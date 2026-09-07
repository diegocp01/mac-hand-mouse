import Foundation
import CoreGraphics

var checks = 0
func check(_ condition: Bool, _ message: String) {
    checks += 1
    if !condition { fatalError(message) }
}
var pinch = PinchDetector()
check(!pinch.update(ratio: 0.1, time: 0), "Starting with a pinch must not click")
check(!pinch.update(ratio: 0.1, time: 0.1), "Held initial pinch must not click")
check(!pinch.update(ratio: 0.8, time: 0.2), "Opening must not click")
check(!pinch.update(ratio: 0.8, time: 0.32), "Open dwell arms")
check(!pinch.update(ratio: 0.1, time: 0.4), "Short pinch must not click")
check(pinch.update(ratio: 0.1, time: 0.48), "Deliberate pinch clicks")
check(!pinch.update(ratio: 0.1, time: 1), "Holding must not repeat")
check(!pinch.update(ratio: 0.38, time: 1.1), "Threshold noise must not rearm")
check(!pinch.update(ratio: 0.1, time: 1.2), "Noise must not duplicate click")
_ = pinch.update(ratio: 0.8, time: 1.3)
_ = pinch.update(ratio: 0.8, time: 1.42)
_ = pinch.update(ratio: 0.1, time: 1.5)
check(pinch.update(ratio: 0.1, time: 1.58), "Second separate pinch clicks")
_ = pinch.update(ratio: 0.8, time: 2)
_ = pinch.update(ratio: 0.8, time: 2.12)
pinch.reset()
_ = pinch.update(ratio: 0.1, time: 2.2)
check(!pinch.update(ratio: 0.1, time: 2.3), "Tracking loss must disarm")
_ = pinch.update(ratio: 0.8, time: 3)
_ = pinch.update(ratio: 0.8, time: 3.12)
_ = pinch.update(ratio: 0.1, time: 3.2)
_ = pinch.update(ratio: 0.35, time: 3.24)
check(!pinch.update(ratio: 0.1, time: 3.28), "Broken pinch dwell must restart")
check(!pinch.update(ratio: .nan, time: 4), "Invalid frame must disarm")

// A gentle pinch should click after one 30 fps interval, but never on one frame.
var gentle = PinchDetector()
_ = gentle.update(ratio: 0.8, time: 0)
_ = gentle.update(ratio: 0.8, time: 0.12)
check(!gentle.update(ratio: 0.32, time: 0.2), "One gentle-pinch frame must not click")
check(!gentle.update(ratio: 0.32, time: 0.22), "Pinch shorter than 30 ms must not click")
check(gentle.update(ratio: 0.32, time: 0.234), "Gentle pinch must click within one 30 fps interval")
check(!gentle.update(ratio: 0.32, time: 0.30), "Holding gentle pinch must not repeat")
_ = gentle.update(ratio: 0.8, time: 0.31)
_ = gentle.update(ratio: 0.8, time: 0.42)
_ = gentle.update(ratio: 0.32, time: 0.43)
check(!gentle.update(ratio: 0.32, time: 0.47), "New sensitivity must preserve click cooldown")
check(gentle.update(ratio: 0.32, time: 0.55), "A rearmed pinch clicks after cooldown")
gentle.reset()
_ = gentle.update(ratio: 0.8, time: 1)
_ = gentle.update(ratio: 0.8, time: 1.12)
_ = gentle.update(ratio: 0.35, time: 1.2)
check(!gentle.update(ratio: 0.35, time: 1.3), "Fingers outside close threshold must not click")
_ = gentle.update(ratio: 0.32, time: 1.4)
check(gentle.update(ratio: 0.32, time: 1.434), "Rearmed gentle pinch clicks")
_ = gentle.update(ratio: 0.8, time: 2.0)
_ = gentle.update(ratio: 0.8, time: 2.05)
_ = gentle.update(ratio: 0.32, time: 2.06)
check(!gentle.update(ratio: 0.32, time: 2.1), "Brief reopening must not rearm even after cooldown")

var pointer = PointerFilter()
let bounds = CGRect(x: -1920, y: 100, width: 1920, height: 1080)
check(pointer.update(point: CGPoint(x: 0, y: 0), bounds: bounds, time: 0, freeze: false) == CGPoint(x: -1920, y: 100), "Clamp top left on offset display")
let moved = pointer.update(point: CGPoint(x: 1, y: 1), bounds: bounds, time: 0.03, freeze: false)
check(moved.x > -1920 && moved.x < -1, "Smooth movement")
check(pointer.update(point: CGPoint(x: 0, y: 0), bounds: bounds, time: 0.06, freeze: true) == moved, "Pinch freezes pointer at click target")
pointer.reset()
check(pointer.update(point: CGPoint(x: 1, y: 1), bounds: bounds, time: 1, freeze: false) == CGPoint(x: -1, y: 1179), "Clamp bottom right inside display")

// Settling targets measure smoothing alone, not camera/Vision end-to-end latency.
for fps in [30.0, 60.0] {
    var responsive = PointerFilter()
    let screen = CGRect(x: 0, y: 0, width: 1001, height: 1001)
    let start = CGPoint(x: 0.15, y: 0.15)
    let target = CGPoint(x: 0.85, y: 0.85)
    _ = responsive.update(point: start, bounds: screen, time: 0, freeze: false)
    var result = CGPoint.zero
    for frame in 1...Int(fps / 10) {
        result = responsive.update(point: target, bounds: screen, time: Double(frame) / fps, freeze: false)
        check(result.x >= 0 && result.x <= 1000, "Faster pointer must not overshoot at \(fps) fps")
    }
    check(result.x > 975, "Pointer must settle within 2.5% of fingertip target after 100 ms at \(fps) fps")
}
var partialPinch = PointerFilter()
_ = partialPinch.update(point: CGPoint(x: 0.2, y: 0.2), bounds: bounds, time: 0, freeze: false)
let aiming = partialPinch.update(point: CGPoint(x: 0.7, y: 0.7), bounds: bounds, time: 0.04,
                                 freeze: 0.43 < GestureTuning.pointerFreezeRatio)
check(aiming.x > -1700, "A partial pinch must still let the index finger aim")
let pinching = partialPinch.update(point: CGPoint(x: 0.5, y: 0.5), bounds: bounds, time: 0.08,
                                   freeze: 0.32 < GestureTuning.pointerFreezeRatio)
check(pinching == aiming, "A clicking pinch must preserve the aimed position")
print("Passed \(checks) gesture and pointer checks.")
