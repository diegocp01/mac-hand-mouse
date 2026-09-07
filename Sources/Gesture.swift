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

enum ClickMode: String, CaseIterable {
    case twoFingerTap
    case pinch
    case forward

    static func restored(_ value: String?) -> ClickMode {
        value == "dwell" ? .forward : (value.flatMap(ClickMode.init(rawValue:)) ?? .pinch)
    }
}

enum TapPose { case raised, bent, transition, uncertain }

/// A visible raise -> bend -> raise cycle clicks once. Missing observations cancel it.
struct TwoFingerTapDetector {
    enum Phase { case waiting, ready, pressed }
    enum Cancellation { case timedOut, incompleteBend, trackingLost }
    private(set) var phase: Phase = .waiting
    private(set) var cancellation: Cancellation?
    private var raisedSince: Double?
    private var pressSince: Double?
    private var bentSince: Double?
    private var lastTime: Double?
    private var bendSamples = 0
    var shouldFreeze: Bool { phase == .pressed }

    /// The feedback and release event share the same evidence requirement.
    var canReleaseToClick: Bool {
        guard phase == .pressed, bendSamples >= 2,
              let pressSince, let lastTime else { return false }
        return lastTime - pressSince >= 0.05 - 1e-9
    }

    mutating func reset() {
        phase = .waiting; cancellation = nil; raisedSince = nil
        pressSince = nil; bentSince = nil; lastTime = nil; bendSamples = 0
    }

    private mutating func cancel(_ reason: Cancellation) {
        reset(); cancellation = reason
    }

    mutating func update(_ pose: TapPose?, time: Double) -> Bool {
        guard time.isFinite else { cancel(.trackingLost); return false }
        if let lastTime, time <= lastTime || time - lastTime > GestureTuning.trackingGraceSeconds + 1e-9 {
            cancel(.trackingLost)
        }
        lastTime = time
        guard let pose, pose != .uncertain else { cancel(.trackingLost); return false }
        if phase == .pressed {
            // Preparation gets its own bounded allowance. Once a bend is seen,
            // further transition frames never restart its existing release window.
            // These timings are covered synthetically; physical camera trials remain necessary.
            let start = bentSince ?? pressSince ?? time
            let limit = bentSince == nil ? 0.8 : 0.65
            guard time - start <= limit + 1e-9 else { cancel(.timedOut); return false }
            if pose == .bent {
                if bentSince == nil { bentSince = time }
                bendSamples += 1
                return false
            }
            if pose == .transition { return false }
            let clicked = canReleaseToClick
            if clicked { reset() } else { cancel(.incompleteBend) }
            lastTime = time; raisedSince = time
            return clicked
        }
        if pose == .raised {
            if raisedSince == nil { raisedSince = time }
            if time - raisedSince! >= 0.15 - 1e-9 {
                phase = .ready; cancellation = nil
            }
        } else {
            raisedSince = nil
            if phase == .ready {
                phase = .pressed; pressSince = time
                bentSince = pose == .bent ? time : nil
                bendSamples = pose == .bent ? 1 : 0
            }
        }
        return false
    }
}

struct PinchSettings {
    var closeRatio: Double = 0.42
    var releaseRatio: Double { closeRatio + 0.18 }
    var confirmationRatio: Double { closeRatio + 0.06 }
    let holdSeconds = 0.025
    let openSeconds = 0.07
    let cooldownSeconds = 0.30
}

enum PinchPhase { case waitingForOpen, ready, confirming, held }

/// Short occlusions preserve readiness, but never count toward pinch confirmation.
struct PinchDetector {
    var settings = PinchSettings()
    private(set) var phase: PinchPhase = .waitingForOpen
    private var openSince: Double?
    private var closedSince: Double?
    private var closeSamples = 0
    private var lastObserved: Double?
    private var lastTimestamp: Double?
    private var lastClick = -Double.infinity

    var shouldFreeze: Bool { phase == .confirming || phase == .held }

    mutating func reset() {
        phase = .waitingForOpen
        openSince = nil
        closedSince = nil
        closeSamples = 0
        lastObserved = nil
        lastTimestamp = nil
    }

