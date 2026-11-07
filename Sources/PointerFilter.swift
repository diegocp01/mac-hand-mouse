import Foundation
import CoreGraphics

enum GestureTuning {
    /// Low speed: heavier smoothing (kill camera jitter). High speed: low lag.
    static let minSmoothingSeconds = 0.008
    static let maxSmoothingSeconds = 0.050
    /// Screen-diagonals/sec at which smoothing reaches the minimum.
    static let velocityRefDiagonalsPerSecond = 1.4
    /// Comfortable fingertip travel leaves room for the rest of the hand in view.
    static let softInset = 0.22
    static let softClampK = 1.20
    static let trackingGraceSeconds = 0.12
}

/// Letterboxes the camera frame inside the preview so overlays match the capture aspect.
struct HandGeometry {
    static func fittedRect(in bounds: CGRect, aspect: CGFloat) -> CGRect {
        let width = min(bounds.width, bounds.height * aspect)
        let height = width / aspect
        return CGRect(x: bounds.minX + (bounds.width - width) / 2,
                      y: bounds.minY + (bounds.height - height) / 2, width: width, height: height)
    }
}

/// Smooth, bounded mapping for the default fingertip travel region.
enum SoftMargin {
    static func normalize(_ t: Double) -> Double {
        guard t.isFinite else { return 0.5 }
        let inset = GestureTuning.softInset
        let x = (t - inset) / (1 - 2 * inset)
        let k = GestureTuning.softClampK
        let z = (x - 0.5) * 2
        let y = Foundation.tanh(k * z) / Foundation.tanh(k)
        return min(1, max(0, 0.5 + 0.5 * y))
    }

}

/// A no-jump anchor with reachable endpoints on both sides. A translated,
/// already-clamped absolute map can otherwise make one display edge unreachable.
struct PointerAxisMap {
    let hand: Double
    let screen: Double
    let lower: Double
    let upper: Double

    init(hand: Double, screen: Double) {
        self.hand = min(1, max(0, hand))
        self.screen = min(1, max(0, screen))
        // Keep useful travel on each side when resuming off-center.
        lower = max(0, min(GestureTuning.softInset, self.hand - 0.12))
        upper = min(1, max(1 - GestureTuning.softInset, self.hand + 0.12))
    }

    func map(_ input: Double, gain: Double = 1) -> Double {
        let value = hand + (input - hand) * gain
        if value == hand { return screen }
        let left = value < hand
        let span = left ? hand - lower : upper - hand
        let distance = left ? screen : 1 - screen
        guard span > 0, distance > 0 else { return left ? 0 : 1 }
        let u = min(1, max(0, abs(value - hand) / span))
        // Preserve fine aiming near the resume position, then smoothly increase
        // gain if more screen distance remains than the available hand travel.
        let linear = min(1, span / ((1 - 2 * GestureTuning.softInset) * distance))
        let travel = distance * (linear * u + (1 - linear) * u * u)
        return min(1, max(0, screen + (left ? -travel : travel)))
    }

    var visibleLower: Double { screen == 0 ? hand : lower }
    var visibleUpper: Double { screen == 1 ? hand : upper }
}

/// Fine corrections use less travel without changing the target when speed changes.
/// The bounded, position-based offset preserves screen-edge reach and never decays at rest.
private struct SteadyAimMotion {
    private var hand: CGPoint?
    private var baseline: CGPoint?
    private var target: CGPoint?

    mutating func reanchor(hand: CGPoint, cursor: CGPoint) {
        self.hand = hand; baseline = cursor; target = cursor
    }

    mutating func update(hand: CGPoint, baseline: CGPoint, bounds: CGRect, dt: Double) -> CGPoint {
        guard let oldHand = self.hand, let oldBaseline = self.baseline, let oldTarget = target, dt > 0 else {
            reanchor(hand: hand, cursor: baseline)
            return baseline
        }
        let speed = hypot(hand.x - oldHand.x, hand.y - oldHand.y) / dt
        let blend = min(1, max(0, (speed - 0.04) / (0.25 - 0.04)))
        let gain = 0.25 + 0.75 * blend * blend * (3 - 2 * blend)
        func advance(_ old: Double, _ delta: Double, _ base: Double, _ low: Double, _ high: Double) -> Double {
            let maxOffset = min(48.0, (high - low) / 4)
            let edgeDistance = max(0, min(base - low, high - base))
            let edgeBlend = min(1, edgeDistance / (2 * maxOffset))
            let limit = maxOffset * edgeBlend * edgeBlend * (3 - 2 * edgeBlend)
            return min(high, max(low, min(base + limit, max(base - limit, old + gain * delta))))
        }
        let next = CGPoint(
            x: advance(oldTarget.x, baseline.x - oldBaseline.x, baseline.x, bounds.minX, bounds.maxX - 1),
            y: advance(oldTarget.y, baseline.y - oldBaseline.y, baseline.y, bounds.minY, bounds.maxY - 1))
        self.hand = hand; self.baseline = baseline; target = next
        return next
    }
}

struct PointerFilter {
    private var position: CGPoint?
    private var lastTime: Double?
    private var lastTarget: CGPoint?
    private var horizontal: PointerAxisMap?
    private var vertical: PointerAxisMap?
    private var steadyMotion = SteadyAimMotion()
    private var wasFrozen = false
    private var steadyAimMode: Bool?

