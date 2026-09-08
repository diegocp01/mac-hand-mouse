import Foundation
import CoreGraphics

@main struct PracticeTaskTests {
    static var checks = 0

    static func check(_ condition: Bool, _ message: String) {
        checks += 1
        if !condition { fatalError(message) }
    }

    static func neutral(_ state: inout PracticeTaskState, point: CGPoint? = CGPoint(x: 0.5, y: 0.5)) {
        check(!state.update(point: point, clicked: false, scrollY: 0, dragging: false),
              "neutral input does not complete a task")
    }

    static func clickChecks() {
        var state = PracticeTaskState(task: .click)
        let target = CGPoint(x: PracticeTaskState.clickTarget.midX,
                             y: PracticeTaskState.clickTarget.midY)
        let outside = CGPoint(x: 0.1, y: 0.9)

        check(!state.update(point: target, clicked: true, scrollY: 0, dragging: false),
              "a held click present at startup cannot complete practice")
        neutral(&state)
        check(!state.update(point: outside, clicked: true, scrollY: 0, dragging: false),
              "a click outside the target does not complete practice")
        check(!state.update(point: target, clicked: true, scrollY: 0, dragging: false),
              "moving a held click onto the target is not a new click")
        neutral(&state)
        check(state.update(point: target, clicked: true, scrollY: 0, dragging: false),
              "a fresh click inside the target completes practice")
        check(state.completed, "click completion persists")
        check(!state.update(point: target, clicked: true, scrollY: 0, dragging: false),
              "held click frames do not report repeat completion")

        for invalid in [
            CGPoint(x: .nan, y: 0.4), CGPoint(x: .infinity, y: 0.4),
            CGPoint(x: -0.01, y: 0.4), CGPoint(x: 1.01, y: 0.4)
        ] {
            state.reset(task: .click)
            neutral(&state)
            check(!state.update(point: invalid, clicked: true, scrollY: 0, dragging: false),
                  "invalid normalized points cannot click the target")
            check(!state.completed, "invalid click input leaves the task incomplete")
        }

        state.reset(task: .click)
        check(!state.completed && state.scrollOffset == 0 && state.selectionStart == nil,
              "reset clears completion and transient state")
        check(!state.update(point: target, clicked: true, scrollY: 0, dragging: false),
              "reset does not inherit the preceding held click")
        neutral(&state)
        check(!state.update(point: target, clicked: true, scrollY: 0, dragging: false,
                            interrupted: true),
              "blocked click data cannot complete practice")
        check(!state.update(point: target, clicked: true, scrollY: 0, dragging: false),
              "a held click after interruption cannot complete practice")
        neutral(&state)
        check(state.update(point: target, clicked: true, scrollY: 0, dragging: false),
              "a fresh click after interruption can complete practice")

        state.reset(task: .click)
        neutral(&state)
        check(!state.update(point: target, clicked: true, scrollY: -20, dragging: false),
              "simultaneous scroll output cannot count as a practice click")
        check(!state.update(point: target, clicked: true, scrollY: 0, dragging: false),
              "removing scroll output while click stays held is not a fresh click")
        neutral(&state)
        check(!state.update(point: target, clicked: true, scrollY: 0, dragging: true),
              "simultaneous drag output cannot count as a practice click")
    }

