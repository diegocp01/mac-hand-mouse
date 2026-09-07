import Foundation
import CoreGraphics

@main struct IntentClickTests {
    static var checks = 0
    static let aim = CGPoint(x: 0.5, y: 0.5)
    static let bounds = CGRect(x: -1440, y: -100, width: 1440, height: 900)

    static func check(_ condition: Bool, _ message: String) {
        checks += 1
        if !condition { fatalError(message) }
    }

    struct HoldTrace {
        var detector = PointHoldDetector()
        var fps: Double
        var time = 0.0
        var clicks = 0

        @discardableResult mutating func frame(_ pose: PointingPose?, point: CGPoint? = aim,
                gap: Double? = nil) -> Bool {
            time += gap ?? 1 / fps
            let fired = detector.update(pose: pose, point: point, time: time)
            if fired { clicks += 1 }
            return fired
        }

        mutating func hold(_ pose: PointingPose?, seconds: Double, point: CGPoint? = aim) {
            for _ in 0..<Int(ceil(seconds * fps)) { frame(pose, point: point) }
        }
    }

    struct RightTrace {
        var detector = FiveFingerPinchDetector()
        var fps: Double
        var time = 0.0
        var clicks = 0

        @discardableResult mutating func frame(_ ratio: Double?, gap: Double? = nil) -> Bool {
            time += gap ?? 1 / fps
            let fired = detector.update(ratio: ratio, time: time)
            if fired { clicks += 1 }
            return fired
        }

        mutating func hold(_ ratio: Double?, seconds: Double) {
            for _ in 0..<Int(ceil(seconds * fps)) { frame(ratio) }
        }
    }

    struct Session {
        var engine = InteractionEngine()
        var fps: Double
        var destination: InteractionDestination
        var time = 0.0
        var cursor = CGPoint(x: -720, y: 350)
        var leftClicks = 0
        var rightClicks = 0
        var scroll = Int32(0)
        var last = InteractionStep()

        init(fps: Double, practice: Bool, allowClicks: Bool = true, allowScrolling: Bool = true) {
            self.fps = fps; destination = practice ? .practice : .system
            engine.configure(InteractionSettings(mode: .pointAndHold,
                allowClicks: allowClicks, allowScrolling: allowScrolling))
        }

        @discardableResult mutating func frame(_ pose: PointingPose? = .move,
                point: CGPoint? = aim, right: Double? = 1.2, scrollPinch: Double? = 0.9,
                age: Double = 0.01, gap: Double? = nil, trusted: Bool = true) -> InteractionStep {
            time += gap ?? 1 / fps
            last = engine.process(index: point, pinchRatio: nil, timestamp: time, now: time + age,
                bounds: bounds, running: true, trusted: trusted && destination == .system,
                destination: destination, cursorPosition: cursor, handSide: "left",
                palm: point, scrollPinchRatio: scrollPinch, pointingPose: pose, fiveFingerPinchRatio: right)
            if let location = last.location { cursor = location }
            if last.click { leftClicks += 1 }
            if last.rightClick { rightClicks += 1 }
            scroll += last.scrollY
            check(!(last.click && last.rightClick), "A frame cannot emit both mouse buttons")
            if destination == .practice {
                check(last.systemLocation == nil && !last.systemClick && !last.systemRightClick &&
                    last.systemScrollY == 0 && !last.systemButtonHeld,
                    "Point-and-hold practice cannot emit any system input")
            }
            return last
        }

        mutating func hold(_ pose: PointingPose? = .move, seconds: Double = 0.7,
                point: CGPoint? = aim, right: Double? = 1.2, scrollPinch: Double? = 0.9) {
            for _ in 0..<Int(ceil(seconds * fps)) {
                frame(pose, point: point, right: right, scrollPinch: scrollPinch)
            }
        }
    }

