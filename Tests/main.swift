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

// Soft margins: continuous through the old hard 0.15 wall; hard crop is flat outside.
let softAtWall = SoftMargin.normalize(0.15)
let softInside = SoftMargin.normalize(0.16)
let hardAtWall = SoftMargin.hardCrop(0.15)
let hardOutside = SoftMargin.hardCrop(0.14)
check(hardOutside == 0 && hardAtWall == 0, "Hard crop is flat at the old wall")
check(softInside > softAtWall, "Soft map keeps moving through the old 0.15 boundary")
check(SoftMargin.normalize(0.10) == 0 && SoftMargin.normalize(0.90) == 1, "Soft inset endpoints map to screen edges")
check(abs(SoftMargin.normalize(0.5) - 0.5) < 1e-9, "Soft map is centered")

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


// --- DwellDetector: separate physics from pinch's 25ms hold ---
check(ClickMode.pinch.rawValue == "pinch" && ClickMode.dwell.rawValue == "dwell", "ClickMode cases exist")
check(DwellSettings().dwellSeconds >= 0.5 && DwellSettings().dwellSeconds <= 0.8, "Default dwell in CTO 0.5–0.8s band")

func closeEnough(_ actual: Double, _ expected: Double, tolerance: Double = 1e-9) -> Bool {
    abs(actual - expected) <= tolerance
}

// Progress is derived only from tracked observations; reading it never advances dwell.
var dwellProgress = DwellDetector()
dwellProgress.settings.dwellSeconds = 1.0
let progressPoint = CGPoint(x: 40, y: 40)
check(!dwellProgress.update(point: progressPoint, time: 10.0, tracking: true), "Progress arm starts without firing")
check(closeEnough(dwellProgress.progress, 0) && closeEnough(dwellProgress.remainingSeconds, 1.0),
      "Fresh arm reports zero progress and the full duration remaining")
for sample in 1...5 {
    _ = dwellProgress.update(point: progressPoint, time: 10.0 + Double(sample) * 0.1, tracking: true)
}
check(closeEnough(dwellProgress.progress, 0.5) && closeEnough(dwellProgress.remainingSeconds, 0.5),
      "Half dwell reports half progress and half remaining")
for sample in 6...9 {
    _ = dwellProgress.update(point: progressPoint, time: 10.0 + Double(sample) * 0.1, tracking: true)
}
_ = dwellProgress.update(point: progressPoint, time: 10.99, tracking: true)
check(closeEnough(dwellProgress.progress, 0.99) && closeEnough(dwellProgress.remainingSeconds, 0.01),
      "Near-complete dwell stays below one until an observation reaches the threshold")

var resetProgress = dwellProgress
resetProgress.reset()
check(resetProgress.progress == 0 && resetProgress.remainingSeconds == 0,
      "Reset clears dwell progress and remaining time")

var movedProgress = DwellDetector()
movedProgress.settings.dwellSeconds = 1.0
_ = movedProgress.update(point: progressPoint, time: 20.0, tracking: true)
for sample in 1...5 {
    _ = movedProgress.update(point: progressPoint, time: 20.0 + Double(sample) * 0.1, tracking: true)
}
_ = movedProgress.update(point: CGPoint(x: 80, y: 40), time: 20.6, tracking: true)
check(movedProgress.phase == .idle && movedProgress.progress == 0 && movedProgress.remainingSeconds == 0,
      "Movement cancellation clears visible dwell timing")

var lostProgress = DwellDetector()
lostProgress.settings.dwellSeconds = 1.0
_ = lostProgress.update(point: progressPoint, time: 30.0, tracking: true)
_ = lostProgress.update(point: progressPoint, time: 30.1, tracking: true)
_ = lostProgress.update(point: progressPoint, time: 30.2, tracking: false)
check(lostProgress.phase == .idle && lostProgress.progress == 0 && lostProgress.remainingSeconds == 0,
      "Tracking loss clears visible dwell timing")

var sparseProgress = DwellDetector()
sparseProgress.settings.dwellSeconds = 0.5
_ = sparseProgress.update(point: progressPoint, time: 40.0, tracking: true)
check(!sparseProgress.update(point: progressPoint, time: 40.6, tracking: true),
      "A callback gap cannot complete a dwell with unobserved time")
