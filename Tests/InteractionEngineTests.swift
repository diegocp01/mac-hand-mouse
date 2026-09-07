import Foundation
import CoreGraphics

@main struct InteractionEngineTests {
    static var checks = 0
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
        var last = InteractionStep()
        @discardableResult mutating func frame(_ point: CGPoint? = CGPoint(x: 0.5, y: 0.5), ratio: Double? = 0.9,
                                                dt: Double = 1.0 / 30) -> InteractionStep {
            time += dt
            last = engine.process(index: point, pinchRatio: ratio, timestamp: time, now: time + 0.01,
                                  bounds: bounds, running: running, trusted: trusted)
            if last.click { clicks += 1 }
            return last
        }
        mutating func hold(_ point: CGPoint = CGPoint(x: 0.5, y: 0.5), seconds: Double, fps: Double = 30) {
            for _ in 0..<Int(ceil(seconds * fps)) { frame(point, dt: 1 / fps) }
        }
    }

    static func main() {
        let a = CGPoint(x: 0.3, y: 0.5), b = CGPoint(x: 0.7, y: 0.5)
        for fps in [15.0, 30.0, 60.0] {
            var s = Session()
            s.engine.configure(InteractionSettings(mode: .dwell, allowClicks: false))
            s.hold(a, seconds: 1, fps: fps)
            let before = s.last.location!
            s.hold(b, seconds: 0.5, fps: fps)
            check(s.clicks == 0 && s.engine.dwell.progress == 0, "Clicks-off practice never arms a dwell")
            check(s.last.location!.x > before.x + 800, "Clicks-off practice never freezes movement")

            s = Session()
            s.engine.configure(InteractionSettings(mode: .dwell, allowClicks: true))
            s.hold(a, seconds: 0.3, fps: fps)
            check(s.engine.dwell.progress > 0 && s.clicks == 0, "Production engine reports active countdown")
            let moved = s.frame(b, dt: 1 / fps)
            check(moved.restartedDwell && !moved.click, "Move cancels the production dwell")
            s.hold(b, seconds: 0.3, fps: fps)
            check(s.clicks == 0, "Movement cannot inherit the previous countdown")
            s.hold(b, seconds: 0.5, fps: fps)
            check(s.clicks == 1, "Re-aim and hold sends one click")
            let target = PointerFilter().unfrozenTarget(point: b, bounds: s.bounds)
            check(abs(s.last.location!.x - target.x) < 20, "Re-aimed dwell reaches the new target across frame rates")
            s.engine.trackingInterrupted()
            s.hold(b, seconds: 1, fps: fps)
            check(s.clicks == 1 && s.engine.dwell.phase == .needMove, "A stalled camera cannot re-click a stationary target")
            s.hold(a, seconds: 1, fps: fps)
            check(s.clicks == 2, "Movement after a stall still permits a deliberate second click")
        }

        var pinch = Session()
        pinch.engine.configure(InteractionSettings(allowClicks: true))
        pinch.hold(a, seconds: 0.2)
        let aimed = pinch.last.location!
        pinch.frame(b, ratio: 0.40)
        let fired = pinch.frame(b, ratio: 0.40)
        check(fired.click && fired.location == aimed, "Actual engine freezes before a closing pinch moves the pointer")

        for reason in ["permission", "pause", "pointer", "display", "overflow", "stale", "future", "duplicate", "nan"] {
            var s = Session()
            s.engine.configure(InteractionSettings(mode: .dwell, allowClicks: true))
            s.hold(a, seconds: 0.3)
            let step: InteractionStep
            switch reason {
            case "permission": s.trusted = false; step = s.frame(a)
            case "pause": s.running = false; step = s.frame(a)
            case "pointer": s.engine.configure(InteractionSettings(mode: .dwell, allowClicks: true, pointerEnabled: false)); step = s.frame(a)
            case "display": s.bounds = .zero; step = s.frame(a)
            case "overflow":
                s.bounds = CGRect(x: CGFloat.greatestFiniteMagnitude, y: CGFloat.greatestFiniteMagnitude,
                                  width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
                step = s.frame(a)
            case "nan": step = s.frame(CGPoint(x: CGFloat.nan, y: 0.5))
            default:
                let stamp = reason == "future" ? s.time + 1 : s.time
                let now = reason == "stale" ? s.time + 0.3 : s.time + 0.01
                step = s.engine.process(index: a, pinchRatio: 0.9, timestamp: stamp, now: now,
                                        bounds: s.bounds, running: true, trusted: true)
            }
            check(step.location == nil && !step.click, "\(reason) blocks all pointer and click output")
            check(s.engine.dwell.progress == 0, "\(reason) cancels active progress")
        }

        var restored = Session()
        restored.engine.configure(InteractionSettings(mode: .dwell, allowClicks: true))
        restored.hold(a, seconds: 0.4)
        restored.trusted = false; restored.frame(a)
        restored.trusted = true; restored.hold(a, seconds: 0.4)
        check(restored.clicks == 0, "Permission restoration starts a fresh countdown")
        restored.hold(a, seconds: 0.4)
        check(restored.clicks == 1, "A full countdown after permission restoration clicks once")

        var duration = Session()
        duration.engine.configure(InteractionSettings(mode: .dwell, allowClicks: true))
        duration.hold(a, seconds: 0.4)
        duration.engine.configure(InteractionSettings(mode: .dwell, allowClicks: true, dwellSeconds: 1.5))
        check(duration.engine.dwell.progress == 0, "Changing hold time cancels old progress")
        duration.hold(a, seconds: 1)
        check(duration.clicks == 0 && duration.engine.dwell.remainingSeconds > 0.4, "Longer hold time drives actual click timing")
        duration.hold(a, seconds: 0.6)
        check(duration.clicks == 1, "Longer dwell eventually produces exactly one click")
        print("Passed \(checks) production interaction-engine checks.")
    }
}
