import Foundation
import CoreGraphics

/// A stable movement source while the index finger bends to pinch.
enum PinchDragPalm {
    static func measure(points: [CGPoint?], confidences: [Double]) -> CGPoint? {
        guard points.count == 4, confidences.count == 4,
              confidences.allSatisfy({ $0.isFinite && (0.6...1).contains($0) }) else { return nil }
        let valid = points.compactMap { $0 }
        guard valid.count == 4, valid.allSatisfy({
            $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y)
        }) else { return nil }
        return CGPoint(x: valid.reduce(0) { $0 + $1.x } / 4,
                       y: valid.reduce(0) { $0 + $1.y } / 4)
    }
}

enum OneHandDragPhase { case waitingForOpen, ready, confirming, pressed, dragging }

/// Emits intent only. DragOutput owns the matching OS down/up obligation.
struct OneHandDragDetector {
    private var pinch = PinchDetector()
    private(set) var phase: OneHandDragPhase = .waitingForOpen
    private(set) var releasedClick = false
    private var pressedAt: Double?
    private var palmAnchor: CGPoint?
    private var previousPalm: CGPoint?
    private var previousTime: Double?
    private var motionSince: Double?
    private var motionSamples = 0
    var held: Bool { phase == .pressed || phase == .dragging }
    var engaged: Bool { held || phase == .confirming }

    mutating func reset() {
        pinch.reset(); phase = .waitingForOpen; releasedClick = false
        pressedAt = nil; palmAnchor = nil; previousPalm = nil; previousTime = nil
        motionSince = nil; motionSamples = 0
    }

    /// False means uncertain input: the caller must stop movement and release.
    mutating func update(ratio: Double?, palm: CGPoint?, time: Double,
                         bounds: CGRect, threshold: Double) -> Bool {
        releasedClick = false
        guard let ratio, ratio.isFinite, ratio >= 0, let palm,
              palm.x.isFinite, palm.y.isFinite, (0...1).contains(palm.x), (0...1).contains(palm.y),
              time.isFinite, previousTime.map({ time > $0 && time - $0 <= GestureTuning.trackingGraceSeconds }) ?? true,
              previousPalm.map({ hypot(palm.x - $0.x, palm.y - $0.y) <= 0.08 }) ?? true else {
            reset(); return false
        }
        previousPalm = palm; previousTime = time
        pinch.settings.closeRatio = threshold
        let fired = pinch.update(ratio: ratio, time: time)
        if held {
            if ratio > pinch.settings.releaseRatio {
                releasedClick = phase == .pressed
                phase = .waitingForOpen; pressedAt = nil; palmAnchor = nil
                motionSince = nil; motionSamples = 0
            } else if phase == .pressed {
                // Let closure settle before interpreting whole-hand motion as dragging.
                if time - (pressedAt ?? time) < 0.10 {
                    palmAnchor = palm
                } else if let anchor = palmAnchor {
                    // Use unbounded displacement so off-center palms can still initiate
                    // a drag outside the default aiming region, including at screen edges.
                    let travel = 1 - 2 * GestureTuning.softInset
                    let dx = (palm.x - anchor.x) * (bounds.width - 1) / travel
                    let dy = (palm.y - anchor.y) * (bounds.height - 1) / travel
                    if hypot(dx, dy) >= 8 {
                        if motionSince == nil { motionSince = time }
                        motionSamples += 1
                        if motionSamples >= 2 && time - (motionSince ?? time) >= 0.025 { phase = .dragging }
                    } else { motionSince = nil; motionSamples = 0 }
                }
            }
        } else if fired {
            phase = .pressed; pressedAt = time; palmAnchor = palm
        } else {
            switch pinch.phase {
            case .ready: phase = .ready
            case .confirming: phase = .confirming
            case .waitingForOpen, .held: phase = .waitingForOpen
            }
        }
        return true
    }
}