    mutating func update(ratio: Double?, time: Double) -> Bool {
        guard time.isFinite else { reset(); return false }
        if let previous = lastTimestamp, time <= previous { reset(); return false }
        lastTimestamp = time
        if let previous = lastObserved, time - previous > GestureTuning.trackingGraceSeconds {
            reset()
            lastTimestamp = time
        }
        if let ratio, !ratio.isFinite || ratio < 0 { reset(); return false }
        guard let ratio else {
            openSince = nil
            closedSince = nil
            closeSamples = 0
            if phase == .confirming { phase = .ready }
            return false
        }
        lastObserved = time
        if ratio > settings.releaseRatio {
            closedSince = nil
            closeSamples = 0
            if phase == .confirming { phase = .ready }
            if openSince == nil { openSince = time }
            if time - openSince! >= settings.openSeconds { phase = .ready }
            return false
        }
        openSince = nil
        guard phase == .ready || phase == .confirming else { return false }
        let threshold = phase == .confirming ? settings.confirmationRatio : settings.closeRatio
        guard ratio < threshold else {
            phase = .ready
            closedSince = nil
            closeSamples = 0
            return false
        }
        // A physical gesture during cooldown is consumed, never queued for a late click.
        guard time - lastClick >= settings.cooldownSeconds else {
            phase = .held
            closedSince = nil
            closeSamples = 0
            return false
        }
        if closedSince == nil { closedSince = time }
        closeSamples += 1
        phase = .confirming
        if closeSamples >= 2 && time - closedSince! >= settings.holdSeconds {
            lastClick = time
            phase = .held
            closedSince = nil
            closeSamples = 0
            return true
        }
        return false
    }
}

struct DwellSettings {
    /// CTO band 0.5–0.8s. Midpoint default — not pinch's 25ms hold.
    var dwellSeconds: Double = 0.65
    /// Screen points from arm origin; move past this cancels and restarts.
    var moveCancelPoints: Double = 18
    var cooldownSeconds: Double = 0.45
    /// After (re)arm, keep freeze off briefly so aim can track onto the stable target.
    var armFreezeDelaySeconds: Double = 0.10
}

enum DwellPhase { case idle, arming, needMove }

/// Separate dwell physics. Cancel-on-move, one shot, cooldown, no auto-repeat.
struct DwellDetector {
    var settings = DwellSettings()
    private(set) var phase: DwellPhase = .idle
    private var origin: CGPoint?
    private var armingSince: Double?
    private var postFireLock: CGPoint?
    private var lastFire = -Double.infinity
    private var lastObserved: Double?
    private var lastTimestamp: Double?

    /// Fraction of the current observed dwell interval, without advancing its clock.
    var progress: Double {
        guard phase == .arming,
              let started = armingSince,
              let observed = lastObserved,
              settings.dwellSeconds.isFinite,
              settings.dwellSeconds > 0 else { return 0 }
        return min(1, max(0, (observed - started) / settings.dwellSeconds))
    }

    /// Observed dwell time still required. Non-arming phases intentionally report zero.
    var remainingSeconds: Double {
        guard phase == .arming,
              let started = armingSince,
              let observed = lastObserved,
              settings.dwellSeconds.isFinite,
              settings.dwellSeconds > 0 else { return 0 }
        let elapsed = min(settings.dwellSeconds, max(0, observed - started))
        return settings.dwellSeconds - elapsed
    }

    /// Freeze only while arming on a stable target (or post-fire needMove).
    /// Cancel-on-move returns `.idle` (freeze off). Fresh arm waits `armFreezeDelaySeconds` before latching.
    var shouldFreeze: Bool {
        if phase == .needMove { return true }
        guard phase == .arming, let started = armingSince, let t = lastTimestamp else { return false }
        return t - started >= settings.armFreezeDelaySeconds
    }

    mutating func reset() {
        phase = .idle
        origin = nil
        armingSince = nil
        postFireLock = nil
        lastFire = -Double.infinity
        lastObserved = nil
        lastTimestamp = nil
    }

    /// Cancel incomplete dwell work when the hand is not observed. A completed
    /// click remains locked in `needMove`, including its cooldown and lock point.
    mutating func trackingLost() {
        origin = nil
        armingSince = nil
        lastObserved = nil
        if phase == .arming { phase = .idle }
    }