check(sparseProgress.phase == .arming && sparseProgress.progress == 0 &&
      closeEnough(sparseProgress.remainingSeconds, 0.5),
      "A callback gap begins a fresh observed arm")

var firedProgress = DwellDetector()
firedProgress.settings.dwellSeconds = 0.3
firedProgress.settings.cooldownSeconds = 0.45
_ = firedProgress.update(point: progressPoint, time: 50.0, tracking: true)
_ = firedProgress.update(point: progressPoint, time: 50.1, tracking: true)
_ = firedProgress.update(point: progressPoint, time: 50.2, tracking: true)
check(firedProgress.update(point: progressPoint, time: 50.31, tracking: true), "Observed dwell reaches completion")
check(firedProgress.phase == .needMove && firedProgress.progress == 0 && firedProgress.remainingSeconds == 0,
      "Post-fire needMove reports no active progress")
_ = firedProgress.update(point: progressPoint, time: 50.4, tracking: true)
check(firedProgress.phase == .needMove && firedProgress.progress == 0 && firedProgress.remainingSeconds == 0,
      "Cooldown cannot expose queued dwell progress")

// Tracking and malformed observations cancel only incomplete work. Once fired,
// needMove and cooldown are safety state and survive until real movement or reset.
var protectedNeedMove = DwellDetector()
protectedNeedMove.settings.dwellSeconds = 0.20
protectedNeedMove.settings.cooldownSeconds = 0.45
_ = protectedNeedMove.update(point: progressPoint, time: 60.0, tracking: true)
_ = protectedNeedMove.update(point: progressPoint, time: 60.1, tracking: true)
check(protectedNeedMove.update(point: progressPoint, time: 60.21, tracking: true),
      "Safety-state fixture fires once")
protectedNeedMove.trackingLost()
check(protectedNeedMove.phase == .needMove && protectedNeedMove.shouldFreeze,
      "Tracking loss preserves the post-click movement lock")
check(!protectedNeedMove.update(point: progressPoint, time: 60.8, tracking: true),
      "Reacquiring the same stationary hand cannot repeat a click")

check(!protectedNeedMove.update(point: progressPoint, time: 60.8, tracking: true),
      "Duplicate timestamp cannot clear needMove")
check(protectedNeedMove.phase == .needMove, "Duplicate timestamp preserves post-click safety state")
check(!protectedNeedMove.update(point: progressPoint, time: 60.7, tracking: true),
      "Out-of-order timestamp cannot clear needMove")
check(protectedNeedMove.phase == .needMove, "Out-of-order timestamp preserves post-click safety state")
check(!protectedNeedMove.update(point: progressPoint, time: .nan, tracking: true),
      "NaN timestamp cannot clear needMove")
check(protectedNeedMove.phase == .needMove, "NaN timestamp preserves post-click safety state")
check(!protectedNeedMove.update(point: CGPoint(x: CGFloat.nan, y: 40), time: 60.9, tracking: true),
      "Invalid point cannot clear needMove")
check(!protectedNeedMove.update(point: CGPoint(x: 40, y: CGFloat.infinity), time: 60.9, tracking: true),
      "Infinite point cannot clear needMove")
check(protectedNeedMove.phase == .needMove && protectedNeedMove.progress == 0,
      "Malformed points preserve the movement lock without visible progress")

_ = protectedNeedMove.update(point: CGPoint(x: 80, y: 40), time: 60.9, tracking: true)
check(protectedNeedMove.phase == .arming && protectedNeedMove.progress == 0,
      "Real movement after tracking loss starts a fresh arm")
_ = protectedNeedMove.update(point: CGPoint(x: 80, y: 40), time: 61.0, tracking: true)
check(protectedNeedMove.update(point: CGPoint(x: 80, y: 40), time: 61.11, tracking: true),
      "Fresh dwell after required movement can click")

var invalidInitialPosition = DwellDetector()
invalidInitialPosition.settings.dwellSeconds = 0.20
check(!invalidInitialPosition.update(point: CGPoint(x: CGFloat.nan, y: CGFloat.infinity), time: 70.0, tracking: true),
      "Invalid initial position cannot arm or click")
