import Foundation
import CoreGraphics

/// Ownership is session-scoped, not Vision result order. The other side is only a modifier.
struct HandOwnership {
    private(set) var side: String?

    mutating func reset() { side = nil }
    mutating func lock(_ acquiredSide: String?) {
        if side == nil, let acquiredSide, ["left", "right"].contains(acquiredSide) { side = acquiredSide }
    }
    func primaryIndex(in sides: [String?]) -> Int? {
        if let side {
            let matches = sides.indices.filter { sides[$0] == side }
            return matches.count == 1 ? matches[0] : nil
        }
        // Establish the pointer with one hand first. Never guess when both arrive together.
        guard sides.count == 1, let first = sides[0], ["left", "right"].contains(first) else { return nil }
        return 0
    }
}

enum LPoseGeometry {
    /// Both fingers extended, other fingers folded, and thumb/index roughly perpendicular.
    /// Camera confidence checks happen before this aspect-corrected geometry is evaluated.
    static func matches(thumbTip: CGPoint, thumbIP: CGPoint, thumbBase: CGPoint,
                        indexTip: CGPoint, indexPIP: CGPoint, indexBase: CGPoint,
                        otherFingersFolded: Bool, aspect: Double) -> Bool {
        guard otherFingersFolded, aspect.isFinite, aspect > 0,
              [thumbTip, thumbIP, thumbBase, indexTip, indexPIP, indexBase].allSatisfy({
                  $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y)
              }),
              ScrollPoseGeometry.shape(tip: indexTip, pip: indexPIP, base: indexBase, aspect: aspect) == .extended,
              ScrollPoseGeometry.shape(tip: thumbTip, pip: thumbIP, base: thumbBase, aspect: aspect) == .extended else { return false }
        let thumb = CGPoint(x: (thumbTip.x - thumbBase.x) * aspect, y: thumbTip.y - thumbBase.y)
        let index = CGPoint(x: (indexTip.x - indexBase.x) * aspect, y: indexTip.y - indexBase.y)
        let denominator = hypot(thumb.x, thumb.y) * hypot(index.x, index.y)
        guard denominator > 0.001 else { return false }
        let cosine = (thumb.x * index.x + thumb.y * index.y) / denominator
        return abs(cosine) <= 0.5 // 60–120 degrees, including mirrored L poses.
    }
}

enum TwoHandDragPhase { case idle, confirming, dragging, needsRelease }

struct TwoHandDragDetector {
    private(set) var phase: TwoHandDragPhase = .idle
    private(set) var progress = 0.0
    private var since: Double?
    private var lastTime: Double?
    private var samples = 0
    private var releaseSince: Double?
    private var releaseSamples = 0

    /// A canceled/finished gesture cannot restart from poses that were already held.
    mutating func interrupt() {
        if phase != .idle { phase = .needsRelease }
        progress = 0
        since = nil; lastTime = nil; samples = 0
        releaseSince = nil; releaseSamples = 0
    }

    mutating func update(bothL: Bool, visiblyReleased: Bool, time: Double) {
        guard time.isFinite else { interrupt(); return }
        if let previous = lastTime, time <= previous || time - previous > GestureTuning.trackingGraceSeconds + 1e-9 {
            interrupt()
        }
        lastTime = time
        guard bothL else {
            // Uncertain tracking releases immediately, but is not evidence of intent.
            if phase == .confirming || phase == .dragging { interrupt(); lastTime = time }
            if phase == .needsRelease && visiblyReleased {
                if releaseSince == nil { releaseSince = time }
                releaseSamples += 1
                if releaseSamples >= 3 && time - (releaseSince ?? time) >= 0.12 {
                    phase = .idle; since = nil; samples = 0
                }
            } else { releaseSince = nil; releaseSamples = 0 }
            return
        }
        releaseSince = nil; releaseSamples = 0
        guard phase != .needsRelease && phase != .dragging else { return }
        if phase == .idle { phase = .confirming; since = time; samples = 0 }
        samples += 1
        progress = min(1, max(0, (time - (since ?? time)) / 0.25))
        if samples >= 4 && time - (since ?? time) >= 0.25 { phase = .dragging }
    }
}

enum DragEventKind { case down, moved, up }
struct DragEvent { var kind: DragEventKind; var location: CGPoint }

/// Shared, testable button lifecycle. Practice outputs can only release an existing system hold.
struct DragOutput {
    private(set) var heldLocation: CGPoint?

    mutating func dispatch(_ step: InteractionStep, post: ([DragEvent]) -> Bool) -> Bool {
        var proposed = self
        guard post(proposed.update(step)) else { return false }
        self = proposed
        return true
    }

    mutating func release() -> [DragEvent] {
        guard let location = heldLocation else { return [] }
        heldLocation = nil
        return [DragEvent(kind: .up, location: location)]
    }

    mutating func update(_ step: InteractionStep) -> [DragEvent] {
        guard step.systemDragging, step.blocked == nil, let location = step.systemLocation,
              location.x.isFinite, location.y.isFinite else { return release() }
        let kind: DragEventKind = heldLocation == nil ? .down : .moved
        heldLocation = location
        return [DragEvent(kind: kind, location: location)]
    }
}
