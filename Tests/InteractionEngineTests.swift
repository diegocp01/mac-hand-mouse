import Foundation
import CoreGraphics

@main struct InteractionEngineTests {
    static var checks = 0
    static let neutral = ForwardPose(scale: 0.14, reach: 1.4, center: CGPoint(x: 0.5, y: 0.5), side: "left")
    static let pressed = ForwardPose(scale: 0.16, reach: 0.8, center: CGPoint(x: 0.5, y: 0.5), side: "left")
    static func check(_ value: Bool, _ message: String) {
        checks += 1
        if !value { fatalError(message) }
    }
    struct Session {
        var engine = InteractionEngine()
        var time = 0.0
        var clicks = 0
        var bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
        var running = true
        var trusted = true
        var destination: InteractionDestination = .system
        var last = InteractionStep()
        mutating func setup(allowClicks: Bool = true, duration: Double = 0.65) {
            engine.configure(InteractionSettings(mode: .forward, allowClicks: allowClicks, dwellSeconds: duration))
        }
        @discardableResult mutating func frame(_ point: CGPoint? = CGPoint(x: 0.5, y: 0.5),
                pose: ForwardPose? = neutral, ratio: Double? = 0.9, dt: Double = 1.0 / 30) -> InteractionStep {
            time += dt
            last = engine.process(index: point, pinchRatio: ratio, forwardPose: pose, timestamp: time, now: time + 0.01,
                                  bounds: bounds, running: running, trusted: trusted, destination: destination)
            if last.click { clicks += 1 }
            return last
        }
        mutating func hold(_ point: CGPoint = CGPoint(x: 0.5, y: 0.5), pose: ForwardPose? = neutral,
                           seconds: Double, fps: Double = 30) {
            for _ in 0..<Int(ceil(seconds * fps)) { frame(point, pose: pose, dt: 1 / fps) }
        }
    }
    static func main() {
        let a = CGPoint(x: 0.3, y: 0.5), b = CGPoint(x: 0.7, y: 0.5)
        check(ClickMode.restored("dwell") == .forward, "Legacy dwell migrates to explicit intent")
        for fps in [15.0, 30.0, 60.0] {
            var s = Session(); s.setup()
            s.hold(a, seconds: 3, fps: fps)
            check(s.clicks == 0 && s.engine.forward.progress == 0 && !s.engine.forward.shouldFreeze,
                  "Standing still alone never shows a countdown or freezes the pointer")
            let before = s.last.location!
            s.hold(b, seconds: 1, fps: fps)
            check(s.clicks == 0 && s.last.location!.x > before.x + 800, "Normal aiming remains responsive")
            for i in 0..<Int(fps * 3) {
                s.frame(CGPoint(x: 0.5 + Double(i) / fps * 20 / s.bounds.width, y: 0.5), dt: 1 / fps)
            }
            check(s.clicks == 0 && s.engine.forward.progress == 0, "Slow 20-point/sec aiming never starts a timer")
            s = Session(); s.setup(); s.hold(a, seconds: 0.7, fps: fps)
            let aimed = s.last.location!
            s.hold(b, pose: pressed, seconds: 0.35, fps: fps)
            check(s.engine.forward.progress > 0 && s.clicks == 0, "Only a confirmed forward pose starts progress")
            check(s.last.location == aimed, "Forward projection cannot move the chosen target")
            s.hold(b, pose: pressed, seconds: 0.6, fps: fps)
            check(s.clicks == 1 && s.last.location == aimed, "Forward hold clicks the intended target once")
            s.hold(b, pose: pressed, seconds: 1, fps: fps)
            var outlier = pressed; outlier.center.x += 19 / s.bounds.width
            s.frame(b, pose: outlier, dt: 1 / fps)
            s.hold(b, pose: pressed, seconds: 1, fps: fps)
            check(s.clicks == 1, "A positional outlier never rearms a completed click")
            s.hold(a, seconds: 0.7, fps: fps); s.hold(a, pose: pressed, seconds: 1, fps: fps)
            check(s.clicks == 2, "Withdrawal and a new press can click the same place")
            s = Session(); s.setup(); s.hold(a, seconds: 0.7, fps: fps)
            s.frame(a, pose: pressed, dt: 1 / fps); s.hold(a, seconds: 1, fps: fps)
            check(s.clicks == 0 && s.engine.forward.progress == 0, "One pose outlier cannot start a timer")
            s.hold(a, pose: pressed, seconds: 0.4, fps: fps)
            s.frame(a, pose: nil, dt: 1 / fps); s.hold(a, pose: pressed, seconds: 2, fps: fps)
            check(s.clicks == 0 && s.engine.forward.progress == 0, "Tracking loss requires a new neutral-to-forward transition")
            s = Session(); s.setup(); s.hold(a, seconds: 0.7, fps: fps)
            s.hold(a, pose: pressed, seconds: 0.35, fps: fps)
            for i in 0..<Int(fps) {
                var moving = pressed; moving.center.x += Double(i) / fps * 20 / s.bounds.width
                s.frame(a, pose: moving, dt: 1 / fps)
            }
            check(s.clicks == 0 && s.engine.forward.progress == 0 && !s.engine.forward.shouldFreeze,
                  "Sustained sideways drift cancels independently of the frozen pointer")
            s = Session(); s.setup(allowClicks: false)
            s.hold(a, seconds: 0.7, fps: fps); s.hold(b, pose: pressed, seconds: 2, fps: fps)
            check(s.clicks == 0 && s.engine.forward.progress == 0 && !s.engine.forward.shouldFreeze,
                  "Clicks-off pointing ignores all click gestures")
            s = Session(); s.setup()
            s.hold(b, pose: pressed, seconds: 2, fps: fps)
            check(s.clicks == 0 && s.engine.forward.progress == 0, "Starting with a forward hold cannot click without a fresh transition")
        }
        var pinch = Session(); pinch.engine.configure(InteractionSettings(allowClicks: true))
        pinch.hold(a, seconds: 0.2)
        let aimed = pinch.last.location!
        pinch.frame(b, ratio: 0.40)
        let fired = pinch.frame(b, ratio: 0.40)
        check(fired.click && fired.location == aimed, "Pinch freezes before its closing gesture moves the pointer")
        for reason in ["permission", "pause", "pointer", "display", "overflow", "stale", "future", "duplicate", "nan", "hand"] {
            var s = Session(); s.setup(); s.hold(a, seconds: 0.7); s.hold(a, pose: pressed, seconds: 0.4)
            let step: InteractionStep
            switch reason {
            case "permission": s.trusted = false; step = s.frame(a, pose: pressed)
            case "pause": s.running = false; step = s.frame(a, pose: pressed)
            case "pointer": s.engine.configure(InteractionSettings(mode: .forward, allowClicks: true, pointerEnabled: false)); step = s.frame(a, pose: pressed)
            case "display": s.bounds = .zero; step = s.frame(a, pose: pressed)
            case "overflow":
                s.bounds = CGRect(x: CGFloat.greatestFiniteMagnitude, y: CGFloat.greatestFiniteMagnitude,
                                  width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
                step = s.frame(a, pose: pressed)
            case "nan": step = s.frame(CGPoint(x: CGFloat.nan, y: 0.5), pose: pressed)
            case "hand": step = s.frame(nil, pose: nil)
            default:
                let stamp = reason == "future" ? s.time + 1 : s.time
                let now = reason == "stale" ? s.time + 0.3 : s.time + 0.01
                step = s.engine.process(index: a, pinchRatio: 0.9, forwardPose: pressed, timestamp: stamp, now: now,
                                        bounds: s.bounds, running: true, trusted: true)
            }
            check(step.location == nil && !step.click, "\(reason) blocks all output")
            check(s.engine.forward.progress == 0, "\(reason) cancels active progress")
        }
        var restored = Session(); restored.setup(); restored.hold(a, seconds: 0.7)
        restored.hold(a, pose: pressed, seconds: 0.4)
        restored.trusted = false; restored.frame(a, pose: pressed)
        restored.trusted = true; restored.hold(a, pose: pressed, seconds: 2)
        check(restored.clicks == 0, "Permission restoration cannot resume a held gesture")
        restored.hold(a, seconds: 0.7); restored.hold(a, pose: pressed, seconds: 1)
        check(restored.clicks == 1, "Permission restoration accepts a fresh deliberate gesture")
        var duration = Session(); duration.setup(); duration.hold(a, seconds: 0.7)
        duration.hold(a, pose: pressed, seconds: 0.4)
        duration.engine.configure(InteractionSettings(mode: .forward, allowClicks: true, dwellSeconds: 1.5))
        duration.hold(a, pose: pressed, seconds: 2)
        check(duration.clicks == 0, "Changing duration requires withdrawal")
        duration.hold(a, seconds: 0.7); duration.hold(a, pose: pressed, seconds: 1)
        check(duration.clicks == 0 && duration.engine.forward.remainingSeconds > 0.4, "Selected duration drives the timer")
        duration.hold(a, pose: pressed, seconds: 0.8)
        check(duration.clicks == 1, "A full longer hold fires once")
        var wrongHand = Session(); wrongHand.setup(); wrongHand.hold(a, seconds: 0.7)
        var other = pressed; other.side = "right"
        wrongHand.hold(a, pose: other, seconds: 2)
        check(wrongHand.clicks == 0, "A different hand cannot inherit the click gesture")
        var reference = AutomaticForwardReference()
        for i in 0..<30 {
            var moving = neutral; moving.center.x = 0.2 + Double(i) * 0.015
            _ = reference.update(moving, time: Double(i) / 30, canAdapt: true)
        }
        check(reference.profile != nil, "Ordinary moving-pointing learns automatically without a capture step")
        let learned = reference.profile
        _ = reference.update(pressed, time: 1, canAdapt: false)
        check(reference.profile == learned, "A press cannot alter the reference during confirmation or holding")
        _ = reference.update(nil, time: 1.03, canAdapt: true)
        check(reference.profile == nil, "Lost landmarks discard the automatic reference")
        for i in 0..<5 { _ = reference.update(neutral, time: 2 + Double(i) / 30, canAdapt: true) }
        _ = reference.update(neutral, time: 3, canAdapt: true)
        check(reference.profile == nil, "A tracking gap cannot count as observed pointing")
        var invalid = neutral; invalid.scale = .nan
        _ = reference.update(invalid, time: 3.03, canAdapt: true)
        check(reference.profile == nil, "Invalid geometry cannot seed automatic thresholds")

        for fps in [15.0, 30.0, 60.0] {
            for scale in [0.08, 0.14, 0.28] {
                for reach in [1.1, 1.4, 1.8] {
                    for side in ["left", "right"] {
                        var s = Session(); s.setup()
                        let aim = ForwardPose(scale: scale, reach: reach, center: CGPoint(x: 0.5, y: 0.5), side: side)
                        let press = ForwardPose(scale: scale * 1.12, reach: reach * 0.55, center: aim.center, side: side)
                        s.hold(a, pose: aim, seconds: 0.8, fps: fps)
                        check(s.engine.forwardProfile != nil && s.engine.forward.progress == 0,
                              "Both hands and multiple camera scales start without manual setup")
                        s.hold(a, pose: press, seconds: 1.2, fps: fps)
                        check(s.clicks == 1, "Relative forward detection works across synthetic hand sizes and frame rates")
                    }
                }
            }
        }
        var changingDistance = Session(); changingDistance.setup(); changingDistance.hold(a, seconds: 0.8)
        var enlarged = neutral; enlarged.scale *= 1.3
        changingDistance.hold(a, pose: enlarged, seconds: 2)
        check(changingDistance.clicks == 0 && changingDistance.engine.forward.progress == 0,
              "Moving closer with an extended index does not count as pointing toward the screen")
        check(abs(changingDistance.engine.forwardProfile!.neutral.scale - enlarged.scale) < 0.001,
              "An ordinary extended index readapts to seating distance automatically")
        var jitter = Session(); jitter.setup(); jitter.hold(a, seconds: 0.8)
        var showedTimer = false
        for i in 0..<120 {
            var noisy = neutral
            noisy.scale *= 1 + sin(Double(i)) * 0.025
            noisy.reach += cos(Double(i)) * 0.04
            jitter.frame(CGPoint(x: 0.3 + Double(i) / 400, y: 0.5), pose: noisy)
            showedTimer = showedTimer || jitter.engine.forward.progress > 0
        }
        check(!showedTimer && jitter.clicks == 0, "Noisy ordinary pointing cannot silently become a countdown")

        for bounds in [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: -2560, y: -100, width: 2560, height: 1440)] {
            var simulated = Session(); simulated.setup(); simulated.bounds = bounds
            simulated.destination = .practice; simulated.trusted = false
            simulated.hold(a, seconds: 0.7); simulated.hold(a, pose: pressed, seconds: 0.4)
            check(simulated.engine.forward.progress > 0 && simulated.last.location != nil,
                  "Practice simulates the same desktop geometry without Accessibility")
            var systemOutputs = 0
            for _ in 0..<30 {
                let step = simulated.frame(a, pose: pressed)
                if step.systemLocation != nil || step.systemClick { systemOutputs += 1 }
            }
            check(simulated.clicks == 1 && systemOutputs == 0, "A successful practice click cannot dispatch OS input")
            simulated.destination = .system; simulated.trusted = true
            simulated.hold(a, pose: pressed, seconds: 2)
            check(simulated.clicks == 1 && simulated.engine.forward.progress == 0,
                  "Switching out of simulation cannot carry click intent into the desktop")
        }
        var canceled = Session(); canceled.setup(); canceled.hold(a, seconds: 0.7)
        canceled.hold(a, pose: pressed, seconds: 0.4); canceled.hold(a, seconds: 0.7)
        check(canceled.clicks == 0 && !canceled.engine.forward.shouldFreeze && canceled.engine.forward.progress == 0,
              "Pulling back cancels an active countdown and releases the pointer")
        // Same pixel geometry expressed in square and wide normalized camera frames.
        func measured(aspect: Double, folded: Bool = false) -> ForwardPose? {
            func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x / aspect, y: y) }
            return ForwardPose.measure(index: p(0.4, folded ? 0.48 : 0.2), pip: p(0.4, 0.40),
                dip: p(0.4, 0.30), base: p(0.4, 0.5), littleBase: p(0.6, 0.5),
                middleBase: p(0.5, 0.5), wrist: p(0.5, 0.7), aspect: aspect, side: "left")
        }
        let square = measured(aspect: 1)!, wide = measured(aspect: 16.0 / 9)!
        check(abs(square.scale - wide.scale) < 1e-9 && abs(square.reach - wide.reach) < 1e-9,
              "Camera aspect correction preserves the forward gesture features")
        check(measured(aspect: 1, folded: true) == nil, "Folded index is rejected rather than treated as forward intent")
        check(measured(aspect: .nan) == nil, "Invalid frame geometry cannot produce gesture evidence")
        print("Passed \(checks) production interaction and forward-intent checks.")
    }
}