check(invalidInitialPosition.phase == .idle && invalidInitialPosition.progress == 0 &&
      invalidInitialPosition.remainingSeconds == 0 && !invalidInitialPosition.shouldFreeze,
      "Invalid initial position leaves the detector fully idle")
check(!invalidInitialPosition.update(point: progressPoint, time: 70.0, tracking: true),
      "A valid sample at the same timestamp can start the first real observation")
check(invalidInitialPosition.phase == .arming && invalidInitialPosition.progress == 0,
      "The valid position, not the malformed one, becomes the arm origin")

var graceBoundary = DwellDetector()
graceBoundary.settings.dwellSeconds = 0.50
_ = graceBoundary.update(point: progressPoint, time: 80.0, tracking: true)
for sample in 1...4 {
    _ = graceBoundary.update(point: progressPoint,
                             time: 80.0 + Double(sample) * GestureTuning.trackingGraceSeconds,
                             tracking: true)
}
check(graceBoundary.phase == .arming && graceBoundary.progress > 0.95,
      "Nominal samples exactly at tracking grace accumulate consistently")
check(graceBoundary.update(point: progressPoint,
                           time: 80.0 + 5 * GestureTuning.trackingGraceSeconds,
                           tracking: true),
      "Floating-point rounding at the grace boundary cannot restart a valid dwell")

struct DwellSim {
    var detector = DwellDetector()
    var now = 0.0
    var clicks = 0
    init() {
        detector.settings.dwellSeconds = 0.55
        detector.settings.cooldownSeconds = 0.40
        detector.settings.moveCancelPoints = 18
    }
    @discardableResult mutating func step(_ point: CGPoint, after interval: Double = 1.0 / 30, tracking: Bool = true) -> Bool {
        now += interval
        let click = detector.update(point: point, time: now, tracking: tracking)
        if click { clicks += 1 }
        return click
    }
    mutating func hold(_ point: CGPoint, seconds: Double, fps: Double = 30) {
        let frames = Int((seconds * fps).rounded(.up))
        for _ in 0..<frames { step(point, after: 1 / fps) }
    }
}

let dwellAim = CGPoint(x: 100, y: 100)
var d = DwellSim()
d.hold(dwellAim, seconds: 0.40)
check(d.clicks == 0 && d.detector.phase == .arming, "Sub-threshold dwell does not fire")
check(d.detector.shouldFreeze, "Arming freezes the aim point")
d.hold(dwellAim, seconds: 0.30)
check(d.clicks == 1 && d.detector.phase == .needMove, "Dwell fires once after threshold")
d.hold(dwellAim, seconds: 1.0)
check(d.clicks == 1, "No auto-repeat while still after fire")

d = DwellSim()
d.hold(dwellAim, seconds: 0.70)
check(d.clicks == 1, "Fresh dwell session clicks")
d.step(CGPoint(x: 200, y: 100), after: 0.45)  // move + clear cooldown
d.hold(CGPoint(x: 200, y: 100), seconds: 0.70)
check(d.clicks == 2, "Second dwell after move + settle")

var cancel = DwellSim()
cancel.hold(dwellAim, seconds: 0.30)
check(cancel.detector.phase == .arming, "Arming before cancel")
check(cancel.detector.shouldFreeze, "Arming freezes before cancel")
cancel.step(CGPoint(x: 130, y: 100), after: 1.0 / 30)
check(cancel.clicks == 0 && cancel.detector.phase == .idle, "Cancel-on-move releases freeze (idle), no click")
check(!cancel.detector.shouldFreeze, "Freeze released on cancel so aim can track")
cancel.hold(CGPoint(x: 130, y: 100), seconds: 0.30)
check(cancel.detector.phase == .arming && cancel.clicks == 0, "Partial re-arm after cancel does not inherit old time")
cancel.hold(CGPoint(x: 130, y: 100), seconds: 0.40)
check(cancel.clicks == 1, "Full dwell after cancel-on-move fires once")

var dwellLost = DwellSim()
dwellLost.hold(dwellAim, seconds: 0.30)
dwellLost.step(dwellAim, after: 1.0 / 30, tracking: false)
check(dwellLost.detector.phase == .idle, "Tracking loss disarms dwell")
dwellLost.detector.reset()
check(dwellLost.detector.phase == .idle && !dwellLost.detector.shouldFreeze, "Esc/pause reset clears armed dwell")

