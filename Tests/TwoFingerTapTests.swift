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
        // A gradual bend must keep the original target through release. Exercise
        // the production path at camera rates, with both input destinations/gates.
        for fps in [15.0, 30, 60] {
            for practice in [false, true] {
                for allowed in [false, true] {
                    var engine = InteractionEngine()
                    engine.configure(InteractionSettings(mode: .twoFingerTap, allowClicks: allowed))
                    var cursor = CGPoint(x: 500, y: 500)
                    var time = 0.0
                    var clicks = 0
                    func feed(_ pose: TapPose, seconds: Double, y: Double) {
                        for _ in 0..<Int((fps * seconds).rounded(.up)) {
                            time += 1 / fps
                            let step = engine.process(index: CGPoint(x: 0.5, y: y), pinchRatio: nil,
                                timestamp: time, now: time, bounds: CGRect(x: 0, y: 0, width: 1000, height: 1000),
                                running: true, trusted: !practice, destination: practice ? .practice : .system,
                                cursorPosition: cursor, handSide: "left", tapPose: pose)
                            if let location = step.location { cursor = location }
                            if step.click { clicks += 1 }
                            if practice { check(!step.systemClick && step.systemLocation == nil, "slow practice tap stays isolated") }
                        }
                    }
                    feed(.raised, seconds: 1, y: 0.5)
                    let aim = cursor
                    feed(.transition, seconds: 0.7, y: 0.54)
                    feed(.bent, seconds: 0.15, y: 0.6)
                    feed(.raised, seconds: 1 / fps, y: 0.52)
                    check(clicks == (allowed ? 1 : 0), "gradual bend respects click gate at \(fps) fps")
                    if allowed { check(cursor == aim, "gradual bend and release preserve target at \(fps) fps") }
                    feed(.raised, seconds: 0.5, y: 0.52)
                    check(clicks == (allowed ? 1 : 0), "gradual tap never repeats while raised")
                }
            }
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
        for practice in [false, true] {
            var engine = InteractionEngine()
            engine.configure(InteractionSettings(mode: .twoFingerTap))
            var cursor = CGPoint(x: 500, y: 500)
            var time = 0.0
            var clicks = 0
            func feed(_ ratio: Double?, _ pose: TapPose? = .raised, x: Double = 0.5) {
                time += 1.0 / 30
                let step = engine.process(index: CGPoint(x: x, y: 0.5), pinchRatio: nil,
                    timestamp: time, now: time, bounds: CGRect(x: 0, y: 0, width: 1000, height: 1000),
                    running: true, trusted: !practice, destination: practice ? .practice : .system,
                    cursorPosition: cursor, handSide: "left", tapPose: pose, fingerSeparationRatio: ratio)
                if let location = step.location { cursor = location }
                if step.click { clicks += 1 }
                if practice { check(step.systemLocation == nil && !step.systemClick, "close lock stays in practice") }
            }
            for _ in 0..<30 { feed(0.6) }
            feed(0.6, x: 0.52)
            let aim = cursor
            feed(0.30, x: 0.6)
            check(cursor == aim && clicks == 0, "first touching frame freezes without clicking")
            for _ in 0..<30 { feed(0.35, x: 0.65) }
            check(cursor == aim, "hysteresis holds lock while raised")
            feed(nil, nil, x: 0.7)
            check(cursor == aim, "missing proximity does not unlock")
            for _ in 0..<30 { feed(0.2, .raised, x: 0.7) }
            for _ in 0..<3 { feed(0.2, .bent, x: 0.7) }
            feed(0.2, .raised, x: 0.7)
            check(cursor == aim && clicks == 1, "tap clicks at locked target")
            for _ in 0..<30 { feed(0.2, .raised, x: 0.7) }
            for _ in 0..<30 { feed(0.2, .bent, x: 0.7) }
            check(cursor == aim && clicks == 1, "tap timeout does not release close lock")
            feed(0.42, .raised, x: 0.7)
            check(cursor == aim, "separation reanchors without jump")
            feed(0.6, x: 0.72)
            check(cursor.x > aim.x, "movement resumes after separation")
            engine.configure(InteractionSettings(mode: .twoFingerTap, allowClicks: false))
            for _ in 0..<30 { feed(0.2, x: 0.5) }
            let before = cursor
            feed(0.2, x: 0.6)
            check(cursor.x > before.x && clicks == 1, "clicks off bypasses proximity lock")
        }
        // A visible second hand suppresses taps before a drag pose is recognized.
        // The persistent guide must observe that same modifier, not just drag.phase.
        for practice in [false, true] {
            var engine = InteractionEngine()
            engine.configure(InteractionSettings(mode: .twoFingerTap, allowDragging: true))
            var time = 0.0
            func feed(companion: Bool) {
                time += 1.0 / 30
                let step = engine.process(index: CGPoint(x: 0.5, y: 0.5), pinchRatio: nil,
                    timestamp: time, now: time, bounds: CGRect(x: 0, y: 0, width: 1000, height: 1000),
                    running: true, trusted: !practice, destination: practice ? .practice : .system,
                    cursorPosition: CGPoint(x: 500, y: 500), handSide: "left",
                    companionPresent: companion, tapPose: .raised)
                check(!step.click, "showing or hiding a companion hand never clicks")
            }
            for _ in 0..<30 { feed(companion: false) }
            check(engine.tap.phase == .ready && !engine.dragModifierPresent, "single hand is ready to tap")
            feed(companion: true)
            check(engine.dragModifierPresent && engine.drag.phase == .idle && engine.tap.phase == .waiting,
                "guide sees modifier before a drag starts")
            feed(companion: false)
            check(!engine.dragModifierPresent, "lowering companion restores tap guide")
            feed(companion: true)
            engine.trackingInterrupted()
            check(!engine.dragModifierPresent, "tracking loss clears companion feedback")
        }
        // Pinch scrolling uses the production engine, including arbitration and release.
        for practice in [false, true] {
            for clicksAllowed in [false, true] {
                var engine = InteractionEngine()
                engine.configure(InteractionSettings(mode: .twoFingerTap, allowClicks: clicksAllowed, allowScrolling: true))
                var cursor = CGPoint(x: 500, y: 500)
                var time = 0.0
                var totalScroll: Int32 = 0
                func feed(_ ratio: Double?, y: Double = 0.5, pose: TapPose = .raised) -> InteractionStep {
                    time += 1.0 / 30
                    let step = engine.process(index: CGPoint(x: 0.5, y: y), pinchRatio: nil,
                        timestamp: time, now: time, bounds: CGRect(x: 0, y: 0, width: 1000, height: 1000),
                        running: true, trusted: !practice, destination: practice ? .practice : .system,
                        cursorPosition: cursor, handSide: "left", scrollPoint: CGPoint(x: 0.5, y: y),
                        palm: CGPoint(x: 0.5, y: y), tapPose: pose, scrollPinchRatio: ratio)
                    if let location = step.location { cursor = location }
                    totalScroll += step.scrollY
                    check(!step.click, "scroll never clicks")
                    if practice { check(step.systemScrollY == 0 && step.systemLocation == nil, "scroll practice isolation") }
                    return step
                }
                for _ in 0..<30 { _ = feed(0.8) }
                check(engine.scroll.phase == .idle && totalScroll == 0, "extended fingers without pinch cannot scroll")
                let aim = cursor
                _ = feed(0.2, pose: .bent)
                check(cursor == aim && engine.scroll.phase == .confirming, "pinch freezes immediately and cancels tap")
                for _ in 0..<10 { _ = feed(0.2, pose: .bent) }
                check(engine.scroll.phase == .scrolling, "steady pinch arms scrolling")
                _ = feed(0.5, y: 0.48, pose: .bent)
                check(totalScroll > 0 && cursor == aim, "pinch hysteresis scrolls without cursor motion")
                let beforeRelease = totalScroll
                _ = feed(0.8, y: 0.46)
                check(totalScroll == beforeRelease && cursor == aim && engine.scroll.phase == .idle, "release stops immediately without jump")
                _ = feed(0.8, y: 0.44)
                check(cursor.y < aim.y, "aiming resumes after pinch release")
                for _ in 0..<11 { _ = feed(0.2, y: 0.44) }
                let beforeLoss = totalScroll
                _ = feed(nil, y: 0.42)
                check(totalScroll == beforeLoss && engine.scroll.phase == .idle, "missing pinch evidence stops scroll")
                engine.configure(InteractionSettings(mode: .twoFingerTap, allowClicks: false, allowScrolling: false))
                for _ in 0..<30 { _ = feed(0.2) }
                _ = feed(0.2, y: 0.48)
                check(totalScroll == beforeLoss && engine.scroll.phase == .idle, "disabled scrolling ignores pinch")
            }
        }
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        var normal = PointerFilter(), precise = PointerFilter()
        let center = CGPoint(x: 500, y: 500)
        normal.reanchor(point: CGPoint(x: 0.5, y: 0.5), cursor: center, bounds: bounds, time: 0)
        precise.reanchor(point: CGPoint(x: 0.5, y: 0.5), cursor: center, bounds: bounds, time: 0)
        var normalPoint = center, precisePoint = center
        for i in 1...30 {
            normalPoint = normal.update(point: CGPoint(x: 0.55, y: 0.5), bounds: bounds, time: Double(i)/30, freeze: false)
            precisePoint = precise.update(point: CGPoint(x: 0.55, y: 0.5), bounds: bounds, time: Double(i)/30, precision: true, freeze: false)
        }
        check(precisePoint.x > center.x && precisePoint.x - center.x < (normalPoint.x - center.x) * 0.4, "precision reduces travel to about 35 percent")
        let frozen = precise.update(point: CGPoint(x: 0.7, y: 0.5), bounds: bounds, time: 1.1, precision: true, freeze: true)
        check(frozen == precisePoint, "precision respects target lock")
        print("Passed \(checks) two-finger tap checks")
    }
}
