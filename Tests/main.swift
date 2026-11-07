import Foundation
import CoreGraphics

var checks = 0
func check(_ condition: Bool, _ message: String) {
    checks += 1
    if !condition { fatalError(message) }
}

var pointer = PointerFilter()
let bounds = CGRect(x: -1920, y: 100, width: 1920, height: 1080)
check(pointer.update(point: .zero, bounds: bounds, time: 0, freeze: false) == CGPoint(x: -1920, y: 100), "Clamp top left of offset display")
let moved = pointer.update(point: CGPoint(x: 1, y: 1), bounds: bounds, time: 0.03, freeze: false)
check(moved.x > -1920 && moved.x < -1, "Smooth pointer movement")
check(pointer.update(point: .zero, bounds: bounds, time: 0.06, freeze: true) == moved, "A frozen gesture holds the exact target")
pointer.reset()
check(pointer.update(point: CGPoint(x: 1, y: 1), bounds: bounds, time: 1, freeze: false) == CGPoint(x: -1, y: 1179), "Clamp bottom right inside display")

// The smaller fingertip region covers the display before the hand leaves view.
let inset = GestureTuning.softInset
check(inset >= 0.2, "Fingertip travel leaves room for the palm at camera edges")
check(SoftMargin.normalize(inset) == 0 && SoftMargin.normalize(1 - inset) == 1, "Guide endpoints map to screen edges")
check(SoftMargin.normalize(inset + 0.01) > SoftMargin.normalize(inset), "Motion inside the guide remains responsive")
check(abs(SoftMargin.normalize(0.5) - 0.5) < 1e-9, "Default mapping is centered")

for fps in [30.0, 60.0] {
    var response = PointerFilter()
    let screen = CGRect(x: 0, y: 0, width: 1001, height: 1001)
    let inset = GestureTuning.softInset
    _ = response.update(point: CGPoint(x: inset, y: inset), bounds: screen, time: 0, freeze: false)
    var result = CGPoint.zero
    for frame in 1...Int(fps / 10) {
        result = response.update(point: CGPoint(x: 1 - inset, y: 1 - inset), bounds: screen, time: Double(frame) / fps, freeze: false)
        check(result.x >= 0 && result.x <= 1000, "No overshoot at \(fps) fps")
    }
    check(result.x > 975, "Settle within 2.5% after 100 ms at \(fps) fps")
}

// Synthetic proof: low velocity damps jitter more than high velocity tracks a step.
let screen = CGRect(x: 0, y: 0, width: 1000, height: 1000)
func jitterRMS(amplitude: Double, fps: Double) -> Double {
    var filter = PointerFilter()
    var sum = 0.0
    var n = 0
    let base = 0.5
    _ = filter.update(point: CGPoint(x: base, y: base), bounds: screen, time: 0, freeze: false)
    for i in 1...60 {
        let t = Double(i) / fps
        let noise = (i % 2 == 0 ? amplitude : -amplitude)
        let p = filter.update(point: CGPoint(x: base + noise, y: base), bounds: screen, time: t, freeze: false)
        let centerX = screen.midX
        sum += (p.x - centerX) * (p.x - centerX)
        n += 1
    }
    return (sum / Double(n)).squareRoot()
}
let quiet = jitterRMS(amplitude: 0.002, fps: 60)
check(quiet < 3.0, "Low-speed smoothing suppresses sub-pixel camera jitter")

func fractionalLag(distance: Double, fps: Double, frames: Int) -> Double {
    var filter = PointerFilter()
    let start = 0.5
    let origin = filter.update(point: CGPoint(x: start, y: start), bounds: screen, time: 0, freeze: false)
    var last = origin
    for i in 1...frames {
        last = filter.update(point: CGPoint(x: start + distance, y: start), bounds: screen, time: Double(i) / fps, freeze: false)
    }
    let targetX = screen.minX + SoftMargin.normalize(start + distance) * (screen.width - 1)
    let span = abs(targetX - origin.x)
    return span < 1e-6 ? 0 : abs(targetX - last.x) / span
}
let slowFrac = fractionalLag(distance: 0.012, fps: 60, frames: 3)
let fastFrac = fractionalLag(distance: 0.35, fps: 60, frames: 3)
check(fastFrac < slowFrac * 0.9, "High-velocity path closes a larger fraction of the step (less lag)")

let previewBounds = CGRect(x: 0, y: 0, width: 640, height: 480)
check(HandGeometry.fittedRect(in: previewBounds, aspect: 4 / 3) == previewBounds, "4:3 overlay fills preview")
check(HandGeometry.fittedRect(in: previewBounds, aspect: 16 / 9) == CGRect(x: 0, y: 60, width: 640, height: 360), "16:9 overlay matches letterboxed camera")

