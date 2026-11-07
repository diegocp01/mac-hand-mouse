import Foundation
import CoreGraphics

/// Right-click and scroll gestures, their priority over hold-still clicking,
/// fingertip geometry, and the production output gates around them.
@main struct ClickGestureTests {
    static var checks = 0
    static let aim = CGPoint(x: 0.5, y: 0.5)
    static let bounds = CGRect(x: -1440, y: -100, width: 1440, height: 900)

    static func check(_ condition: Bool, _ message: String) {
        checks += 1
        if !condition { fatalError(message) }
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
            engine.configure(InteractionSettings(allowClicks: allowClicks, allowScrolling: allowScrolling))
        }

        @discardableResult mutating func frame(point: CGPoint? = aim, right: Double? = 1.2, scrollPinch: Double? = 0.9,
                age: Double = 0.01, gap: Double? = nil, trusted: Bool = true) -> InteractionStep {
            time += gap ?? 1 / fps
            last = engine.process(HandInput(index: point, timestamp: time, handSide: "left", palm: point,
                    fiveFingerPinchRatio: right, threeFingerPinchRatio: scrollPinch),
                now: time + age, bounds: bounds, running: true, trusted: trusted && destination == .system,
                destination: destination, cursorPosition: cursor)
            if let location = last.location { cursor = location }
            if last.click { leftClicks += 1 }
            if last.rightClick { rightClicks += 1 }
            scroll += last.scrollY
            check(!(last.click && last.rightClick), "A frame cannot emit both mouse buttons")
            if destination == .practice {
                check(last.systemLocation == nil && !last.systemClick && !last.systemRightClick &&
                    last.systemScrollY == 0 && !last.systemButtonHeld,
                    "Practice cannot emit any system input")
            }
            return last
        }