    /// `point` must be an *unfrozen* screen sample (finger target). Freeze only the click aim.
    mutating func update(point: CGPoint, time: Double, tracking: Bool) -> Bool {
        guard tracking else { trackingLost(); return false }
        guard time.isFinite else { trackingLost(); return false }
        if let previous = lastTimestamp, time <= previous { trackingLost(); return false }
        guard point.x.isFinite, point.y.isFinite else { trackingLost(); return false }
        lastTimestamp = time

        // A sparse callback stream cannot turn unobserved time into dwell progress.
        if phase == .arming,
           let previous = lastObserved,
           time - previous > GestureTuning.trackingGraceSeconds + 1e-9 {
            trackingLost()
        }
        lastObserved = time

        // Cooldown consumes stillness — never queue a late click.
        if time - lastFire < settings.cooldownSeconds {
            origin = nil
            armingSince = nil
            return false
        }

        // No auto-repeat: must move after a fire before the next arm.
        if phase == .needMove {
            if let lock = postFireLock,
               hypot(point.x - lock.x, point.y - lock.y) > settings.moveCancelPoints {
                phase = .idle
                postFireLock = nil
            } else {
                return false
            }
        }

        if let origin {
            let moved = hypot(point.x - origin.x, point.y - origin.y)
            if moved > settings.moveCancelPoints {
                // Freeze-release invariant: cancel drops to idle so the pointer
                // can track to the new target. Re-arm only after the next still sample.
                self.origin = nil
                armingSince = nil
                phase = .idle
                return false
            }
        } else {
            origin = point
            armingSince = time
            phase = .arming
            return false
        }

        guard let started = armingSince else {
            armingSince = time
            phase = .arming
            return false
        }

        if time - started >= settings.dwellSeconds {
            lastFire = time
            postFireLock = point
            phase = .needMove
            origin = nil
            armingSince = nil
            return true
        }

        phase = .arming
        return false
    }
}

/// Distances use the actual frame aspect ratio, so rotation and widescreen capture
/// do not distort pinch measurements. Palm length backs up a foreshortened width.
struct HandGeometry {
    static func pinchRatio(thumb: CGPoint, index: CGPoint, indexBase: CGPoint?, littleBase: CGPoint?,
                           wrist: CGPoint?, middleBase: CGPoint?, aspect: Double) -> Double? {
        guard aspect.isFinite, aspect > 0 else { return nil }
        func distance(_ a: CGPoint?, _ b: CGPoint?) -> Double {
            guard let a, let b else { return 0 }
            return hypot(Double(a.x - b.x) * aspect, Double(a.y - b.y))
        }
        let scale = max(distance(indexBase, littleBase), distance(wrist, middleBase) * 0.75)
        guard scale.isFinite, scale > 0.035 else { return nil }
        let ratio = distance(thumb, index) / scale
        return ratio.isFinite ? ratio : nil
    }

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

struct PointerFilter {
    private var position: CGPoint?
    private var lastTime: Double?
    private var lastTarget: CGPoint?
    private var horizontal: PointerAxisMap?
    private var vertical: PointerAxisMap?

    var controlRegion: CGRect {
        let inset = GestureTuning.softInset
        let left = horizontal?.visibleLower ?? inset
        let right = horizontal?.visibleUpper ?? (1 - inset)
        let top = vertical?.visibleLower ?? inset
        let bottom = vertical?.visibleUpper ?? (1 - inset)
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    mutating func reset() { position = nil; lastTime = nil; lastTarget = nil; horizontal = nil; vertical = nil }

    mutating func reanchor(point: CGPoint, cursor: CGPoint, bounds: CGRect, time: Double) {
        reset()
        horizontal = PointerAxisMap(hand: point.x, screen: (cursor.x - bounds.minX) / (bounds.width - 1))
        vertical = PointerAxisMap(hand: point.y, screen: (cursor.y - bounds.minY) / (bounds.height - 1))
        position = cursor; lastTarget = cursor; lastTime = time
    }

    /// Soft-mapped screen target with no EMA / freeze — use for dwell cancel sampling.
    func unfrozenTarget(point: CGPoint, bounds: CGRect, precision: Bool = false) -> CGPoint {
        let x = horizontal?.map(point.x, gain: precision ? 0.35 : 1) ?? SoftMargin.normalize(Double(point.x))
        let y = vertical?.map(point.y, gain: precision ? 0.35 : 1) ?? SoftMargin.normalize(Double(point.y))
        return CGPoint(x: bounds.minX + x * (bounds.width - 1),
                       y: bounds.minY + y * (bounds.height - 1))
    }

    mutating func update(point: CGPoint, bounds: CGRect, time: Double, precision: Bool = false, freeze: Bool) -> CGPoint {
        let target = unfrozenTarget(point: point, bounds: bounds, precision: precision)
        let dt = max(0, min(0.1, time - (lastTime ?? time)))
        lastTime = time
        guard let previous = position else {
            position = target
            lastTarget = target
            return target
        }
        if freeze { return previous }
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
