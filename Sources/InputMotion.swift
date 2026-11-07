import Foundation
import CoreGraphics

/// A valid hand, cursor, and hand side take control immediately at the existing
/// cursor. The owner is remembered so another hand cannot inherit the session.
struct PointerAcquisition {
    private(set) var active = false
    private(set) var owner: String?

    mutating func interrupt() { active = false }
    mutating func reset() { active = false; owner = nil }

    mutating func update(point: CGPoint, cursor: CGPoint, side: String?) -> Bool {
        guard point.x.isFinite, point.y.isFinite, (0...1).contains(point.x), (0...1).contains(point.y),
              cursor.x.isFinite, cursor.y.isFinite,
              let side, side == "left" || side == "right", owner == nil || owner == side else {
            interrupt(); return false
        }
        active = true; owner = side
        return true
    }
}

/// Extended versus folded finger shapes from three joints, corrected for the
/// frame aspect ratio. Used for the L pose, release evidence, and diagnostics.
enum FingerGeometry {
    struct Measurement {
        let reachRatio: Double
        let straightness: Double

        func shape(foldedReachLimit: Double) -> FingerShape {
            if reachRatio > 1.6 && straightness > 0.9 { return .extended }
            if reachRatio < foldedReachLimit { return .folded }
            return .uncertain
        }
    }

    static func measure(tip: CGPoint, pip: CGPoint, base: CGPoint, aspect: Double) -> Measurement? {
        guard aspect.isFinite, aspect > 0,
              [tip, pip, base].allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }) else { return nil }
        func distance(_ a: CGPoint, _ b: CGPoint) -> Double { hypot((a.x - b.x) * aspect, a.y - b.y) }
        let proximal = distance(pip, base), reach = distance(tip, base), distal = distance(tip, pip)
        guard proximal > 0.015 else { return nil }
        return Measurement(reachRatio: reach / proximal, straightness: reach / max(proximal + distal, 1e-9))
    }

    static func shape(tip: CGPoint, pip: CGPoint, base: CGPoint, aspect: Double,
                      foldedReachLimit: Double = 1.2) -> FingerShape {
        measure(tip: tip, pip: pip, base: base, aspect: aspect)?.shape(foldedReachLimit: foldedReachLimit) ?? .uncertain
    }
}

/// A stable movement source while the fingertips pinch: the mean of four
/// confident palm joints, or nil when any of them is missing or unreliable.
enum PalmGeometry {
    static func center(points: [CGPoint?], confidences: [Double]) -> CGPoint? {
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

enum ScrollPhase { case idle, confirming, scrolling }

/// A held pinch explicitly enters scrolling; stopping or losing the pose emits no inertia.
struct ScrollDetector {
    private(set) var phase: ScrollPhase = .idle
    private var since: Double?
    private var lastTime: Double?
    private var anchor: CGPoint?
    private var lastY: Double?
    private var remainder = 0.0
    private var samples = 0

    mutating func reset() {
        phase = .idle; since = nil; lastTime = nil; anchor = nil; lastY = nil; remainder = 0; samples = 0
    }
    mutating func update(point: CGPoint?, time: Double) -> Int32 {
        guard let point, time.isFinite, point.x.isFinite, point.y.isFinite,
              (0...1).contains(point.x), (0...1).contains(point.y) else { reset(); return 0 }
        let dt = time - (lastTime ?? time)
        if lastTime != nil && (dt <= 0 || dt > GestureTuning.trackingGraceSeconds + 1e-9) { reset() }
        lastTime = time
        if phase == .idle {
            phase = .confirming; since = time; anchor = point; samples = 1
            return 0
        }
        if phase == .confirming {
            if let anchor, hypot(point.x - anchor.x, point.y - anchor.y) > 0.025 {
                reset(); return 0
            }
            samples += 1
            if samples >= 4 && time - (since ?? time) >= 0.25 {
                phase = .scrolling; lastY = point.y
            }
            return 0
        }
        let delta = (lastY ?? point.y) - point.y
        lastY = point.y
        // Discontinuities cancel instead of becoming a page-sized scroll.
        guard abs(delta) <= 0.06, dt > 0 else { reset(); return 0 }
        let pixels = max(-600 * dt, min(600 * dt, delta * 1000)) + remainder
        let whole = pixels.rounded(.towardZero)
        remainder = pixels - whole
        return Int32(whole)
    }
}

/// Independent of camera/UI APIs so repeated keys and overlapping system pauses are testable.
struct ActivationPolicy {
    var awake = true
    var displaysAwake = true
    var sessionActive = true
    private var keyHeld = false
    var canResume: Bool { awake && displaysAwake && sessionActive }
    mutating func press() -> Bool {
        guard !keyHeld else { return false }
        keyHeld = true
        return canResume
    }
    mutating func release() { keyHeld = false }
}