        /// Half a second by default: settled, but short of a hold-still click.
        mutating func hold(seconds: Double = 0.5, point: CGPoint? = aim, right: Double? = 1.2, scrollPinch: Double? = 0.9) {
            for _ in 0..<Int((seconds * fps).rounded()) {
                frame(point: point, right: right, scrollPinch: scrollPinch)
            }
        }
    }

    static func main() {
        // Partially curled outer fingers fall between the tight-fist cutoff and
        // the extended-finger cutoff; the relaxed limit used for diagnostics accepts them.
        for aspect in [0.75, 1.0, 16.0 / 9.0] {
            for angle in [0.0, 0.6, 1.5, 3.1] {
                let base = CGPoint(x: 0.5, y: 0.5)
                func point(_ distance: Double) -> CGPoint {
                    CGPoint(x: base.x + cos(angle) * distance / aspect,
                            y: base.y + sin(angle) * distance)
                }
                func outer(_ ratio: Double) -> FingerShape {
                    FingerGeometry.shape(tip: point(0.1 * ratio), pip: point(0.1), base: base,
                        aspect: aspect, foldedReachLimit: 1.45)
                }
                check(outer(1.27) == .folded, "A partly curled outer finger is recognized without a tight fist")
                check(outer(1.4) == .folded, "Relaxed curled fingers are accepted across orientations")
                check(outer(1.52) == .uncertain, "Borderline outer fingers remain uncertain")
                check(outer(2.0) == .extended, "Raised outer fingers are recognized")
                check(FingerGeometry.shape(tip: point(0.127), pip: point(0.1), base: base,
                    aspect: aspect) == .uncertain, "The default geometry keeps its strict fold threshold")
            }
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
        check(closedThree != nil && closedThree! < InteractionEngine.scrollPinchClose,
            "Three gathered fingertips provide a scroll pinch below the threshold")
        check(openMiddle != nil && openMiddle! > InteractionEngine.scrollPinchOpen,
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
                var visible = Session(fps: fps, practice: practice)
                let start = visible.cursor
                let first = visible.frame()
                check(first.blocked == nil && visible.cursor == start,
                    "A visible hand acquires immediately without a special pose or cursor jump")
                visible.hold(seconds: 0.4, point: CGPoint(x: 0.6, y: 0.5))
                check(visible.cursor != start && visible.leftClicks == 0 && visible.rightClicks == 0,
                    "An open hand moves without clicking")
                visible.frame(point: nil)
                let beforeReturn = visible.cursor
                check(visible.frame().blocked == nil && visible.cursor == beforeReturn,
                    "Returning visible hand reanchors immediately without jumping")

                var session = Session(fps: fps, practice: practice)
                session.hold()
                let rightTarget = session.cursor
                session.hold(seconds: 0.45, right: 0.4, scrollPinch: 0.2)
                check(session.rightClicks == 1 && session.leftClicks == 0 && session.scroll == 0 &&
                    session.cursor == rightTarget, "Five-finger pinch wins over scrolling and emits only one right click")
                session.hold(seconds: 1, point: CGPoint(x: 0.5, y: 0.45), right: 0.4, scrollPinch: 0.2)
                check(session.rightClicks == 1 && session.leftClicks == 0 && session.scroll == 0 && session.cursor == rightTarget,
                    "Moving a held right pinch cannot leak into scroll, left click, or pointer travel")
                session.frame(point: CGPoint(x: 0.5, y: 0.45))
                check(session.cursor == rightTarget, "Opening the hand after a right click reanchors without a jump")

                var priority = Session(fps: fps, practice: practice)
                priority.hold(seconds: 0.7)
                check(priority.engine.clickPhase == .holding, "A rest in progress is counting down")
                priority.hold(seconds: 0.45, right: 0.4, scrollPinch: 0.2)
                check(priority.rightClicks == 1 && priority.leftClicks == 0 && priority.scroll == 0,
                    "Right pinch cancels a pending left countdown")
                priority.hold(seconds: 0.5)
                check(priority.leftClicks == 0, "The canceled countdown does not resume after reopening")
                priority.hold(seconds: 0.7)
                check(priority.leftClicks == 1, "A fresh full rest after a right click can left click")

                var stagedRight = Session(fps: fps, practice: practice)
                stagedRight.hold()
                let stagedTarget = stagedRight.cursor
                // Thumb, index, and middle can meet before the last two fingertips arrive.
                // This short transitional pinch is not yet a completed scroll gesture.
                stagedRight.hold(seconds: 0.2, right: 1.2, scrollPinch: 0.2)
                stagedRight.hold(seconds: 0.45, right: 0.4, scrollPinch: 0.2)
                check(stagedRight.rightClicks == 1 && stagedRight.leftClicks == 0 && stagedRight.scroll == 0 &&
                    stagedRight.cursor == stagedTarget,
                    "Closing three fingertips first cannot discard the armed five-finger right click")

                var threeScroll = Session(fps: fps, practice: practice)
                threeScroll.hold()
                let scrollTarget = threeScroll.cursor
                threeScroll.hold(seconds: 0.4, scrollPinch: 0.2)
                check(threeScroll.engine.scroll.phase == .scrolling && threeScroll.scroll == 0,
                    "A steady three-finger pinch arms scrolling without an initial delta")
                threeScroll.frame(point: CGPoint(x: 0.5, y: 0.48), scrollPinch: 0.2)
                check(threeScroll.scroll > 0 && threeScroll.cursor == scrollTarget &&
                    threeScroll.leftClicks == 0 && threeScroll.rightClicks == 0,
                    "Three-finger movement scrolls while keeping the cursor and mouse buttons still")
                let beforeRelease = threeScroll.scroll
                threeScroll.frame(point: CGPoint(x: 0.5, y: 0.46), scrollPinch: 0.9)
                check(threeScroll.engine.scroll.phase == .idle && threeScroll.scroll == beforeRelease &&
                    threeScroll.cursor == scrollTarget,
                    "Releasing the pinch stops scroll immediately without a pointer jump")
                threeScroll.hold(seconds: 0.4, scrollPinch: 0.2)
                threeScroll.frame(point: CGPoint(x: 0.5, y: 0.48), scrollPinch: 0.2)
                let beforeMissing = threeScroll.scroll
                threeScroll.frame(point: CGPoint(x: 0.5, y: 0.46), scrollPinch: nil)
                check(threeScroll.engine.scroll.phase == .idle && threeScroll.scroll == beforeMissing,
                    "Missing fingertip evidence stops an active scroll")
                threeScroll.frame(point: CGPoint(x: 0.5, y: 0.46))
                check(threeScroll.cursor == scrollTarget, "Returning to aiming reanchors after scrolling")

                var stale = Session(fps: fps, practice: practice)
                stale.hold(seconds: 0.7)
                let rejected = stale.frame(age: 0.3)
                check(rejected.blocked == .staleFrame && !rejected.click && !rejected.rightClick,
                    "Stale frames never produce either button")
                stale.hold(seconds: 0.5)
                check(stale.leftClicks == 0 && stale.rightClicks == 0, "A stale countdown restarts from zero")
                stale.hold(seconds: 0.7)
                check(stale.leftClicks == 1, "A fresh rest after a stale frame clicks once")
                stale.frame(point: nil); stale.frame(right: 0.4)
                stale.frame(right: 0.4, age: 0.3)
                stale.hold(seconds: 0.4, right: 0.4)
                check(stale.rightClicks == 0, "A stale pinch cannot finish a right click")

                var disabled = Session(fps: fps, practice: practice, allowClicks: false, allowScrolling: false)
                disabled.hold(seconds: 1.3)
                disabled.hold(seconds: 0.4, right: 0.4, scrollPinch: 0.2)
                check(disabled.leftClicks == 0 && disabled.rightClicks == 0 && disabled.scroll == 0 &&
                    !disabled.last.systemButtonHeld, "Disabling clicks suppresses both gesture buttons")

                if !practice {
                    var denied = Session(fps: fps, practice: false)
                    denied.hold(seconds: 0.7)
                    let blocked = denied.frame(trusted: false)
                    check(blocked.blocked == .permission && blocked.systemLocation == nil &&
                        !blocked.systemClick && !blocked.systemRightClick,
                        "Permission loss cancels a pending hold before system input")
                    denied.hold(seconds: 0.5)
                    check(denied.leftClicks == 0, "Restored permission restarts the hold from zero")
                    denied.hold(seconds: 0.7)
                    check(denied.leftClicks == 1, "A fresh rest after restoration clicks once")
                }
            }
        }
        print("Passed \(checks) click gesture checks")
    }
}
