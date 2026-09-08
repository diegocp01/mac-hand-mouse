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
                legacyPinch: Double? = 0.9,
                age: Double = 0.01, gap: Double? = nil, trusted: Bool = true) -> InteractionStep {
            time += gap ?? 1 / fps
            last = engine.process(index: point, pinchRatio: nil, timestamp: time, now: time + age,
                bounds: bounds, running: true, trusted: trusted && destination == .system,
                destination: destination, cursorPosition: cursor, handSide: "left",
                palm: point, scrollPinchRatio: legacyPinch, pointingPose: pose, fiveFingerPinchRatio: right,
                threeFingerPinchRatio: scrollPinch)
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
                point: CGPoint? = aim, right: Double? = 1.2, scrollPinch: Double? = 0.9,
                legacyPinch: Double? = 0.9) {
            for _ in 0..<Int(ceil(seconds * fps)) {
                frame(pose, point: point, right: right, scrollPinch: scrollPinch, legacyPinch: legacyPinch)
            }
        }
    }

    static func main() {
        let openPose = PointingPoseClassifier.classify(index: .extended, middle: .extended, ring: .extended, little: .extended)
        check(openPose == .move, "An open hand prepares a click while aiming")
        let twoPose = PointingPoseClassifier.classify(index: .extended, middle: .extended, ring: .folded, little: .uncertain)
        check(twoPose == .click, "Two raised fingers tolerate one obscured folded outer finger")
        check(PointingPoseClassifier.classify(index: .extended, middle: .extended, ring: .uncertain, little: .uncertain) == nil,
            "Two missing outer fingers cannot establish a click gesture")
        check(PointingPoseClassifier.classify(index: .extended, middle: .extended, ring: .folded, little: .extended) == .move,
            "An extended outer finger prevents a click")
        for fps in [15.0, 30, 60] {
            var trace = Session(fps: fps, practice: true)
            trace.hold(openPose, seconds: 0.4)
            trace.hold(twoPose, seconds: 1.3)
            check(trace.leftClicks == 1, "Open-hand aim followed by two fingers completes a click")
            trace.hold(twoPose, seconds: 1.3)
            check(trace.leftClicks == 1, "Holding two fingers cannot repeat a click")
            trace.hold(openPose, seconds: 0.4)
            trace.hold(twoPose, seconds: 1.3)
            check(trace.leftClicks == 2, "Opening the hand rearms the next two-finger click")
        }
        for practice in [false, true] {
            var visible = Session(fps: 30, practice: practice)
            let start = visible.cursor
            let first = visible.frame(nil)
            check(first.blocked == nil && visible.cursor == start,
                "A visible hand acquires immediately without a pointing pose or cursor jump")
            visible.hold(nil, seconds: 0.4, point: CGPoint(x: 0.6, y: 0.5))
            check(visible.cursor != start && visible.leftClicks == 0 && visible.rightClicks == 0,
                "An open or unclassified hand moves without clicking")
            visible.frame(nil, point: nil)
            let beforeReturn = visible.cursor
            check(visible.frame(nil).blocked == nil && visible.cursor == beforeReturn,
                "Returning visible hand reanchors immediately without jumping")
            visible.hold(.click, seconds: 1.2)
            check(visible.leftClicks == 0, "Acquisition alone cannot arm a click")
        }
        let tightThree = [CGPoint(x: 0.49, y: 0.40), CGPoint(x: 0.51, y: 0.40), CGPoint(x: 0.50, y: 0.42)]
        let middleApart = [CGPoint(x: 0.49, y: 0.40), CGPoint(x: 0.51, y: 0.40), CGPoint(x: 0.70, y: 0.20)]
        func threeRatio(_ tips: [CGPoint], aspect: Double = 1) -> Double? {
            ThreeFingerPinchGeometry.ratio(tips: tips,
                indexBase: CGPoint(x: 0.4, y: 0.6), littleBase: CGPoint(x: 0.6, y: 0.6),
                wrist: CGPoint(x: 0.5, y: 0.85), middleBase: CGPoint(x: 0.5, y: 0.58), aspect: aspect)
        }
        let closedThree = threeRatio(tightThree)
        let openMiddle = threeRatio(middleApart)
        check(closedThree != nil && closedThree! < 0.34,
            "Three gathered fingertips provide a scroll pinch below all sensitivity presets")
        check(openMiddle != nil && openMiddle! > 0.68,
            "Thumb and index together with middle apart cannot satisfy the scroll pinch")
        check(threeRatio(Array(tightThree.prefix(2))) == nil && threeRatio(tightThree + [aim]) == nil,
            "Three-finger geometry requires exactly three observed fingertips")
        check(threeRatio([tightThree[0], tightThree[1], CGPoint(x: .nan, y: 0.4)]) == nil &&
            threeRatio([tightThree[0], tightThree[1], CGPoint(x: 0.5, y: 1.1)]) == nil,
            "Malformed or out-of-frame fingertip locations cannot scroll")
        for aspect in [0.0, -1.0, Double.nan, Double.infinity] {
            check(threeRatio(tightThree, aspect: aspect) == nil,
                "Invalid camera aspect ratios cannot supply a scroll pinch")
        }

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
                check(session.engine.acquisition.active && session.cursor == initial && session.leftClicks == 0,
                    "A click pose can acquire movement without arming or emitting a click")
                session.hold(.move, seconds: 0.15)
                check(session.engine.acquisition.active && session.cursor == initial,
                    "Movement does not require a stable index-only acquisition interval")
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
                // Thumb, index, and middle can meet before the last two fingertips arrive.
                // This short transitional pinch is not yet a completed scroll gesture.
                stagedRight.hold(nil, seconds: 0.2, right: 1.2, scrollPinch: 0.2)
                stagedRight.hold(nil, seconds: 0.45, right: 0.4, scrollPinch: 0.2)
                check(stagedRight.rightClicks == 1 && stagedRight.leftClicks == 0 && stagedRight.scroll == 0 &&
                    stagedRight.cursor == stagedTarget,
                    "Closing three fingertips first cannot discard the armed five-finger right click")

                var threeScroll = Session(fps: fps, practice: practice)
                threeScroll.hold()
                threeScroll.hold(nil, seconds: 0.4, scrollPinch: nil, legacyPinch: 0.2)
                threeScroll.frame(nil, point: CGPoint(x: 0.5, y: 0.48), scrollPinch: nil, legacyPinch: 0.2)
                check(threeScroll.engine.scroll.phase == .idle && threeScroll.scroll == 0,
                    "Legacy thumb/index pinch alone cannot scroll when middle-finger evidence is absent")
                threeScroll.hold(nil, seconds: 0.4, scrollPinch: 0.9, legacyPinch: 0.2)
                threeScroll.frame(nil, point: CGPoint(x: 0.5, y: 0.48), scrollPinch: 0.9, legacyPinch: 0.2)
                check(threeScroll.engine.scroll.phase == .idle && threeScroll.scroll == 0,
                    "Legacy thumb/index pinch cannot scroll while the middle finger remains apart")
                let scrollTarget = threeScroll.cursor
                threeScroll.hold(nil, seconds: 0.4, scrollPinch: 0.2, legacyPinch: 0.2)
                check(threeScroll.engine.scroll.phase == .scrolling && threeScroll.scroll == 0,
                    "A steady three-finger pinch arms scrolling without an initial delta")
                threeScroll.frame(nil, point: CGPoint(x: 0.5, y: 0.48), scrollPinch: 0.2, legacyPinch: 0.2)
                check(threeScroll.scroll > 0 && threeScroll.cursor == scrollTarget &&
                    threeScroll.leftClicks == 0 && threeScroll.rightClicks == 0,
                    "Three-finger movement scrolls while keeping the cursor and mouse buttons still")
                let beforeThirdRelease = threeScroll.scroll
                threeScroll.frame(nil, point: CGPoint(x: 0.5, y: 0.46), scrollPinch: 0.9, legacyPinch: 0.2)
                check(threeScroll.engine.scroll.phase == .idle && threeScroll.scroll == beforeThirdRelease &&
                    threeScroll.cursor == scrollTarget,
                    "Releasing only the middle finger stops scroll immediately without a pointer jump")
                threeScroll.hold(nil, seconds: 0.4, scrollPinch: 0.2, legacyPinch: 0.2)
                threeScroll.frame(nil, point: CGPoint(x: 0.5, y: 0.48), scrollPinch: 0.2, legacyPinch: 0.2)
                let beforeMissingThird = threeScroll.scroll
                threeScroll.frame(nil, point: CGPoint(x: 0.5, y: 0.46), scrollPinch: nil, legacyPinch: 0.2)
                check(threeScroll.engine.scroll.phase == .idle && threeScroll.scroll == beforeMissingThird,
                    "Missing third-finger evidence stops an active scroll despite a continuing thumb/index pinch")
                threeScroll.frame(.move, point: CGPoint(x: 0.5, y: 0.46), scrollPinch: 0.9, legacyPinch: 0.9)
                check(threeScroll.cursor == scrollTarget, "Returning to index-only movement reanchors after scrolling")

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
