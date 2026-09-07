import Foundation
import CoreGraphics

@main struct TapTests {
    static var checks = 0
    static func check(_ condition: Bool, _ message: String) {
        checks += 1; if !condition { fatalError(message) }
    }
    static func main() {
        for fps in [20.0, 30, 60] {
            var detector = TwoFingerTapDetector()
            var time = 0.0
            func feed(_ pose: TapPose?, _ count: Int) -> Int {
                var clicks = 0
                for _ in 0..<count { time += 1/fps; if detector.update(pose, time: time) { clicks += 1 } }
                return clicks
            }
            check(feed(.raised, Int(fps)) == 0, "stationary does not click")
            check(feed(.transition, 1) == 0, "transition does not click")
            check(feed(.bent, 3) == 0, "bend does not click")
            check(feed(.raised, Int(fps)) == 1, "one click on release")
            check(feed(.transition, 2) == 0 && feed(.raised, Int(fps)) == 0, "single finger does not click")
            _ = feed(.bent, 3); _ = feed(nil, 1)
            check(feed(.raised, Int(fps)) == 0, "missing frame cancels")
            _ = feed(.bent, Int(fps))
            check(feed(.raised, Int(fps)) == 0, "long hold cancels")
            _ = feed(.bent, 3); time += 1
            check(feed(.raised, Int(fps)) == 0, "stale cycle cancels")
        }
        for practice in [false, true] {
            for allowed in [false, true] {
                var engine = InteractionEngine()
                engine.configure(InteractionSettings(mode: .twoFingerTap, allowClicks: allowed, allowScrolling: true))
                var cursor = CGPoint(x: 500, y: 500)
                var time = 0.0
                var clicks = 0
                func feed(_ pose: TapPose, _ count: Int, point: CGPoint) {
                    for _ in 0..<count {
                        time += 1/30
                        let step = engine.process(index: point, pinchRatio: 0.1, timestamp: time, now: time,
                            bounds: CGRect(x: 0, y: 0, width: 1000, height: 1000), running: true, trusted: !practice,
                            destination: practice ? .practice : .system, cursorPosition: cursor, handSide: "left",
                            scrollPoint: point, tapPose: pose)
                        if let location = step.location { cursor = location }
                        if step.click { clicks += 1 }
                        check(step.scrollY == 0, "tap cannot scroll")
                        if practice { check(!step.systemClick && step.systemLocation == nil, "practice isolation") }
                    }
                }
                feed(.raised, 30, point: CGPoint(x: 0.5, y: 0.5))
                let aim = cursor
                feed(.transition, 1, point: CGPoint(x: 0.5, y: 0.52))
                feed(.bent, 3, point: CGPoint(x: 0.5, y: 0.6))
                feed(.raised, 1, point: CGPoint(x: 0.5, y: 0.5))
                check(clicks == (allowed ? 1 : 0), "click permission honored")
                if allowed { check(cursor == aim, "tap keeps target anchored") }
            }
        }
        print("Passed \(checks) two-finger tap checks")
    }
}
