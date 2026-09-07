import Foundation
import CoreGraphics

var checks = 0
func check(_ condition: Bool, _ message: String) {
    checks += 1
    if !condition { fatalError(message) }
}

struct Simulation {
    var detector = PinchDetector()
    var now = 0.0
    var clicks = 0
    @discardableResult mutating func frame(_ ratio: Double?, after interval: Double = 1.0 / 30) -> Bool {
        now += interval
        let click = detector.update(ratio: ratio, time: now)
        if click { clicks += 1 }
        return click
    }
    mutating func frames(_ ratio: Double?, count: Int) {
        for _ in 0..<count { frame(ratio) }
    }
    mutating func ready() { frames(0.9, count: 5) }
}

var s = Simulation()
s.frames(0.1, count: 12)
check(s.clicks == 0, "Starting with closed fingers must not click")
s.ready()
check(s.detector.phase == .ready, "Open fingers arm clicking")
check(!s.frame(0.40), "One close frame cannot click")
check(s.detector.phase == .confirming && s.detector.shouldFreeze, "Confirmation holds the target")
check(s.frame(0.40), "Gentle pinch clicks after a second observed frame")
s.frames(0.40, count: 30)
check(s.clicks == 1 && s.detector.phase == .held, "Held pinch sends exactly one click")
s.frames(0.52, count: 10)
check(s.detector.phase == .held, "Threshold noise cannot rearm a held pinch")
s.ready()
s.frames(0.40, count: 3)
check(s.clicks == 2, "A separated second pinch clicks")

var jitter = Simulation(); jitter.ready()
_ = jitter.frame(0.40)
check(jitter.frame(0.45), "Small threshold jitter does not cancel a deliberate pinch")
var abandoned = Simulation(); abandoned.ready()
_ = abandoned.frame(0.40)
_ = abandoned.frame(0.55)
check(abandoned.detector.phase == .ready, "A clearly abandoned pinch cancels confirmation")

var gap = Simulation(); gap.ready()
gap.frame(nil)
check(gap.detector.phase == .ready, "One brief occluded frame preserves readiness")
check(!gap.frame(0.39), "Reacquisition requires a fresh confirmation frame")
check(gap.frame(0.39), "Confirmed pinch after a short occlusion clicks")
gap.frame(nil)
gap.frames(0.39, count: 3)
check(gap.clicks == 1, "A short occlusion during a held pinch never repeats")

var interrupted = Simulation(); interrupted.ready()
interrupted.frame(0.40)
interrupted.frame(nil)
check(!interrupted.frame(0.40), "A missing frame does not count toward pinch dwell")
check(interrupted.frame(0.40), "Fresh confirmation after occlusion can click")

var lost = Simulation(); lost.ready()
lost.frames(nil, count: 5)
check(lost.detector.phase == .waitingForOpen, "Long tracking loss disarms")
lost.frames(0.1, count: 8)
check(lost.clicks == 0, "Reappearing pinched cannot click")
lost.ready(); lost.frames(0.1, count: 3)
check(lost.clicks == 1, "Opening after tracking loss restores clicking")

var silentGap = Simulation(); silentGap.ready()
check(!silentGap.frame(0.1, after: 0.3), "A gap with no callbacks also disarms")
silentGap.frames(0.1, count: 2)
check(silentGap.clicks == 0, "A long silent gap requires reopening")

var briefOpen = Simulation(); briefOpen.ready(); briefOpen.frames(0.1, count: 3)
briefOpen.frames(0.1, count: 15)
briefOpen.frames(0.9, count: 2)
briefOpen.frames(0.1, count: 3)
check(briefOpen.clicks == 1, "A brief noisy opening cannot rearm after cooldown")

var cooldown = Simulation(); cooldown.ready(); cooldown.frames(0.1, count: 2)
cooldown.frames(0.9, count: 4)
cooldown.frames(0.1, count: 15)
check(cooldown.clicks == 1, "A too-fast second pinch is consumed, not queued for a late click")
cooldown.ready(); cooldown.frames(0.1, count: 3)
check(cooldown.clicks == 2, "A later deliberate pinch still clicks")

var noise = Simulation(); noise.ready()
noise.frame(0.1); noise.frame(0.9)
check(noise.clicks == 0, "One-frame spike cannot click")
noise.ready(); noise.frame(.nan)
check(noise.detector.phase == .waitingForOpen, "Invalid coordinates disarm")
noise.ready(); noise.detector.reset(); noise.frames(0.1, count: 5)
check(noise.clicks == 0, "Pause or control change disarms")
noise.ready()
check(!noise.detector.update(ratio: 0.1, time: noise.now - 1), "Out-of-order timestamps cannot click")
check(noise.detector.phase == .waitingForOpen, "Clock reversal disarms")

for fps in [15.0, 30.0, 60.0] {
    var cadence = Simulation()
    for _ in 0..<Int(fps / 2) { cadence.frame(0.9, after: 1 / fps) }
    for _ in 0..<Int(fps / 2) { cadence.frame(0.40, after: 1 / fps) }
    check(cadence.clicks == 1, "One click at \(fps) fps")
}
for (threshold, ratio, expected) in [(0.34, 0.40, 0), (0.42, 0.40, 1), (0.50, 0.48, 1)] {
    var feel = Simulation(); feel.detector.settings.closeRatio = threshold
    feel.ready(); feel.frames(ratio, count: 5)
    check(feel.clicks == expected, "Sensitivity preset accepts the intended pinch range")
}

