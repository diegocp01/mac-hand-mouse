import Foundation
import CoreGraphics

enum GestureTuning {
    static let pinchCloseRatio = 0.34
    static let pinchReleaseRatio = 0.48
    static let pointerFreezeRatio = 0.38
    static let pinchHoldSeconds = 0.030
    static let pointerSmoothingSeconds = 0.025
}

/// Hysteresis and time-based debounce prevent duplicate clicks and tracking-loss clicks.
struct PinchDetector {
    private var armed = false
    private var openSince: Double?
    private var closedSince: Double?
    private var lastClick = -Double.infinity

    mutating func reset() {
        armed = false
        openSince = nil
        closedSince = nil
    }

    mutating func update(ratio: Double, time: Double) -> Bool {
        guard ratio.isFinite else { reset(); return false }
        if ratio > GestureTuning.pinchReleaseRatio {
            closedSince = nil
            if openSince == nil { openSince = time }
            if time - openSince! >= 0.10 { armed = true }
        } else {
            openSince = nil
            if ratio < GestureTuning.pinchCloseRatio && armed {
                if closedSince == nil { closedSince = time }
                if time - closedSince! >= GestureTuning.pinchHoldSeconds && time - lastClick >= 0.30 {
                    armed = false
                    closedSince = nil
                    lastClick = time
                    return true
                }
            } else {
                closedSince = nil
            }
        }
        return false
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
