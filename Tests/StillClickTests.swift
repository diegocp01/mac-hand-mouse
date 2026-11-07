import Foundation
import CoreGraphics

@main struct StillClickTests {
    static var checks = 0
    static let bounds = CGRect(x: -1440, y: -100, width: 1440, height: 900)

    static func check(_ condition: Bool, _ message: String) {
        checks += 1
        if !condition { fatalError(message) }
    }

    struct Trace {
        var detector = StillClickDetector()
        var fps: Double
        var time = 0.0
        var clicks = 0
        mutating func hold(at point: CGPoint?, seconds: Double) {
            for _ in 0..<max(1, Int((seconds * fps).rounded())) {
                time += 1 / fps
                if detector.update(location: point, time: time) { clicks += 1 }
            }
        }
    }

    struct Session {
        var engine = InteractionEngine()
        var fps: Double
        var time = 0.0
        var cursor = CGPoint(x: -720, y: 350)
        var clicks = 0
        var rightClicks = 0
        init(fps: Double, allowClicks: Bool = true) {
            self.fps = fps
            engine.configure(InteractionSettings(allowClicks: allowClicks))
        }
        mutating func hold(_ point: CGPoint, right: Double? = 1.2, seconds: Double) {
            for _ in 0..<max(1, Int((seconds * fps).rounded())) {
                time += 1 / fps
                let step = engine.process(HandInput(index: point, timestamp: time, handSide: "left", palm: point,
                        fiveFingerPinchRatio: right, threeFingerPinchRatio: 0.9),
                    now: time + 0.01, bounds: bounds, running: true, trusted: true, cursorPosition: cursor)
                if let location = step.location { cursor = location }
                if step.click { clicks += 1 }
                if step.rightClick { rightClicks += 1 }
            }
        }
    }

    static func main() {
        let here = CGPoint(x: 100, y: 100)
        for fps in [15.0, 30.0, 60.0] {
            var trace = Trace(fps: fps)
            trace.hold(at: here, seconds: 0.2)
            check(trace.detector.phase == .ready && trace.detector.progress == 0, "Brief pauses show no ring")
            trace.hold(at: here, seconds: 0.5)
            check(trace.detector.phase == .holding && trace.detector.progress > 0, "Settled pointer starts the ring")
            check(trace.clicks == 0, "No click before the ring fills")
            trace.hold(at: here, seconds: 0.4)
            check(trace.clicks == 1 && trace.detector.phase == .clicked, "Holding still for one second clicks once at \(fps) fps")
            trace.hold(at: here, seconds: 3)
            check(trace.clicks == 1, "Resting in place never repeats clicks")
            trace.hold(at: CGPoint(x: here.x + 20, y: here.y), seconds: 2)
            check(trace.clicks == 1, "Small drift after a click cannot rearm")
            trace.hold(at: CGPoint(x: here.x + 80, y: here.y), seconds: 1.1)
            check(trace.clicks == 2, "Moving away and holding still again clicks again")

            var jitter = Trace(fps: fps)
            for i in 0..<Int(fps * 1.2) {
                jitter.hold(at: CGPoint(x: here.x + (i % 2 == 0 ? 5 : -5), y: here.y + (i % 3 == 0 ? 4 : -4)), seconds: 1 / fps)
            }
            check(jitter.clicks == 1, "Hand tremor inside the still circle still clicks")

            var moving = Trace(fps: fps)
            for i in 0..<Int(fps * 3) {
                moving.hold(at: CGPoint(x: here.x + Double(i) * 300 / fps, y: here.y), seconds: 1 / fps)
            }
            check(moving.clicks == 0, "Continuous aiming never clicks")

            var cancel = Trace(fps: fps)
            cancel.hold(at: here, seconds: 0.6)
            cancel.hold(at: CGPoint(x: here.x + 40, y: here.y), seconds: 1 / fps)
            check(cancel.detector.phase == .ready && cancel.detector.lastCancellation == .movement, "Moving away cancels a filling ring")
            check(cancel.clicks == 0, "A canceled ring does not click")

            var lost = Trace(fps: fps)
            lost.hold(at: here, seconds: 0.6)
            lost.hold(at: nil, seconds: 1 / fps)
            lost.hold(at: here, seconds: 0.5)
            check(lost.clicks == 0, "Lost tracking restarts the full hold instead of finishing it")
        }

        // Production engine: aiming clicks after holding still.
        for fps in [15.0, 30.0, 60.0] {
            var session = Session(fps: fps)
            let aim = CGPoint(x: 0.5, y: 0.5)
            session.hold(aim, seconds: 1.4)
            check(session.clicks == 1, "Engine clicks after the pointer rests at \(fps) fps")
            session.hold(aim, seconds: 2)
            check(session.clicks == 1, "Engine never repeats a click in place")
            for i in 0..<Int(fps * 0.5) { session.hold(CGPoint(x: 0.5 + Double(i) * 0.15 / fps, y: 0.5), seconds: 1 / fps) }
            session.hold(CGPoint(x: 0.65, y: 0.5), seconds: 1.2)
            check(session.clicks == 2, "Engine rearms after moving away")

            var right = Session(fps: fps)
            right.hold(aim, seconds: 0.3)
            right.hold(aim, right: 0.4, seconds: 1.2)
            check(right.clicks == 0 && right.rightClicks == 1, "A five-finger pinch right-clicks without a left click")

            var off = Session(fps: fps, allowClicks: false)
            off.hold(aim, seconds: 2)
            check(off.clicks == 0, "Disabled clicks never fire")
        }
        print("Still click: \(checks) checks passed.")
    }
}
