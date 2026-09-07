import Foundation
import CoreGraphics

@main struct OneHandDragTests {
    static var checks = 0
    static func check(_ value: Bool, _ message: String) {
        checks += 1
        if !value { fatalError(message) }
    }
    struct Session {
        var engine = InteractionEngine()
        var output = DragOutput()
        var events: [DragEvent] = []
        var fps = 30.0
        var time = 0.0
        var cursor = CGPoint(x: -600, y: 400)
        var bounds = CGRect(x: -1440, y: -100, width: 1440, height: 900)
        var point: CGPoint? = CGPoint(x: 0.4, y: 0.4)
        var palm: CGPoint? = CGPoint(x: 0.4, y: 0.55)
        var ratio: Double? = 0.9
        var side = "left"
        var destination: InteractionDestination = .system
        var trusted = true
        var running = true
        var scrollPoint: CGPoint?
        var last = InteractionStep()
        var atomicClicks = 0
        mutating func setup(enabled: Bool = true, scrolling: Bool = true) {
            engine.configure(InteractionSettings(allowScrolling: scrolling, allowPinchDragging: enabled))
            hold(1)
        }
        @discardableResult mutating func frame(dt: Double? = nil, age: Double = 0.01) -> InteractionStep {
            time += dt ?? (1 / fps)
            last = engine.process(index: point, pinchRatio: ratio, timestamp: time, now: time + age,
                bounds: bounds, running: running, trusted: trusted, destination: destination,
                cursorPosition: cursor, handSide: side, scrollPoint: scrollPoint, palm: palm)
            events += output.update(last)
            if last.systemClick { atomicClicks += 1 }
            if let location = last.location { cursor = location }
            return last
        }
        mutating func hold(_ seconds: Double) {
            for _ in 0..<Int(ceil(seconds * fps)) { frame() }
        }
        mutating func press() {
            ratio = 0.2
            point = CGPoint(x: 0.44, y: 0.45)
            hold(0.4)
        }
        mutating func move() {
            for i in 1...15 {
                palm = CGPoint(x: 0.4 + Double(i) * 0.004, y: 0.55)
                // Finger curl is intentionally unrelated to whole-hand movement.
                point = CGPoint(x: 0.44, y: 0.45 + Double(i % 2) * 0.002)
                frame()
            }
        }
        var downs: Int { events.filter { $0.kind == .down }.count }
        var ups: Int { events.filter { $0.kind == .up }.count }
        var moves: Int { events.filter { $0.kind == .moved }.count }
    }
    static func main() {
        let p = CGPoint(x: 0.4, y: 0.5)
        check(PinchDragPalm.measure(points: [p, p, p, p], confidences: [0.6, 1, 0.8, 0.9]) == p, "Confident palm center")
        check(PinchDragPalm.measure(points: [p, nil, p, p], confidences: [1, 1, 1, 1]) == nil, "Missing joint rejected")
        check(PinchDragPalm.measure(points: [p, p, p, p], confidences: [1, 0.59, 1, 1]) == nil, "Weak palm rejected")
        check(PinchDragPalm.measure(points: [p, p, p, p], confidences: [1, .nan, 1, 1]) == nil, "Nonfinite confidence rejected")
        check(PinchDragPalm.measure(points: [p, p, p, CGPoint(x: 2, y: 0)], confidences: [1, 1, 1, 1]) == nil, "Out-of-frame palm rejected")
        check(!InteractionSettings().allowPinchDragging, "New behavior is opt-in")
        for fps in [15.0, 30.0, 60.0] {
            for side in ["left", "right"] {
                var s = Session(); s.fps = fps; s.side = side; s.setup()
                let target = s.cursor
                s.press()
                check(s.downs == 1 && s.ups == 0 && s.moves == 0, "Confirmed pinch presses once without dragging")
                check(s.cursor == target && s.events.first?.location == target, "Closure preserves the aimed target")
                s.hold(0.5)
                check(s.downs == 1 && s.moves == 0, "Stationary hold never emits dragged events")
                for i in 0..<10 {
                    s.palm = CGPoint(x: 0.4 + Double(i % 2) * 0.001, y: 0.55); s.frame()
                }
                check(s.moves == 0 && s.cursor == target, "Subthreshold palm jitter stays pressed")
                s.ratio = 0.9; s.point = CGPoint(x: 0.5, y: 0.4); s.frame()
                check(s.ups == 1 && s.cursor == target && s.atomicClicks == 0, "Short release clicks through one matched native pair without cursor jump")
                s.hold(0.5); check(s.ups == 1, "Release is idempotent")
                s.palm = CGPoint(x: 0.4, y: 0.55); s.press(); s.move()
                check(s.downs == 2 && s.last.systemDragging && s.cursor.x > target.x, "Whole-hand motion drags after deliberate threshold")
                let end = s.cursor
                s.ratio = 0.9; s.point = CGPoint(x: 0.6, y: 0.3); s.frame()
                check(s.ups == 2 && s.events.last?.location == end && s.cursor == end && s.atomicClicks == 0, "Drag release stays at the final selection and creates no extra click")
            }
            // PR #12 anchors preserve reach from corners; palm drag must preserve it too.
            for right in [false, true] {
                for bottom in [false, true] {
                    var edge = Session(); edge.fps = fps
                    edge.cursor = CGPoint(x: right ? edge.bounds.maxX - 1 : edge.bounds.minX,
                                          y: bottom ? edge.bounds.maxY - 1 : edge.bounds.minY)
                    let startX = right ? 0.85 : 0.15, startY = bottom ? 0.85 : 0.15
                    edge.palm = CGPoint(x: startX, y: startY)
                    edge.setup(); edge.press()
                    for i in 1...70 {
                        edge.palm = CGPoint(x: startX + (right ? -1 : 1) * Double(i) * 0.01,
                                            y: startY + (bottom ? -1 : 1) * Double(i) * 0.01)
                        edge.frame()
                    }
                    edge.hold(0.5)
                    check(edge.downs == 1 && edge.last.dragging, "Off-center palm starts and maintains drag")
                    check(edge.cursor.x == (right ? edge.bounds.minX : edge.bounds.maxX - 1)
                          && edge.cursor.y == (bottom ? edge.bounds.minY : edge.bounds.maxY - 1),
                          "Palm drag reaches opposite corner with the new anchored map")
                    edge.ratio = 0.9; edge.frame()
                    check(edge.ups == 1, "Corner drag releases normally")
                }
            }
            for dragging in [false, true] {
                for interruption in 0..<16 {
                    var s = Session(); s.fps = fps; s.setup(); s.press()
                    if dragging { s.move() }
                    check(s.downs == 1, "Interruption fixture has an actual button-down")
                    switch interruption {
                    case 0: s.point = nil
                    case 1: s.palm = nil
                    case 2: s.ratio = nil
                    case 3: s.trusted = false
                    case 4: s.running = false
                    case 5: s.side = "right"
                    case 6: s.cursor.x += 60
                    case 7: s.bounds = .zero
                    case 8: s.engine.configure(InteractionSettings(allowClicks: false, allowPinchDragging: true))
                    case 9: s.engine.configure(InteractionSettings(pointerEnabled: false, allowPinchDragging: true))
                    case 10: s.destination = .practice
                    case 11: s.engine.configure(InteractionSettings(mode: .forward, allowPinchDragging: true))
                    case 12: s.palm = CGPoint(x: 0.8, y: 0.5)
                    case 13: s.bounds.origin.x -= 10
                    default: break
                    }
                    s.frame(dt: interruption == 15 ? 0.4 : nil, age: interruption == 14 ? 0.3 : 0.01)
                    check(s.ups == 1 && !s.last.systemButtonHeld, "Interruption \(interruption) releases press or drag")
                    s.frame(); check(s.ups == 1 && s.atomicClicks == 0, "Repeated cancellation cannot duplicate release or click")
                }
            }
            var loss = Session(); loss.fps = fps; loss.setup(); loss.press()
            loss.palm = nil; loss.frame(); loss.palm = CGPoint(x: 0.4, y: 0.55); loss.hold(1)
            check(loss.downs == 1 && loss.ups == 1, "Closed return after palm loss cannot silently re-press")
            loss.ratio = 0.9; loss.hold(1); loss.press()
            check(loss.downs == 2, "Visible open reacquisition rearms")
            var ordinary = Session(); ordinary.fps = fps; ordinary.setup(enabled: false); ordinary.press()
            check(ordinary.downs == 0 && ordinary.atomicClicks == 1, "Disabled mode preserves existing atomic pinch clicks")
            var scroll = Session(); scroll.fps = fps; scroll.setup(); scroll.press()
            scroll.scrollPoint = p; scroll.hold(0.5)
            check(scroll.last.scrollY == 0 && scroll.downs == 1 && scroll.ups == 0, "Scroll pose cannot steal held pinch")
            scroll.ratio = 0.9; scroll.frame(); check(scroll.ups == 1, "Opening during scroll pose releases first")
            scroll.hold(0.6); check(scroll.engine.scroll.phase == .scrolling, "Released pinch allows deliberate scrolling")
            scroll.scrollPoint = nil; scroll.hold(1); scroll.press()
            check(scroll.downs == 2, "Return from scrolling rearms an open pinch")
            var noScroll = Session(); noScroll.fps = fps; noScroll.setup(scrolling: false)
            noScroll.scrollPoint = p; noScroll.press()
            check(noScroll.downs == 1 && noScroll.atomicClicks == 0, "Disabled scrolling never falls through to atomic clicks")
            var practice = Session(); practice.fps = fps; practice.destination = .practice; practice.setup(); practice.press()
            check(practice.last.buttonHeld && practice.events.isEmpty, "Practice press never posts to system")
            practice.ratio = 0.9; practice.frame()
            check(practice.last.click && !practice.last.systemClick, "Practice target recognizes short pinch on release")
            practice.hold(0.5); practice.press(); practice.move()
            check(practice.last.dragging && practice.events.isEmpty && practice.last.systemLocation == nil, "Practice selection is isolated")
        }
        // A failed down cannot create a release obligation; failed movement retains the prior location.
        var output = DragOutput()
        let pressed = InteractionStep(location: p, buttonHeld: true)
        check(!output.dispatch(pressed, post: { _ in false }) && output.heldLocation == nil, "Failed down does not claim a held button")
        check(output.dispatch(pressed, post: { _ in true }) && output.heldLocation != nil, "Successful press owns a release")
        let moving = InteractionStep(location: CGPoint(x: 0.6, y: 0.5), dragging: true, buttonHeld: true)
        check(!output.dispatch(moving, post: { _ in false }), "Failed move is reported")
        let release = output.update(InteractionStep())
        check(release.count == 1 && release.first?.location == p, "Failure releases at the last successfully posted location")
        print("One-hand drag: \(checks) checks passed")
    }
}
