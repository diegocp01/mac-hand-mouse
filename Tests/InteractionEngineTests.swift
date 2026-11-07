import Foundation
import CoreGraphics

/// Gates and settings of the production pipeline: every reason input can be
/// blocked must also cancel a click in progress, and nothing resumes it later.
@main struct InteractionEngineTests {
    static var checks = 0
    static let a = CGPoint(x: 0.3, y: 0.5), b = CGPoint(x: 0.7, y: 0.5)
    static func check(_ value: Bool, _ message: String) {
        checks += 1
        if !value { fatalError(message) }
    }
    struct Session {
        var engine = InteractionEngine()
        var time = 0.0
        var clicks = 0
        var systemOutputs = 0
        var bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
        var running = true
        var trusted = true
        var destination: InteractionDestination = .system
        var last = InteractionStep()
        var cursor = CGPoint(x: 400, y: 450)
        var fps = 30.0
        init(_ settings: InteractionSettings = InteractionSettings()) { engine.configure(settings) }
        @discardableResult mutating func frame(_ point: CGPoint? = a, side: String? = "left",
                                               timestamp: Double? = nil, now: Double? = nil) -> InteractionStep {
            time += 1 / fps
            last = engine.process(HandInput(index: point, timestamp: timestamp ?? time, handSide: side),
                                  now: now ?? time + 0.01, bounds: bounds, running: running, trusted: trusted,
                                  destination: destination, cursorPosition: cursor)
            if let location = last.location { cursor = location }
            if last.click { clicks += 1 }
            if last.systemLocation != nil || last.systemClick || last.systemRightClick || last.systemScrollY != 0 {
                systemOutputs += 1
            }
            return last
        }
        mutating func hold(_ point: CGPoint = a, seconds: Double) {
            for _ in 0..<Int((seconds * fps).rounded()) { frame(point) }
        }
    }

    static func main() {
        check(ClickPreference.restored(saved: nil, legacy: nil), "A new install enables clicks by default")
        check(!ClickPreference.restored(saved: false, legacy: true), "An explicit clicks-off choice survives relaunch and upgrade")
        check(ClickPreference.restored(saved: true, legacy: false), "The current saved setting wins over legacy preferences")
        check(!ClickPreference.restored(saved: nil, legacy: false), "Legacy clicks-off is preserved")
        let defaults = InteractionSettings()
        check(defaults.allowClicks && defaults.pointerEnabled && defaults.steadyAim && !defaults.allowScrolling && !defaults.allowDragging,
              "Engine defaults match the new-install preferences")

        for fps in [15.0, 30.0, 60.0] {
            var s = Session(); s.fps = fps
            let start = s.cursor
            check(s.frame().location == start && s.engine.acquisition.active, "The first frame takes control at the existing cursor")
            s.hold(a, seconds: 0.6)
            check(s.engine.clickPhase == .holding && s.clicks == 0, "Resting shows a countdown before it clicks")
            s.hold(a, seconds: 0.7)
            check(s.clicks == 1 && s.cursor == start, "A full rest clicks once where the pointer stopped at \(fps) fps")
            s.hold(b, seconds: 0.4)
            check(s.cursor.x > start.x + 300 && s.clicks == 1, "Aiming after a click moves normally")

            for reason in ["permission", "pause", "pointer", "display", "overflow", "stale", "future", "duplicate", "nan", "hand", "cursor", "otherHand"] {
                var s = Session(); s.fps = fps; s.hold(a, seconds: 0.6)
                check(s.engine.clickProgress > 0, "\(reason) fixture starts mid-hold")
                let step: InteractionStep
                switch reason {
                case "permission": s.trusted = false; step = s.frame()
                case "pause": s.running = false; step = s.frame()
                case "pointer": s.engine.configure(InteractionSettings(pointerEnabled: false)); step = s.frame()
                case "display": s.bounds = .zero; step = s.frame()
                case "overflow":
                    s.bounds = CGRect(x: CGFloat.greatestFiniteMagnitude, y: CGFloat.greatestFiniteMagnitude,
                                      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
                    step = s.frame()
                case "stale": step = s.frame(now: s.time + 1 / fps + 0.3)
                case "future": step = s.frame(timestamp: s.time + 2)
                case "duplicate": step = s.frame(timestamp: s.time)
                case "nan": step = s.frame(CGPoint(x: CGFloat.nan, y: 0.5))
                case "hand": step = s.frame(nil)
                case "cursor": s.cursor = CGPoint(x: -50, y: 450); step = s.frame()
                default: step = s.frame(side: "right")
                }
                check(step.location == nil && !step.click, "\(reason) blocks all output")
                check(s.engine.clickProgress == 0 && s.engine.clickPhase == .ready, "\(reason) cancels the countdown")
            }

            var restored = Session(); restored.fps = fps; restored.hold(a, seconds: 0.6)
            restored.trusted = false; restored.frame()
            restored.trusted = true; restored.hold(a, seconds: 0.6)
            check(restored.clicks == 0, "Permission restoration cannot finish the interrupted hold")
            restored.hold(a, seconds: 0.7)
            check(restored.clicks == 1, "A fresh full rest after restoration clicks once")

            var changed = Session(); changed.fps = fps; changed.hold(a, seconds: 0.6)
            changed.engine.configure(InteractionSettings(precisionMode: true))
            changed.hold(a, seconds: 0.6)
            check(changed.clicks == 0, "Changing settings restarts the hold")
            changed.hold(a, seconds: 0.7)
            check(changed.clicks == 1, "The new settings accept a complete rest")

            var moved = Session(); moved.fps = fps; moved.hold(a, seconds: 0.6)
            moved.cursor.x += 60
            let takeover = moved.cursor
            check(moved.frame().location == takeover && moved.engine.clickProgress == 0,
                  "A physical mouse move cancels the hold and control resumes at the new cursor")
            moved.hold(a, seconds: 0.6)
            check(moved.cursor == takeover && moved.clicks == 0, "Resting after a takeover restarts the countdown in place")

            var displays = Session(); displays.fps = fps; displays.hold(a, seconds: 0.6)
            displays.bounds = CGRect(x: -2560, y: -100, width: 2560, height: 1440)
            displays.cursor = CGPoint(x: -1200, y: 600)
            displays.frame()
            check(displays.engine.clickProgress == 0 && displays.cursor == CGPoint(x: -1200, y: 600),
                  "A display change cancels the hold without moving the cursor")

            for bounds in [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: -2560, y: -100, width: 2560, height: 1440)] {
                var simulated = Session(); simulated.fps = fps; simulated.bounds = bounds
                simulated.cursor = CGPoint(x: bounds.midX, y: bounds.midY)
                simulated.destination = .practice; simulated.trusted = false
                simulated.hold(a, seconds: 1.3)
                check(simulated.clicks == 1 && simulated.systemOutputs == 0,
                      "Practice clicks without Accessibility and never dispatches OS input")
                simulated.destination = .system; simulated.trusted = true
                simulated.hold(a, seconds: 1.3)
                check(simulated.clicks == 1, "Switching out of simulation cannot carry or repeat the click")
            }
        }
        print("Passed \(checks) production interaction gate checks.")
    }
}
