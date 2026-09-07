import AppKit

@main
enum GestureDemoTimelineTests {
    private static var checks = 0

    static func main() {
        clickActivatesOnLift()
        scrollPairsDownwardMotionWithAdvancingContent()
        selectionTracksPrimaryMotion()
        timelineLoopsDeterministically()
        print("Passed \(checks) gesture demo timeline checks.")
    }

    private static func clickActivatesOnLift() {
        let raised = GestureDemoTimeline.sample(action: .click, seconds: 1.40)
        let bent = GestureDemoTimeline.sample(action: .click, seconds: 1.72)
        let lifted = GestureDemoTimeline.sample(action: .click, seconds: GestureDemoTimeline.clickLiftTime)

        check(raised.primaryPose == .raised && !raised.gestureHeld && !raised.resultActivated,
              "Click starts raised and inactive")
        check(bent.primaryPose == .bent && bent.gestureHeld && !bent.resultActivated,
              "Bending both fingers does not activate the result")
        check(lifted.primaryPose == .raised && !lifted.gestureHeld && lifted.resultActivated,
              "Lifting both fingers activates the button")
        check(GestureDemoTimeline.clickLiftTime - GestureDemoTimeline.clickBendStart <= 0.65,
              "The teaching bend stays within the production release window")
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