var cool = DwellSim()
cool.detector.settings.dwellSeconds = 0.50
cool.detector.settings.cooldownSeconds = 0.45
cool.hold(dwellAim, seconds: 0.60)
check(cool.clicks == 1, "Configured 0.5s dwell fires")
cool.step(CGPoint(x: 200, y: 100), after: 0.10)
cool.hold(CGPoint(x: 200, y: 100), seconds: 0.60)
check(cool.clicks == 1, "Cooldown blocks a queued late click")
cool.step(CGPoint(x: 260, y: 100), after: 0.50)
cool.hold(CGPoint(x: 260, y: 100), seconds: 0.60)
check(cool.clicks == 2, "After cooldown + move, dwell can fire again")

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



// --- Order-of-ops integration (PR review bugs) ---
// Bug A: pointer update before pinch detect → freeze engages one frame late → click drift.
// Bug B: dwell samples frozen aim → cancel-on-move never sees motion.
let pipelineBounds = CGRect(x: 0, y: 0, width: 1000, height: 1000)

struct BuggyPinchLoop {
    var detector = PinchDetector()
    var filter = PointerFilter()
    var now = 0.0
    var lastAim = CGPoint.zero
    mutating func ready() {
        for _ in 0..<5 {
            now += 1.0 / 30
            _ = detector.update(ratio: 0.9, time: now)
        }
    }
    /// Historical (broken) order: freeze from *previous* phase, then detect.
    mutating func step(index: CGPoint, ratio: Double) -> (aim: CGPoint, fired: Bool) {
        now += 1.0 / 30
        let freeze = detector.shouldFreeze
        let aim = filter.update(point: index, bounds: pipelineBounds, time: now, freeze: freeze)
        let fired = detector.update(ratio: ratio, time: now)
        lastAim = aim
        return (aim, fired)
    }
}

struct FixedPinchLoop {
    var detector = PinchDetector()
    var filter = PointerFilter()
    var now = 0.0
    mutating func ready() {
        for _ in 0..<5 {
            now += 1.0 / 30
            _ = detector.update(ratio: 0.9, time: now)
        }
    }
    /// Correct order: detect first, then filter with post-gesture freeze.
    mutating func step(index: CGPoint, ratio: Double) -> (aim: CGPoint, fired: Bool) {
        now += 1.0 / 30
        let fired = detector.update(ratio: ratio, time: now)
        let aim = filter.update(point: index, bounds: pipelineBounds, time: now, freeze: detector.shouldFreeze)
        return (aim, fired)
    }
}

var buggyPinch = BuggyPinchLoop(); buggyPinch.ready()
let pinchAim = CGPoint(x: 0.50, y: 0.50)
_ = buggyPinch.step(index: pinchAim, ratio: 0.9)
let preClose = buggyPinch.lastAim
// Closing fingers + hand drifts toward camera edge while pinch confirms.
var buggyClick = CGPoint.zero
var buggyFired = false
for (i, ratio) in [0.40, 0.40, 0.40].enumerated() {
    let drifted = CGPoint(x: 0.50 - Double(i + 1) * 0.08, y: 0.50)
    let r = buggyPinch.step(index: drifted, ratio: ratio)
    if r.fired { buggyFired = true; buggyClick = r.aim }
}
check(buggyFired, "Buggy loop still fires a pinch (repro harness)")
let buggyDrift = hypot(buggyClick.x - preClose.x, buggyClick.y - preClose.y)
check(buggyDrift > 40, "Repro: buggy order lets pinch aim drift (was ~126px class)")

var fixedPinch = FixedPinchLoop(); fixedPinch.ready()
_ = fixedPinch.step(index: pinchAim, ratio: 0.9)
var fixedPre = CGPoint.zero
var fixedClick = CGPoint.zero
var fixedFired = false
for (i, ratio) in [0.40, 0.40, 0.40].enumerated() {
    let drifted = CGPoint(x: 0.50 - Double(i + 1) * 0.08, y: 0.50)
    // Capture aim entering confirm: after first close, freeze must hold.
    let r = fixedPinch.step(index: drifted, ratio: ratio)
    if i == 0 { fixedPre = r.aim }
    if r.fired { fixedFired = true; fixedClick = r.aim }
}
check(fixedFired, "Fixed loop fires pinch")
let fixedDrift = hypot(fixedClick.x - fixedPre.x, fixedClick.y - fixedPre.y)
check(fixedDrift < 1.0, "Fixed order: click aim equals pre-pinch freeze (no drift)")
check(fixedDrift < buggyDrift * 0.05, "Fixed drift << buggy drift")

