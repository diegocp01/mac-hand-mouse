import Foundation
import CoreGraphics

enum GestureTuning {
    static let pointerSmoothingSeconds = 0.025
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

struct PointerFilter {
    private var position: CGPoint?
    private var lastTime: Double?

    mutating func reset() { position = nil; lastTime = nil }

    mutating func update(point: CGPoint, bounds: CGRect, time: Double, freeze: Bool) -> CGPoint {
        let x = min(1, max(0, (point.x - 0.15) / 0.70))
        let y = min(1, max(0, (point.y - 0.15) / 0.70))
        let target = CGPoint(x: bounds.minX + x * (bounds.width - 1),
                             y: bounds.minY + y * (bounds.height - 1))
        let dt = max(0, min(0.1, time - (lastTime ?? time)))
        lastTime = time
        guard let previous = position else { position = target; return target }
        if freeze { return previous }
        let alpha = 1 - exp(-dt / GestureTuning.pointerSmoothingSeconds)
        let result = CGPoint(x: previous.x + (target.x - previous.x) * alpha,
                             y: previous.y + (target.y - previous.y) * alpha)
        position = result
        return result
    }
}
