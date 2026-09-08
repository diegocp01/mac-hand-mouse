import Foundation
import CoreGraphics

/// Validate the hand and cursor before anchoring; legacy modes also require a steady pose.
struct PointerAcquisition {
    private(set) var active = false
    private(set) var owner: String?
    private var candidate: CGPoint?
    private var candidateCursor: CGPoint?
    private var candidateSide: String?
    private var since: Double?
    private var samples = 0

    mutating func interrupt() {
        active = false; candidate = nil; candidateCursor = nil; candidateSide = nil; since = nil; samples = 0
    }
    mutating func reset() { interrupt(); owner = nil }

    mutating func update(point: CGPoint, cursor: CGPoint, side: String?, neutral: Bool, time: Double, immediately: Bool = false) -> Bool {
        guard point.x.isFinite, point.y.isFinite, (0...1).contains(point.x), (0...1).contains(point.y),
              cursor.x.isFinite, cursor.y.isFinite, time.isFinite,
              let side, side == "left" || side == "right", owner == nil || owner == side else {
            interrupt(); return false
        }
        if active { return true }
        if immediately {
            active = true; owner = side
            return true
        }
        guard neutral else { interrupt(); return false }
        if candidateSide != side || candidate.map({ hypot(point.x - $0.x, point.y - $0.y) > 0.025 }) == true ||
            candidateCursor.map({ hypot(cursor.x - $0.x, cursor.y - $0.y) > 3 }) == true ||
            since.map({ time <= $0 }) == true { interrupt() }
        if candidate == nil {
            candidate = point; candidateCursor = cursor; candidateSide = side; since = time
        }
        samples += 1
        if samples >= 4 && time - (since ?? time) >= 0.25 {
            active = true; owner = side
        }
        return active
    }
}

enum ScrollPoseGeometry {
    static func shape(tip: CGPoint, pip: CGPoint, base: CGPoint, aspect: Double) -> FingerShape {
        guard aspect.isFinite, aspect > 0,
              [tip, pip, base].allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }) else { return .uncertain }
        func distance(_ a: CGPoint, _ b: CGPoint) -> Double { hypot((a.x - b.x) * aspect, a.y - b.y) }
        let proximal = distance(pip, base), reach = distance(tip, base), distal = distance(tip, pip)
        guard proximal > 0.015 else { return .uncertain }
        if reach / proximal > 1.6 && reach / max(proximal + distal, 1e-9) > 0.9 { return .extended }
        if reach / proximal < 1.2 { return .folded }
        return .uncertain
    }
}

enum ScrollPhase { case idle, confirming, scrolling }

/// Two extended fingers explicitly enter scrolling; stopping or losing the pose emits no inertia.
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
