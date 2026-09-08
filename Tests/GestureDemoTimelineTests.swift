import AppKit

@main
enum GestureDemoTimelineTests {
    private static var checks = 0

    static func main() {
        clickActivatesAfterHold()
        scrollPairsDownwardMotionWithAdvancingContent()
        selectionTracksPrimaryMotion()
        timelineLoopsDeterministically()
        print("Passed \(checks) gesture demo timeline checks.")
    }

    private static func clickActivatesAfterHold() {
        let aim = GestureDemoTimeline.sample(action: .click, seconds: 1.40)
        let held = GestureDemoTimeline.sample(action: .click, seconds: 2.0)
        let clicked = GestureDemoTimeline.sample(action: .click, seconds: GestureDemoTimeline.clickTime)
        check(aim.primaryPose == .point && !aim.resultActivated, "Aim uses index only")
        check(held.primaryPose == .raised && held.gestureHeld && !held.resultActivated && held.resultProgress == 0.5,
              "Two raised fingers count down before activation")
        check(clicked.resultActivated && clicked.primaryPose == .raised, "Click occurs at hold completion")
        check(GestureDemoTimeline.clickTime - GestureDemoTimeline.clickHoldStart == 1, "Tutorial hold lasts one second")
        let right = GestureDemoTimeline.sample(action: .rightClick, seconds: 2)
        check(right.primaryPose == .allPinch && right.resultActivated, "Right click shows five-tip closure")
        check(GestureDemoTimeline.sample(action: .scroll, seconds: 2).primaryPose == .threePinch,
              "Scroll shows three-tip closure")
    }

    private static func scrollPairsDownwardMotionWithAdvancingContent() {
        let start = GestureDemoTimeline.sample(action: .scroll, seconds: 1.20)
        let moved = GestureDemoTimeline.sample(action: .scroll, seconds: 3.20)
        let released = GestureDemoTimeline.sample(action: .scroll, seconds: 3.80)

        check(start.gestureHeld && moved.gestureHeld, "Scroll remains pinched during motion")
        check(moved.primaryY > start.primaryY && moved.resultProgress > start.resultProgress,
              "Moving the hand down advances the list")
        check(!released.gestureHeld && released.resultProgress == moved.resultProgress,
              "Opening the pinch stops list movement")
    }

    private static func selectionTracksPrimaryMotion() {
        let acquired = GestureDemoTimeline.sample(action: .select, seconds: 1.80)
        let dragged = GestureDemoTimeline.sample(action: .select, seconds: 3.20)
        let released = GestureDemoTimeline.sample(action: .select, seconds: 3.90)

        check(acquired.secondaryPose == .lShape && dragged.secondaryPose == .lShape,
              "Selection keeps the companion L hand present while dragging")
        check(dragged.primaryX > acquired.primaryX && dragged.resultProgress > acquired.resultProgress,
              "Primary-hand travel grows the sentence highlight")
        check(released.primaryPose == .open && released.secondaryPose == .open && !released.gestureHeld,
              "Opening either side presents a released selection")
    }

    private static func timelineLoopsDeterministically() {
        let first = GestureDemoTimeline.sample(action: .move, seconds: 2.25)
        let nextLoop = GestureDemoTimeline.sample(action: .move, seconds: 7.25)
        check(first.primaryX == nextLoop.primaryX && first.resultProgress == nextLoop.resultProgress,
              "A sampled frame repeats exactly after one loop")
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !condition() {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}