var pointer = PointerFilter()
let bounds = CGRect(x: -1920, y: 100, width: 1920, height: 1080)
check(pointer.update(point: .zero, bounds: bounds, time: 0, freeze: false) == CGPoint(x: -1920, y: 100), "Clamp top left of offset display")
let moved = pointer.update(point: CGPoint(x: 1, y: 1), bounds: bounds, time: 0.03, freeze: false)
check(moved.x > -1920 && moved.x < -1, "Smooth pointer movement")
check(pointer.update(point: .zero, bounds: bounds, time: 0.06, freeze: true) == moved, "Pinch holds the exact click target")
pointer.reset()
check(pointer.update(point: CGPoint(x: 1, y: 1), bounds: bounds, time: 1, freeze: false) == CGPoint(x: -1, y: 1179), "Clamp bottom right inside display")
for fps in [30.0, 60.0] {
    var response = PointerFilter()
    let screen = CGRect(x: 0, y: 0, width: 1001, height: 1001)
    _ = response.update(point: CGPoint(x: 0.15, y: 0.15), bounds: screen, time: 0, freeze: false)
    var result = CGPoint.zero
    for frame in 1...Int(fps / 10) {
        result = response.update(point: CGPoint(x: 0.85, y: 0.85), bounds: screen, time: Double(frame) / fps, freeze: false)
        check(result.x >= 0 && result.x <= 1000, "No overshoot at \(fps) fps")
    }
    check(result.x > 975, "Settle within 2.5% after 100 ms at \(fps) fps")
}

// Integrate the actual gesture freeze decision with pointer movement.
var aim = Simulation(); aim.ready()
var aimedPointer = PointerFilter()
let target = aimedPointer.update(point: CGPoint(x: 0.5, y: 0.5), bounds: bounds, time: aim.now, freeze: false)
aim.frame(0.40)
let firstClose = aimedPointer.update(point: CGPoint(x: 0.4, y: 0.4), bounds: bounds, time: aim.now, freeze: aim.detector.shouldFreeze)
check(firstClose == target, "Closing finger movement preserves the aimed target")
check(aim.frame(0.40), "Integrated gesture produces click")
let clickPoint = aimedPointer.update(point: CGPoint(x: 0.3, y: 0.3), bounds: bounds, time: aim.now, freeze: aim.detector.shouldFreeze)
check(clickPoint == target, "Click is sent to the pre-pinch target")
aim.ready()
check(!aim.detector.shouldFreeze, "Opening releases pointer lock")

let previewBounds = CGRect(x: 0, y: 0, width: 640, height: 480)
check(HandGeometry.fittedRect(in: previewBounds, aspect: 4 / 3) == previewBounds, "4:3 overlay fills preview")
check(HandGeometry.fittedRect(in: previewBounds, aspect: 16 / 9) == CGRect(x: 0, y: 60, width: 640, height: 360), "16:9 overlay matches letterboxed camera")
func ratio(scale: Double = 1, aspect: Double = 1, narrow: Bool = false, hideLittle: Bool = false) -> Double? {
    HandGeometry.pinchRatio(thumb: CGPoint(x: 0.04 * scale / aspect, y: 0), index: .zero,
        indexBase: .zero, littleBase: hideLittle ? nil : CGPoint(x: (narrow ? 0.02 : 0.1) * scale / aspect, y: 0),
        wrist: .zero, middleBase: CGPoint(x: 0, y: 0.1 * scale / 0.75), aspect: aspect)
}
check(abs(ratio()! - 0.4) < 0.0001, "Palm-normalized pinch measurement")
check(abs(ratio(scale: 2)! - ratio()!) < 0.0001, "Pinch measurement is scale invariant")
check(abs(ratio(aspect: 16 / 9)! - ratio()!) < 0.0001, "Pinch measurement is aspect corrected")
check(abs(ratio(narrow: true)! - ratio()!) < 0.0001, "Palm length stabilizes a rotated hand")
check(abs(ratio(hideLittle: true)! - ratio()!) < 0.0001, "Missing pinky can use wrist and middle base")
check(HandGeometry.pinchRatio(thumb: .zero, index: .zero, indexBase: nil, littleBase: nil,
                             wrist: nil, middleBase: nil, aspect: 1) == nil, "No palm measurement means no click")
check(ratio(scale: 0.1) == nil, "A tiny distant hand cannot trigger an unreliable pinch")

let buffer = LatestFrameBuffer<Int>()
check(buffer.offer(1), "First camera frame schedules delivery")
var duplicateSchedules = 0
for frame in 2...100 { if buffer.offer(frame) { duplicateSchedules += 1 } }
check(duplicateSchedules == 0, "A hundred pending camera results share one delivery")
check(buffer.take() == 100, "Main thread receives the newest frame, not the backlog")
check(buffer.take() == nil, "Delivered results cannot replay")
check(buffer.offer(101), "Next frame schedules a new delivery")
check(buffer.take() == 101, "Next delivery is current")
print("Passed \(checks) gesture, pointer, geometry, and frame-delivery checks.")