    static func scrollChecks() {
        var state = PracticeTaskState(task: .scroll)
        check(!state.update(point: nil, clicked: false, scrollY: 400, dragging: false),
              "a carried scroll delta cannot complete a fresh task")
        check(state.scrollOffset == 0, "carried scroll input does not change the list")
        neutral(&state)

        check(!state.update(point: nil, clicked: true, scrollY: 0, dragging: true),
              "click and drag gestures do not complete scrolling")
        check(state.scrollOffset == 0, "wrong gestures do not move the list")
        check(!state.update(point: nil, clicked: false, scrollY: 200, dragging: false),
              "scrolling in the wrong direction does not complete the task")
        check(state.scrollOffset == 0, "positive scrolling is bounded at the start")
        check(!state.update(point: nil, clicked: false, scrollY: -100, dragging: false),
              "partial correct scrolling does not claim success")
        check(state.scrollOffset > 0 && state.scrollOffset < PracticeTaskState.maxScrollOffset,
              "correct scrolling advances within its normalized bounds")
        check(!state.update(point: nil, clicked: false, scrollY: 25, dragging: false),
              "reversing direction removes progress without success")
        check(state.update(point: nil, clicked: false, scrollY: -200, dragging: false),
              "enough accumulated correct scrolling reveals the target row")
        check(state.completed, "scroll completion persists")
        check(PracticeTaskState.listViewport.contains(state.visibleListTargetRow.origin),
              "the completed row begins inside the viewport")
        check(state.visibleListTargetRow.maxY <= PracticeTaskState.listViewport.maxY,
              "the completed row is fully visible")

        let completedOffset = state.scrollOffset
        check(!state.update(point: nil, clicked: false, scrollY: Int32.max, dragging: false),
              "completed scrolling does not report success again")
        check(state.scrollOffset == completedOffset, "completed state remains stable")

        state.reset(task: .scroll)
        neutral(&state)
        check(!state.update(point: nil, clicked: false, scrollY: Int32.max, dragging: false),
              "extreme reverse input remains bounded")
        check(state.scrollOffset == 0, "extreme reverse input cannot underflow")
        check(state.update(point: nil, clicked: false, scrollY: Int32.min, dragging: false),
              "extreme forward input clamps and reveals the row")
        check(state.scrollOffset == PracticeTaskState.maxScrollOffset,
              "extreme forward input cannot overflow the list")

        state.reset(task: .scroll)
        neutral(&state)
        check(!state.update(point: nil, clicked: false, scrollY: -100, dragging: false),
              "scroll progress may begin before an interruption")
        let partialOffset = state.scrollOffset
        check(!state.update(point: nil, clicked: false, scrollY: -500, dragging: false,
                            interrupted: true),
              "blocked scroll data cannot complete practice")
        check(state.scrollOffset == partialOffset && !state.completed,
              "an interruption preserves earned progress but ignores its delta")
        check(!state.update(point: nil, clicked: false, scrollY: -500, dragging: false),
              "continued scroll output after interruption waits for neutral")
        neutral(&state)
        check(state.update(point: nil, clicked: false, scrollY: -200, dragging: false),
              "fresh scrolling after interruption can complete practice")

        state.reset(task: .scroll)
        neutral(&state)
        check(!state.update(point: nil, clicked: true, scrollY: -500, dragging: false),
              "simultaneous click output cannot count as practice scrolling")
        check(!state.update(point: nil, clicked: false, scrollY: -500, dragging: true),
              "simultaneous drag output cannot count as practice scrolling")
        check(!state.completed && state.scrollOffset == 0,
              "wrong gestures do not contribute scroll progress")
    }