    static func main() {
        var sparseRight = FiveFingerPinchDetector()
        for time in [0.0, 0.05, 0.10, 0.15, 0.20] {
            _ = sparseRight.update(ratio: 1.2, time: time)
        }
        check(!sparseRight.update(ratio: 0.4, time: 0.25) &&
            !sparseRight.update(ratio: 0.4, time: 0.36),
            "Two closed observations cannot right click even after 100 ms")
        check(sparseRight.update(ratio: 0.4, time: 0.38),
            "A third timely closed observation completes an otherwise confirmed right pinch")

        for fps in [15.0, 30.0, 60.0] {
            // An exact deadline uses exactly representable start/end times. Ordinary
            // gesture fixtures below deliberately avoid minimum-duration boundaries.
            var exact = PointHoldDetector()
            for i in 0..<Int(fps) {
                check(!exact.update(pose: .move, point: aim, time: Double(i) / fps),
                    "Index-only pointing never clicks")
            }
            check(exact.phase == .ready, "A sustained move pose arms the hold detector")
            check(!exact.update(pose: .click, point: aim, time: 1), "Raising the middle finger starts a countdown")
            for i in 1..<Int(fps) {
                check(!exact.update(pose: .click, point: aim, time: 1 + Double(i) / fps),
                    "The hold cannot click before one full second")
            }
            check(exact.update(pose: .click, point: aim, time: 2),
                "A steady armed pose clicks at the one-second deadline")
            check(exact.phase == .clicked && exact.shouldFreeze,
                "The completed hold remains latched at its target")
            for i in 1...Int(2 * fps) {
                check(!exact.update(pose: .click, point: aim, time: 2 + Double(i) / fps),
                    "Keeping two fingers raised cannot repeat clicks")
            }

            var hold = HoldTrace(fps: fps)
            hold.hold(.click, seconds: 1.5)
            check(hold.clicks == 0, "Starting with two fingers raised cannot inherit an armed hold")
            hold.hold(.move, seconds: 0.5)
            hold.hold(.click, seconds: 0.4)
            hold.frame(.click, point: CGPoint(x: 0.54, y: 0.5))
            hold.hold(.click, seconds: 1.3, point: CGPoint(x: 0.54, y: 0.5))
            check(hold.clicks == 0 && hold.detector.phase == .needsMove,
                "Excessive hand motion cancels and cannot restart a hold until the move pose returns")
            hold.hold(.move, seconds: 0.5)
            hold.hold(.click, seconds: 1.2)
            check(hold.clicks == 1, "A deliberate move pose rearms a canceled hold")
            hold.hold(.move, seconds: 0.5)
            hold.hold(.click, seconds: 0.4)
            hold.frame(nil)
            hold.hold(.click, seconds: 1.3)
            check(hold.clicks == 1 && hold.detector.phase == .needsMove,
                "Unknown pose evidence cancels and cannot complete a pending hold")
            hold.hold(.move, seconds: 0.5)
            hold.hold(.click, seconds: 0.4)
            hold.frame(.click, gap: 0.3)
            hold.hold(.click, seconds: 1.3)
            check(hold.clicks == 1, "A delivery gap cannot finish or silently restart the hold")
            hold.hold(.move, seconds: 0.5)
            hold.frame(.click, point: CGPoint(x: .nan, y: 0.5))
            hold.hold(.click, seconds: 1.3)
            check(hold.clicks == 1, "Invalid geometry is not click intent")

            var right = RightTrace(fps: fps)
            right.hold(0.4, seconds: 0.5)
            check(right.clicks == 0, "An already closed five-finger pinch cannot click before visible open evidence")
            right.hold(1.2, seconds: 0.5)
            let began = right.time + 1 / fps
            var firstClick: Double?
            for _ in 0..<Int(ceil(0.4 * fps)) {
                if right.frame(0.4), firstClick == nil { firstClick = right.time }
                if right.time - began < 0.1 - 1e-9 {
                    check(right.clicks == 0, "A right pinch needs at least 100 ms of confirmation")
                }
            }
            check(right.clicks == 1 && firstClick != nil && firstClick! - began >= 0.1 - 1e-9,
                "A deliberate five-finger pinch clicks once after confirmation")
            right.hold(0.4, seconds: 1.3)
            check(right.clicks == 1 && right.detector.phase == .held, "Holding the pinch cannot repeat right clicks")
            right.hold(0.9, seconds: 0.5)
            right.hold(0.4, seconds: 0.5)
            check(right.clicks == 1, "A partial reopening releases but does not replace confident open evidence")
            right.hold(1.2, seconds: 0.5)
            right.hold(0.4, seconds: 0.4)
            check(right.clicks == 2, "A fully reopened hand can right click again")
            right.hold(1.2, seconds: 0.5)
            right.frame(0.4); right.frame(nil)
            right.hold(0.4, seconds: 0.4)
            check(right.clicks == 2 && right.detector.phase == .needsOpen,
                "Missing right-pinch measurements require a new open hand")
            right.hold(1.2, seconds: 0.5)
            right.frame(0.4); right.frame(0.4, gap: 0.3)
            right.hold(0.4, seconds: 0.4)
            check(right.clicks == 2, "A tracking gap cannot confirm a right pinch")
            right.hold(1.2, seconds: 0.5)
            right.frame(0.4)
            right.hold(0.65, seconds: 0.2)
            right.hold(0.4, seconds: 0.4)
            check(right.clicks == 2 && right.detector.phase == .needsOpen,
                "A visibly canceled right confirmation needs a fully open hand before retrying")
            right.hold(1.2, seconds: 0.5)
            right.hold(0.4, seconds: 0.4)
            check(right.clicks == 3, "Fully reopening rearms a canceled right confirmation")

            for practice in [false, true] {
                var session = Session(fps: fps, practice: practice)
                let initial = session.cursor
                session.hold(.click, seconds: 1.2)
                check(!session.engine.acquisition.active && session.cursor == initial && session.leftClicks == 0,
                    "Only the move pose may initially acquire the pointer")
                session.hold(.move, seconds: 0.15)
                check(!session.engine.acquisition.active && session.cursor == initial,
                    "Acquisition waits for 250 ms of stable index-only pointing")
                session.hold()
                check(session.engine.acquisition.active && session.cursor == initial,
                    "Move-pose acquisition keeps the existing cursor on a negative-origin display")
                session.hold(.move, seconds: 1.5)
                check(session.leftClicks == 0 && session.rightClicks == 0,
                    "A stationary index-only hand does not click")
                for i in 1...Int(fps) {
                    session.frame(.move, point: CGPoint(x: 0.5 + 0.03 * Double(i) / fps, y: 0.5))
                }
                let point = CGPoint(x: 0.53, y: 0.5)
                session.hold(.move, point: point)
                check(session.cursor.x > initial.x, "Index-only movement remains usable")
                let target = session.cursor
                let holdStart = session.time + 1 / fps
                session.frame(.click, point: point)
                check(session.cursor == target && session.leftClicks == 0,
                    "The first two-finger pose freezes the aimed target immediately")
                for _ in 0..<Int(ceil(1.2 * fps)) {
                    session.frame(.click, point: point)
                    if session.time - holdStart < 1 - 1e-9 {
                        check(session.leftClicks == 0, "The production path cannot send an early left click")
                    }
                    check(session.cursor == target, "The countdown and click stay at the aimed position")
                }
                session.hold(.click, seconds: 1.3, point: point)
                check(session.leftClicks == 1 && session.rightClicks == 0 && session.cursor == target,
                    "A held two-finger pose sends exactly one left click")
                session.frame(.move, point: CGPoint(x: 0.55, y: 0.5))
                check(session.cursor == target, "Returning to the move pose does not release accumulated motion")
                session.hold(.move, point: CGPoint(x: 0.55, y: 0.5))

                session.hold(.click, seconds: 0.4, point: CGPoint(x: 0.55, y: 0.5))
                let cancelTarget = session.cursor
                session.frame(.click, point: CGPoint(x: 0.60, y: 0.5))
                session.hold(.click, seconds: 1.2, point: CGPoint(x: 0.60, y: 0.5))
                check(session.cursor == cancelTarget && session.leftClicks == 1,
                    "Motion cancellation keeps the cursor still until move intent returns")
                session.frame(.move, point: CGPoint(x: 0.60, y: 0.5))
                check(session.cursor == cancelTarget, "Cancel recovery reanchors without jumping")
                session.hold(.move, point: CGPoint(x: 0.60, y: 0.5))
                session.hold(.click, seconds: 0.4, point: CGPoint(x: 0.60, y: 0.5))
                session.frame(nil, point: CGPoint(x: 0.60, y: 0.5))
                session.hold(.click, seconds: 1.2, point: CGPoint(x: 0.60, y: 0.5))
                check(session.leftClicks == 1, "Unknown production pose cancels pending click intent")
                session.hold(.move, point: CGPoint(x: 0.60, y: 0.5))

                let rightTarget = session.cursor
                let beforeScroll = session.scroll
                session.hold(nil, seconds: 0.45, point: CGPoint(x: 0.60, y: 0.5), right: 0.4, scrollPinch: 0.2)
                check(session.rightClicks == 1 && session.leftClicks == 1 && session.scroll == beforeScroll &&
                    session.cursor == rightTarget, "Five-finger pinch wins over scrolling and emits only one right click")
                session.hold(nil, seconds: 1, point: CGPoint(x: 0.60, y: 0.45), right: 0.4, scrollPinch: 0.2)
                check(session.rightClicks == 1 && session.leftClicks == 1 && session.scroll == beforeScroll,
                    "Moving a held right pinch cannot leak into scroll or left click")

                var priority = Session(fps: fps, practice: practice)
                priority.hold(); priority.hold(.click, seconds: 0.7)
                priority.hold(.click, seconds: 0.45, right: 0.4, scrollPinch: 0.2)
                check(priority.rightClicks == 1 && priority.leftClicks == 0 && priority.scroll == 0,
                    "Right pinch cancels a pending left countdown even with overlapping pose evidence")
                priority.hold(.click, seconds: 1.2)
                check(priority.rightClicks == 1 && priority.leftClicks == 0,
                    "Reopening after a right click cannot revive the canceled left countdown")

                var stagedRight = Session(fps: fps, practice: practice)
                stagedRight.hold()
                let stagedTarget = stagedRight.cursor
                // Thumb and index can meet before the other three fingertips arrive.
                // This short transitional pinch is not yet a completed scroll gesture.
                stagedRight.hold(nil, seconds: 0.2, right: 1.2, scrollPinch: 0.2)
                stagedRight.hold(nil, seconds: 0.45, right: 0.4, scrollPinch: 0.2)
                check(stagedRight.rightClicks == 1 && stagedRight.leftClicks == 0 && stagedRight.scroll == 0 &&
                    stagedRight.cursor == stagedTarget,
                    "Closing thumb and index first cannot discard the armed five-finger right click")

                var stale = Session(fps: fps, practice: practice)
                stale.hold(); stale.hold(.click, seconds: 0.7)
                let rejected = stale.frame(.click, age: 0.3)
                check(rejected.blocked == .staleFrame && !rejected.click && !rejected.rightClick,
                    "Stale frames never produce either button")
                stale.hold(.click, seconds: 1.2)
                check(stale.leftClicks == 0 && stale.rightClicks == 0,
                    "A stale countdown cannot resume without fresh move intent")
                stale.hold(); stale.frame(nil, right: 0.4)
                stale.frame(nil, right: 0.4, age: 0.3)
                stale.hold(nil, seconds: 0.4, right: 0.4)
                check(stale.rightClicks == 0, "A stale pinch cannot finish a right click")

                var disabled = Session(fps: fps, practice: practice, allowClicks: false, allowScrolling: false)
                disabled.hold(); disabled.hold(.click, seconds: 1.3)
                disabled.hold(nil, seconds: 0.4, right: 0.4)
                check(disabled.leftClicks == 0 && disabled.rightClicks == 0 && disabled.scroll == 0 &&
                    !disabled.last.systemButtonHeld, "Disabling clicks suppresses both gesture buttons")

                if !practice {
                    var denied = Session(fps: fps, practice: false)
                    denied.hold(); denied.hold(.click, seconds: 0.7)
                    let blocked = denied.frame(.click, trusted: false)
                    check(blocked.blocked == .permission && blocked.systemLocation == nil &&
                        !blocked.systemClick && !blocked.systemRightClick,
                        "Permission loss cancels a pending hold before system input")
                    denied.hold(.click, seconds: 1.2)
                    check(denied.leftClicks == 0 && denied.rightClicks == 0,
                        "Restored permission cannot finish the old gesture")
                }
            }
        }
        print("Passed \(checks) intent click checks")
    }
}