let buffer = LatestFrameBuffer<Int>()
check(buffer.offer(1), "First camera frame schedules delivery")
var duplicateSchedules = 0
for frame in 2...100 { if buffer.offer(frame) { duplicateSchedules += 1 } }
check(duplicateSchedules == 0, "A hundred pending camera results share one delivery")
check(buffer.take() == 100, "Main thread receives the newest frame, not the backlog")
check(buffer.take() == nil, "Delivered results cannot replay")
check(buffer.offer(101), "Next frame schedules a new delivery")
check(buffer.take() == 101, "Next delivery is current")

// SafetyPolicy: all four latches required; any single false blocks click injection.
check(SafetyPolicy.shouldInjectClick(gestureFired: true, allowClicks: true, axTrusted: true, pointerControlEnabled: true),
      "Inject only when every latch is closed")
check(!SafetyPolicy.shouldInjectClick(gestureFired: false, allowClicks: true, axTrusted: true, pointerControlEnabled: true),
      "No gesture means no inject")
check(!SafetyPolicy.shouldInjectClick(gestureFired: true, allowClicks: false, axTrusted: true, pointerControlEnabled: true),
      "allowClicks off blocks inject")
check(!SafetyPolicy.shouldInjectClick(gestureFired: true, allowClicks: true, axTrusted: false, pointerControlEnabled: true),
      "AX untrusted blocks inject")
check(!SafetyPolicy.shouldInjectClick(gestureFired: true, allowClicks: true, axTrusted: true, pointerControlEnabled: false),
      "Pointer control off blocks inject")

// --- CursorFeedbackLayout: clamp captions without displacing the target ring ---
check(CursorFeedbackLayout.appKitPoint(CGPoint(x: 200, y: 0), primaryTop: 900) == CGPoint(x: 200, y: 900),
      "Primary top edge converts from Quartz into AppKit")
check(CursorFeedbackLayout.appKitPoint(CGPoint(x: -100, y: -800), primaryTop: 900) == CGPoint(x: -100, y: 1700),
      "An upper display's exact top edge keeps its position")
check(CursorFeedbackLayout.appKitPoint(CGPoint(x: 400, y: 1500), primaryTop: 900) == CGPoint(x: 400, y: -600),
      "A display below the primary converts without a per-display flip")

func globalRingCenter(_ layout: CursorFeedbackLayout) -> CGPoint {
    CGPoint(x: layout.origin.x + layout.ringOrigin.x + 25,
            y: layout.origin.y + layout.ringOrigin.y + 25)
}

func globalLabelFrame(_ layout: CursorFeedbackLayout) -> CGRect {
    CGRect(x: layout.origin.x + layout.labelOrigin.x,
           y: layout.origin.y + layout.labelOrigin.y,
           width: 150, height: 22)
}

let feedbackScreens = [
    CGRect(x: 0, y: 0, width: 1440, height: 900),
    CGRect(x: -1920, y: -180, width: 1920, height: 1080),
    CGRect(x: 120, y: 900, width: 1280, height: 800),
    CGRect(x: -300, y: -1200, width: 1600, height: 1000)
]
for screen in feedbackScreens {
    let edgeTargets = [
        CGPoint(x: screen.minX, y: screen.minY),
        CGPoint(x: screen.maxX, y: screen.minY),
        CGPoint(x: screen.minX, y: screen.maxY),
        CGPoint(x: screen.maxX, y: screen.maxY)
    ]
    for target in edgeTargets {
        let layout = CursorFeedbackLayout(center: target, screen: screen)
        let label = globalLabelFrame(layout)
        check(label.minX >= screen.minX && label.maxX <= screen.maxX &&
              label.minY >= screen.minY && label.maxY <= screen.maxY,
              "Cursor feedback label stays within every display edge")
        check(globalRingCenter(layout) == target,
              "Clamping feedback at a display edge keeps the ring on the actual target")
    }
}

let offsetTargets: [(CGRect, CGPoint)] = [
    (CGRect(x: -2560, y: 0, width: 2560, height: 1440), CGPoint(x: -1732, y: 721)),
    (CGRect(x: 0, y: 900, width: 1512, height: 982), CGPoint(x: 756, y: 1400)),
    (CGRect(x: 0, y: -1080, width: 1920, height: 1080), CGPoint(x: 1111, y: -640))
]
for (screen, target) in offsetTargets {
    let layout = CursorFeedbackLayout(center: target, screen: screen)
    check(globalRingCenter(layout) == target,
          "Ring center matches the target on negative, above, and below displays")
}

print("Passed \(checks) pointer, geometry, frame-delivery, safety, and feedback-layout checks.")