    static func selectionChecks() {
        var state = PracticeTaskState(task: .select)
        let target = PracticeTaskState.sentenceTarget
        let left = CGPoint(x: target.minX + 0.02, y: target.midY)
        let middle = CGPoint(x: target.midX, y: target.midY)
        let right = CGPoint(x: target.maxX - 0.02, y: target.midY)
        let outside = CGPoint(x: 0.03, y: 0.03)

        check(!state.update(point: left, clicked: false, scrollY: 0, dragging: true),
              "a carried drag cannot start selection")
        neutral(&state)
        check(!state.update(point: outside, clicked: false, scrollY: 0, dragging: true),
              "a drag beginning outside the sentence cannot select it")
        check(!state.update(point: right, clicked: false, scrollY: 0, dragging: true),
              "an outside drag cannot become valid by crossing the sentence")
        check(!state.update(point: right, clicked: false, scrollY: 0, dragging: false),
              "releasing an invalid drag does not complete selection")

        check(!state.update(point: middle, clicked: false, scrollY: 0, dragging: true),
              "selection can begin inside the sentence")
        check(!state.update(point: right, clicked: false, scrollY: 0, dragging: true),
              "partial selection stays in progress")
        check(!state.update(point: right, clicked: false, scrollY: 0, dragging: false),
              "a drag that misses one edge does not select the whole sentence")
        check(state.selectionStart == nil && state.selectionEnd == nil,
              "a failed released selection clears its highlight")

        check(!state.update(point: left, clicked: false, scrollY: 0, dragging: true),
              "a fresh on-target drag begins")
        check(!state.update(point: right, clicked: false, scrollY: 0, dragging: true),
              "crossing both sentence edges waits for release")
        check(!state.completed, "selection never completes while the drag remains held")
        check(state.update(point: right, clicked: false, scrollY: 0, dragging: false),
              "releasing a full sentence selection completes the task")
        check(state.completed && state.selectionStart == left && state.selectionEnd == right,
              "successful selection remains visible")
        check(!state.update(point: nil, clicked: false, scrollY: 0, dragging: false,
                            interrupted: true),
              "interruption does not report a second selection completion")
        check(state.completed && state.selectionStart == left && state.selectionEnd == right,
              "successful selection remains visible after later tracking loss")
        check(!state.update(point: right, clicked: false, scrollY: 0, dragging: false),
              "selection completion is reported once")

        state.reset(task: .select)
        neutral(&state)
        _ = state.update(point: left, clicked: false, scrollY: 0, dragging: true)
        _ = state.update(point: right, clicked: false, scrollY: 0, dragging: true)
        check(!state.update(point: nil, clicked: false, scrollY: 0, dragging: false),
              "a release without a tracked point cannot complete selection")
        check(!state.completed && state.selectionStart == nil && state.selectionEnd == nil,
              "a missing release point cancels the partial selection")
        check(!state.update(point: right, clicked: false, scrollY: 0, dragging: true),
              "drag output cannot resume after a missing release point")
        neutral(&state)

        state.reset(task: .select)
        neutral(&state)
        check(!state.update(point: right, clicked: false, scrollY: 0, dragging: true),
              "reverse selection may start at the sentence end")
        check(!state.update(point: left, clicked: false, scrollY: 0, dragging: true),
              "reverse selection may cross the sentence")
        check(state.update(point: left, clicked: false, scrollY: 0, dragging: false),
              "reverse full selection completes on release")

        state.reset(task: .select)
        neutral(&state)
        _ = state.update(point: left, clicked: false, scrollY: 0, dragging: true)
        _ = state.update(point: right, clicked: false, scrollY: 0, dragging: true)
        check(!state.update(point: nil, clicked: false, scrollY: 0, dragging: false, interrupted: true),
              "tracking interruption never completes a selection")
        check(!state.completed && state.selectionStart == nil && state.selectionEnd == nil,
              "interruption cancels the partial selection")
        check(!state.update(point: right, clicked: false, scrollY: 0, dragging: true),
              "a held drag reappearing after interruption cannot resume")
        check(!state.update(point: right, clicked: false, scrollY: 0, dragging: false),
              "the post-interruption release only rearms selection")
        check(!state.update(point: left, clicked: false, scrollY: 0, dragging: true),
              "a fresh drag is required after interruption")
        _ = state.update(point: right, clicked: false, scrollY: 0, dragging: true)
        check(state.update(point: right, clicked: false, scrollY: 0, dragging: false),
              "fresh selection after interruption can complete")

        state.reset(task: .select)
        neutral(&state)
        _ = state.update(point: left, clicked: false, scrollY: 0, dragging: true)
        check(!state.update(point: CGPoint(x: .nan, y: target.midY), clicked: false,
                            scrollY: 0, dragging: true),
              "invalid coordinates cancel an active selection")
        check(state.selectionStart == nil && state.selectionEnd == nil,
              "invalid coordinates clear selection state")

        state.reset(task: .select)
        neutral(&state)
        _ = state.update(point: left, clicked: false, scrollY: 0, dragging: true)
        check(!state.update(point: right, clicked: true, scrollY: 0, dragging: true),
              "click output cancels an in-progress practice selection")
        check(state.selectionStart == nil && state.selectionEnd == nil,
              "wrong gesture input cannot leave a qualifying selection")
    }

