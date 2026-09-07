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

    mutating func update(point: CGPoint, bounds: CGRect, time: Double, freeze: Bool) -> CGPoint {
        let x = SoftMargin.normalize(Double(point.x))
        let y = SoftMargin.normalize(Double(point.y))
        let target = CGPoint(x: bounds.minX + x * (bounds.width - 1),
                             y: bounds.minY + y * (bounds.height - 1))
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