struct BuggyDwellLoop {
    var dwell = DwellDetector()
    var filter = PointerFilter()
    var now = 0.0
    mutating func step(index: CGPoint) -> (aim: CGPoint, fired: Bool, phase: DwellPhase) {
        now += 1.0 / 30
        let freeze = dwell.shouldFreeze
        let aim = filter.update(point: index, bounds: pipelineBounds, time: now, freeze: freeze)
        // Bug: feed frozen aim into dwell — motion is invisible while arming.
        let fired = dwell.update(point: aim, time: now, tracking: true)
        return (aim, fired, dwell.phase)
    }
}

struct FixedDwellLoop {
    var dwell = DwellDetector()
    var filter = PointerFilter()
    var now = 0.0
    mutating func step(index: CGPoint) -> (aim: CGPoint, fired: Bool, phase: DwellPhase) {
        now += 1.0 / 30
        let sample = filter.unfrozenTarget(point: index, bounds: pipelineBounds)
        let fired = dwell.update(point: sample, time: now, tracking: true)
        let aim = filter.update(point: index, bounds: pipelineBounds, time: now, freeze: dwell.shouldFreeze)
        return (aim, fired, dwell.phase)
    }
}

let dwellStart = CGPoint(x: 0.50, y: 0.50)
let movedFinger = CGPoint(x: 0.62, y: 0.50) // >> 18pt on 1000pt screen after soft map

// Arm 0.40s, move far, hold 0.30s more. Wall-clock 0.70s ≥ dwell, but cancel must reset.
var buggyDwell = BuggyDwellLoop()
buggyDwell.dwell.settings.dwellSeconds = 0.65
buggyDwell.dwell.settings.moveCancelPoints = 18
for _ in 0..<12 { _ = buggyDwell.step(index: dwellStart) }
check(buggyDwell.dwell.shouldFreeze, "Dwell arming freezes aim")
for _ in 0..<3 { _ = buggyDwell.step(index: movedFinger) }
var earlyFire = false
for _ in 0..<9 {
    if buggyDwell.step(index: movedFinger).fired { earlyFire = true }
}
check(earlyFire, "Repro: buggy dwell ignores move and fires on pre-move arm time")

var fixedDwell = FixedDwellLoop()
fixedDwell.dwell.settings.dwellSeconds = 0.65
fixedDwell.dwell.settings.moveCancelPoints = 18
for _ in 0..<12 { _ = fixedDwell.step(index: dwellStart) }
for _ in 0..<3 { _ = fixedDwell.step(index: movedFinger) }
var fixedEarly = false
for _ in 0..<9 {
    if fixedDwell.step(index: movedFinger).fired { fixedEarly = true }
}
check(!fixedEarly, "Fixed dwell: move cancels arm; 0.30s post-move hold does not fire")
var fixedLate = false
for _ in 0..<25 {
    if fixedDwell.step(index: movedFinger).fired { fixedLate = true }
}
check(fixedLate, "Fixed dwell: full re-arm after cancel still fires once")


// --- Dwell freeze-release: click must land at B after A→B re-aim ---
// Bug: cancel reset the timer but stayed `.arming` → freeze held aim at A.
struct DwellAimLoop {
    var dwell = DwellDetector()
    var filter = PointerFilter()
    var now = 0.0
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 1000)
    init() {
        dwell.settings.dwellSeconds = 0.55
        dwell.settings.moveCancelPoints = 18
        dwell.settings.cooldownSeconds = 0.40
    }
    mutating func step(index: CGPoint) -> (aim: CGPoint, fired: Bool, freeze: Bool) {
        now += 1.0 / 30
        let sample = filter.unfrozenTarget(point: index, bounds: bounds)
        let fired = dwell.update(point: sample, time: now, tracking: true)
        let freeze = dwell.shouldFreeze
        let aim = filter.update(point: index, bounds: bounds, time: now, freeze: freeze)
        return (aim, fired, freeze)
    }
}