    var controlRegion: CGRect {
        let inset = GestureTuning.softInset
        let left = horizontal?.visibleLower ?? inset
        let right = horizontal?.visibleUpper ?? (1 - inset)
        let top = vertical?.visibleLower ?? inset
        let bottom = vertical?.visibleUpper ?? (1 - inset)
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    mutating func reset() {
        position = nil; lastTime = nil; lastTarget = nil; horizontal = nil; vertical = nil
        steadyMotion = SteadyAimMotion(); wasFrozen = false; steadyAimMode = nil
    }

    mutating func reanchor(point: CGPoint, cursor: CGPoint, bounds: CGRect, time: Double) {
        reset()
        horizontal = PointerAxisMap(hand: point.x, screen: (cursor.x - bounds.minX) / (bounds.width - 1))
        vertical = PointerAxisMap(hand: point.y, screen: (cursor.y - bounds.minY) / (bounds.height - 1))
        position = cursor; lastTarget = cursor; lastTime = time
        steadyMotion.reanchor(hand: point, cursor: cursor)
    }

    /// Soft-mapped screen target with no EMA / freeze — use for dwell cancel sampling.
    func unfrozenTarget(point: CGPoint, bounds: CGRect, precision: Bool = false) -> CGPoint {
        let x = horizontal?.map(point.x, gain: precision ? 0.35 : 1) ?? SoftMargin.normalize(Double(point.x))
        let y = vertical?.map(point.y, gain: precision ? 0.35 : 1) ?? SoftMargin.normalize(Double(point.y))
        return CGPoint(x: bounds.minX + x * (bounds.width - 1),
                       y: bounds.minY + y * (bounds.height - 1))
    }

    mutating func update(point: CGPoint, bounds: CGRect, time: Double, precision: Bool = false,
                         steadyAim: Bool = false, freeze: Bool) -> CGPoint {
        var target = unfrozenTarget(point: point, bounds: bounds, precision: precision)
        let dt = max(0, min(0.1, time - (lastTime ?? time)))
        lastTime = time
        guard let previous = position else {
            position = target
            lastTarget = target
            steadyMotion.reanchor(hand: point, cursor: target)
            steadyAimMode = steadyAim
            return target
        }
        if let previousMode = steadyAimMode, previousMode != steadyAim {
            // Dragging uses full travel. Changing paths must discard the fine-motion offset.
            reanchor(point: point, cursor: previous, bounds: bounds, time: time)
            steadyAimMode = steadyAim; wasFrozen = freeze
            return previous
        }
        steadyAimMode = steadyAim
        if freeze { wasFrozen = true; return previous }
        if steadyAim && wasFrozen {
            reanchor(point: point, cursor: previous, bounds: bounds, time: time)
            return previous
        }
        wasFrozen = false
        if steadyAim {
            target = steadyMotion.update(hand: point, baseline: target, bounds: bounds, dt: dt)
        } else {
            steadyMotion.reanchor(hand: point, cursor: target)
        }
        // Rebase at display edges so reversing direction has no hidden dead zone.
        if target.x <= bounds.minX || target.x >= bounds.maxX - 1 {
            horizontal = PointerAxisMap(hand: point.x, screen: target.x <= bounds.minX ? 0 : 1)
        }
        if target.y <= bounds.minY || target.y >= bounds.maxY - 1 {
            vertical = PointerAxisMap(hand: point.y, screen: target.y <= bounds.minY ? 0 : 1)
        }
        let diag = max(hypot(bounds.width, bounds.height), 1)
        let rawSpeed: Double
        if let lastTarget, dt > 1e-6 {
            rawSpeed = hypot(target.x - lastTarget.x, target.y - lastTarget.y) / dt
        } else {
            rawSpeed = hypot(target.x - previous.x, target.y - previous.y) / max(dt, 1e-6)
        }
        lastTarget = target
        let vNorm = rawSpeed / diag
        let blend = min(1, max(0, vNorm / GestureTuning.velocityRefDiagonalsPerSecond))
        let tau = GestureTuning.maxSmoothingSeconds * (1 - blend)
            + GestureTuning.minSmoothingSeconds * blend
        let alpha = 1 - exp(-dt / max(tau, 1e-4))
        func settle(_ old: Double, _ target: Double, _ low: Double, _ high: Double) -> Double {
            // Normalizing an exact resume position can introduce roundoff only.
            if abs(target - old) < 1e-9 { return old }
            let next = old + (target - old) * alpha
            // Reach actual corner pixels instead of approaching them forever.
            if (target == low || target == high) && abs(target - next) < 0.5 { return target }
            return next
        }
        let result = CGPoint(x: settle(previous.x, target.x, bounds.minX, bounds.maxX - 1),
                             y: settle(previous.y, target.y, bounds.minY, bounds.maxY - 1))
        position = result
        return result
    }
}

enum SafetyPolicy {
    /// CGEvent click injection only when every latch is closed.
    static func shouldInjectClick(gestureFired: Bool, allowClicks: Bool, axTrusted: Bool, pointerControlEnabled: Bool) -> Bool {
        gestureFired && allowClicks && axTrusted && pointerControlEnabled
    }
}