    static func taskSwitchChecks() {
        var state = PracticeTaskState(task: .click)
        neutral(&state)
        let click = CGPoint(x: PracticeTaskState.clickTarget.midX,
                            y: PracticeTaskState.clickTarget.midY)
        check(state.update(point: click, clicked: true, scrollY: 0, dragging: false),
              "click completes before switching tasks")

        state.reset(task: .scroll)
        check(state.task == .scroll && !state.completed && state.scrollOffset == 0,
              "explicit next resets state for scrolling")
        check(!state.update(point: nil, clicked: true, scrollY: 300, dragging: true),
              "combined held outputs cannot carry into the next task")
        check(state.scrollOffset == 0, "task switching clears carried motion")

        state.reset(task: .select)
        check(state.task == .select && !state.completed && state.selectionStart == nil,
              "explicit retry resets all selection state")
    }

    struct PracticePipeline {
        var engine = InteractionEngine()
        var state: PracticeTaskState
        var cursor: CGPoint
        var time = 0.0
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 1000)

        init(task: PracticeTask, settings: InteractionSettings, cursor: CGPoint) {
            state = PracticeTaskState(task: task)
            self.cursor = cursor
            engine.configure(settings)
        }

        @discardableResult
        mutating func frame(tapPose: TapPose? = .raised, scrollRatio: Double? = 0.9,
                            palm: CGPoint? = nil) -> Bool {
            time += 1.0 / 30
            let step = engine.process(index: CGPoint(x: 0.5, y: 0.5), pinchRatio: nil,
                timestamp: time, now: time + 0.01, bounds: bounds,
                running: true, trusted: false, destination: .practice,
                cursorPosition: cursor, handSide: "left", palm: palm,
                tapPose: tapPose, fingerSeparationRatio: 0.6,
                scrollPinchRatio: scrollRatio)
            check(step.systemLocation == nil && !step.systemClick && step.systemScrollY == 0
                    && !step.systemDragging && !step.systemButtonHeld,
                  "an actual practice pipeline frame exposes no system input")
            if let location = step.location { cursor = location }
            let point = step.location.map {
                CGPoint(x: ($0.x - bounds.minX) / bounds.width,
                        y: ($0.y - bounds.minY) / bounds.height)
            }
            return state.update(point: point, clicked: step.click, scrollY: step.scrollY,
                                dragging: step.dragging,
                                interrupted: step.blocked != nil || point == nil)
        }
    }

    static func productionPipelineChecks() {
        let clickTarget = PracticeTaskState.clickTarget
        var click = PracticePipeline(task: .click,
            settings: InteractionSettings(mode: .twoFingerTap, allowClicks: true),
            cursor: CGPoint(x: clickTarget.midX * 1000, y: clickTarget.midY * 1000))
        for _ in 0..<30 { _ = click.frame() }
        _ = click.frame(tapPose: .transition)
        for _ in 0..<3 { _ = click.frame(tapPose: .bent) }
        let clicked = click.frame(tapPose: .raised)
        check(clicked && click.state.completed,
              "an actual isolated two-finger tap completes the button task")

        var scroll = PracticePipeline(task: .scroll,
            settings: InteractionSettings(mode: .twoFingerTap, allowClicks: true,
                                          allowScrolling: true),
            cursor: CGPoint(x: 500, y: 500))
        for _ in 0..<30 { _ = scroll.frame() }
        let scrollStart = CGPoint(x: 0.5, y: 0.5)
        for _ in 0..<10 { _ = scroll.frame(scrollRatio: 0.1, palm: scrollStart) }
        var revealed = false
        for index in 1...15 {
            let palm = CGPoint(x: 0.5, y: 0.5 + Double(index) * 0.02)
            revealed = scroll.frame(scrollRatio: 0.1, palm: palm) || revealed
        }
        check(scroll.engine.scroll.phase == .scrolling,
              "the real scroll detector produced the practice stream")
        check(revealed && scroll.state.completed,
              "actual isolated scroll output reveals the target list row")
    }

    static func main() {
        check(PracticeTask.allCases == [.click, .scroll, .select],
              "practice tasks retain their intended sequence")
        clickChecks()
        scrollChecks()
        selectionChecks()
        taskSwitchChecks()
        productionPipelineChecks()
        print("Practice task checks passed: \(checks)")
    }
}