let indexA = CGPoint(x: 0.35, y: 0.50)
let indexB = CGPoint(x: 0.65, y: 0.50)
var abLoop = DwellAimLoop()
var aimAtA = CGPoint.zero
for _ in 0..<10 { // ~0.33s arm at A (> armFreezeDelay)
    let r = abLoop.step(index: indexA)
    aimAtA = r.aim
}
check(abLoop.dwell.shouldFreeze, "Arming at A freezes after settle delay")
// Move to B — cancel must unfreeze so filter tracks.
var sawUnfreeze = false
var aimAfterMove = CGPoint.zero
for _ in 0..<5 {
    let r = abLoop.step(index: indexB)
    if !r.freeze { sawUnfreeze = true }
    aimAfterMove = r.aim
}
check(sawUnfreeze, "Cancel-on-move releases freeze so aim can leave A")
check(hypot(aimAfterMove.x - aimAtA.x, aimAfterMove.y - aimAtA.y) > 40, "Aim tracks toward B after cancel")
// Settle at B and fire — click aim must be near B, not A.
var clickAim = CGPoint.zero
var fired = false
for _ in 0..<25 {
    let r = abLoop.step(index: indexB)
    if r.fired {
        fired = true
        clickAim = r.aim
        break
    }
}
check(fired, "Dwell fires after re-aim settle at B")
let targetB = abLoop.filter.unfrozenTarget(point: indexB, bounds: abLoop.bounds)
let distB = hypot(clickAim.x - targetB.x, clickAim.y - targetB.y)
let distA = hypot(clickAim.x - aimAtA.x, clickAim.y - aimAtA.y)
check(distB < 25, "Click aim is at B after A→B re-aim")
check(distA > 80, "Click aim is not stuck at old A")

// A slow 60 fps approach repeatedly crosses the cancel radius. It must not fire
// while moving, and the brief freeze delay must leave the eventual click at B.
var smoothDwell = DwellDetector()
smoothDwell.settings.dwellSeconds = 0.65
smoothDwell.settings.moveCancelPoints = 18
var smoothFilter = PointerFilter()
var smoothTime = 0.0
var smoothLocation = CGPoint.zero
var smoothClick = CGPoint.zero
var firedDuringApproach = false
let smoothFinalIndex = CGPoint(x: 0.70, y: 0.50)
for frame in 0..<120 {
    smoothTime += 1.0 / 60
    let fraction = Double(frame) / 119
    let index = CGPoint(x: 0.30 + 0.40 * fraction, y: 0.50)
    let sample = smoothFilter.unfrozenTarget(point: index, bounds: pipelineBounds)
    let fired = smoothDwell.update(point: sample, time: smoothTime, tracking: true)
    smoothLocation = smoothFilter.update(point: index, bounds: pipelineBounds, time: smoothTime,
                                         freeze: smoothDwell.shouldFreeze)
    if fired { firedDuringApproach = true }
}
check(!firedDuringApproach, "A smooth 60 fps approach cannot fire before settling")
var smoothFired = false
for _ in 0..<60 where !smoothFired {
    smoothTime += 1.0 / 60
    let sample = smoothFilter.unfrozenTarget(point: smoothFinalIndex, bounds: pipelineBounds)
    smoothFired = smoothDwell.update(point: sample, time: smoothTime, tracking: true)
    smoothLocation = smoothFilter.update(point: smoothFinalIndex, bounds: pipelineBounds, time: smoothTime,
                                         freeze: smoothDwell.shouldFreeze)
    if smoothFired { smoothClick = smoothLocation }
}
let smoothTarget = smoothFilter.unfrozenTarget(point: smoothFinalIndex, bounds: pipelineBounds)
check(smoothFired, "A 60 fps smooth approach can click after a full settled dwell")
check(hypot(smoothClick.x - smoothTarget.x, smoothClick.y - smoothTarget.y) < 8,
      "A 60 fps smooth approach clicks at the final target")

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

print("Passed \(checks) gesture, pointer, geometry, frame-delivery, safety, dwell, order-of-ops, and freeze-release checks.")
