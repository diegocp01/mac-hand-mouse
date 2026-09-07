import Foundation
import CoreGraphics

enum GestureTuning {
    /// Low speed: heavier smoothing (kill camera jitter). High speed: low lag.
    static let minSmoothingSeconds = 0.008
    static let maxSmoothingSeconds = 0.050
    /// Screen-diagonals/sec at which smoothing reaches the minimum.
    static let velocityRefDiagonalsPerSecond = 1.4
    /// Soft usable inset (was hard crop at 0.15). Wider FOV + tanh softclamp.
    static let softInset = 0.10
    static let softClampK = 1.20
    static let trackingGraceSeconds = 0.12
}

enum ClickMode: String, CaseIterable {
    case pinch
    case dwell
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
    var armFreezeDelaySeconds: Double = 0.08
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

    /// `point` must be an *unfrozen* screen sample (finger target). Freeze only the click aim.
    mutating func update(point: CGPoint, time: Double, tracking: Bool) -> Bool {
        guard time.isFinite else { reset(); return false }
        if let previous = lastTimestamp, time <= previous { reset(); return false }
        lastTimestamp = time

        guard tracking else {
            origin = nil
            armingSince = nil
            if phase == .arming { phase = .idle }
            return false
        }

        // A sparse callback stream cannot turn unobserved time into dwell progress.
        if phase == .arming,
           let previous = lastObserved,
           time - previous > GestureTuning.trackingGraceSeconds {
            origin = nil
            armingSince = nil
            phase = .idle
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

/// Soft camera→[0,1] map. Replaces hard `clamp((t-0.15)/0.70)`.
/// Same idea as a mild 1D softclamp: mid-band nearly linear, gain falls off toward
/// the edges, and the old hard wall at 0.15 is gone (C∞ through the old boundary).
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

    /// Hard crop baseline (for synthetic proofs only).
    static func hardCrop(_ t: Double) -> Double {
        min(1, max(0, (t - 0.15) / 0.70))
    }
}

struct PointerFilter {
    private var position: CGPoint?
    private var lastTime: Double?
    private var lastTarget: CGPoint?

    mutating func reset() { position = nil; lastTime = nil; lastTarget = nil }

    /// Soft-mapped screen target with no EMA / freeze — use for dwell cancel sampling.
    func unfrozenTarget(point: CGPoint, bounds: CGRect) -> CGPoint {
        let x = SoftMargin.normalize(Double(point.x))
        let y = SoftMargin.normalize(Double(point.y))
        return CGPoint(x: bounds.minX + x * (bounds.width - 1),
                       y: bounds.minY + y * (bounds.height - 1))
    }

    mutating func update(point: CGPoint, bounds: CGRect, time: Double, freeze: Bool) -> CGPoint {
        let target = unfrozenTarget(point: point, bounds: bounds)
        let dt = max(0, min(0.1, time - (lastTime ?? time)))
        lastTime = time
        guard let previous = position else {
            position = target
            lastTarget = target
            return target
        }
        if freeze { return previous }
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
        let result = CGPoint(x: previous.x + (target.x - previous.x) * alpha,
                             y: previous.y + (target.y - previous.y) * alpha)
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
