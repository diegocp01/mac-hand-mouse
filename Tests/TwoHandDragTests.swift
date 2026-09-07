import Foundation
import CoreGraphics

@main struct TwoHandDragTests {
    static var checks = 0
    static let aim = CGPoint(x: 0.4, y: 0.5)
    static func check(_ value: Bool, _ message: String) {
        checks += 1
        if !value { fatalError(message) }
    }
    struct Session {
        var engine = InteractionEngine()
        var output = DragOutput()
        var time = 0.0
        var fps = 30.0
        var cursor = CGPoint(x: -600, y: 400)
        var bounds = CGRect(x: -1440, y: -100, width: 1440, height: 900)
        var events: [DragEvent] = []
        var last = InteractionStep()
        var destination: InteractionDestination = .system
        var trusted = true
        var running = true
        var side = "left"
        var point: CGPoint? = aim
        var releaseVisible = true
        var primaryL = false
        var companion = false
        var companionL = false
        var ratio = 0.9
        var scrollPoint: CGPoint?
        var mode = ClickMode.pinch
        mutating func setup() {
            engine.configure(InteractionSettings(mode: mode, allowClicks: true, allowScrolling: true, allowDragging: true))
            hold(1)
        }
        @discardableResult mutating func frame(dt: Double? = nil, age: Double = 0.01) -> InteractionStep {
            time += dt ?? (1 / fps)
            let pose = ForwardPose(scale: 0.14, reach: 1.4, center: aim, side: side)
            last = engine.process(index: point, pinchRatio: ratio, forwardPose: pose,
                timestamp: time, now: time + age, bounds: bounds, running: running, trusted: trusted,
                destination: destination, cursorPosition: cursor, handSide: side, scrollPoint: scrollPoint,
                primaryL: primaryL, companionPresent: companion, companionL: companionL,
                primaryReleased: releaseVisible && !primaryL, companionReleased: releaseVisible && !companionL)
            events += output.update(last)
            if let location = last.location { cursor = location }
            return last
        }
        mutating func hold(_ seconds: Double) {
            for _ in 0..<Int(ceil(seconds * fps)) { frame() }
        }
        mutating func drag() {
            primaryL = true; companion = true; companionL = true
            hold(0.5)
        }
        var downs: Int { events.filter { $0.kind == .down }.count }
        var ups: Int { events.filter { $0.kind == .up }.count }
    }
    static func main() {
        // Owner selection is independent of detection ordering and never falls back to the modifier.
        for owner in ["left", "right"] {
            let other = owner == "left" ? "right" : "left"
            var ownership = HandOwnership()
            check(ownership.primaryIndex(in: [owner, other]) == nil, "Two hands at startup require one-hand acquisition")
            check(ownership.primaryIndex(in: [owner]) == 0, "Either single hand can acquire")
            ownership.lock(owner)
            check(ownership.primaryIndex(in: [other, owner]) == 1, "Vision ordering does not steal the cursor")
            check(ownership.primaryIndex(in: [owner, other]) == 0, "Original hand remains the owner")
            check(ownership.primaryIndex(in: [other]) == nil, "Modifier alone cannot control the cursor")
            check(ownership.primaryIndex(in: [owner, owner]) == nil, "Ambiguous same-side results fail closed")
            check(ownership.primaryIndex(in: [nil]) == nil, "Unknown hand cannot take over")
            ownership.lock(other)
            check(ownership.side == owner, "Settings/practice acquisition cannot replace the session owner")
            ownership.reset(); check(ownership.primaryIndex(in: [other]) == 0, "Explicit restart permits switching")
        }
        // Aspect-corrected L geometry, both mirror orientations, rotation and scale.
        for aspect in [1.0, 4.0 / 3, 16.0 / 9] {
            for mirror in [-1.0, 1.0] {
                for scale in [0.6, 1.0, 1.5] {
                    for angle in [0.0, 0.5, 1.2] {
                        func p(_ x: Double, _ y: Double) -> CGPoint {
                            let u = x * scale * mirror, v = y * scale
                            return CGPoint(x: 0.5 + (u * cos(angle) - v * sin(angle)) / aspect,
                                           y: 0.5 + u * sin(angle) + v * cos(angle))
                        }
                        check(LPoseGeometry.matches(thumbTip: p(0.16, 0), thumbIP: p(0.08, 0), thumbBase: p(0, 0),
                            indexTip: p(0, -0.22), indexPIP: p(0, -0.11), indexBase: p(0, 0),
                            otherFingersFolded: true, aspect: aspect), "Extended perpendicular thumb/index form an L")
                        check(!LPoseGeometry.matches(thumbTip: p(0, -0.18), thumbIP: p(0, -0.09), thumbBase: p(0, 0),
                            indexTip: p(0, -0.22), indexPIP: p(0, -0.11), indexBase: p(0, 0),
                            otherFingersFolded: true, aspect: aspect), "Parallel fingers are not an L")
                    }
                }
            }
        }
        check(!LPoseGeometry.matches(thumbTip: .zero, thumbIP: .zero, thumbBase: .zero,
            indexTip: aim, indexPIP: .zero, indexBase: .zero, otherFingersFolded: true, aspect: .nan), "Malformed geometry cannot arm")
        check(!LPoseGeometry.matches(thumbTip: CGPoint(x: 0.66, y: 0.5), thumbIP: CGPoint(x: 0.58, y: 0.5), thumbBase: CGPoint(x: 0.5, y: 0.5),
            indexTip: CGPoint(x: 0.5, y: 0.28), indexPIP: CGPoint(x: 0.5, y: 0.39), indexBase: CGPoint(x: 0.5, y: 0.5),
            otherFingersFolded: false, aspect: 1), "An open palm is not the explicit L pose")

        for fps in [15.0, 30.0, 60.0] {
            for mode in [ClickMode.pinch, .forward] {
                var s = Session(); s.fps = fps; s.mode = mode; s.setup()
                let original = s.cursor
                s.primaryL = true; s.hold(0.6)
                check(s.downs == 0, "One L hand never starts a drag")
                s.companion = true; s.ratio = 0.1; s.scrollPoint = aim; s.hold(0.4)
                check(s.downs == 0 && !s.last.click && s.last.scrollY == 0,
                      "Second hand suppresses pinch and scroll without controlling the cursor")
                s.ratio = 0.9; s.scrollPoint = nil; s.companionL = true
                s.frame()
                check(s.downs == 0 && s.cursor == original, "First L-pair frame freezes aim without pressing")
                s.hold(0.10)
                check(s.downs == 0, "Brief accidental L poses cannot press")
                s.hold(0.4)
                check(s.downs == 1 && s.ups == 0 && s.last.dragging, "Both L poses press once after confirmation")
                check(s.events.first?.location == original, "Mouse-down uses the original selected target")
                for i in 1...12 {
                    s.point = CGPoint(x: aim.x + Double(i) * 0.005, y: aim.y + Double(i) * 0.002)
                    s.frame()
                }
                check(s.cursor.x > original.x && s.cursor.y > original.y && s.downs == 1,
                      "Owner movement extends a held selection without additional downs")
                check(s.events.contains { $0.kind == .moved }, "Held motion emits drag events")
                let end = s.cursor
                s.primaryL = false; s.frame()
                check(s.ups == 1 && s.events.last?.location == end && !s.last.click && s.last.scrollY == 0,
                      "Breaking owner L releases at the last drag position with no trailing click")
                s.hold(0.4); check(s.ups == 1, "Release is idempotent")
                s.drag(); check(s.downs == 2, "A new deliberate pair can drag again")
                s.companionL = false; s.frame()
                check(s.ups == 2, "Breaking modifier L also releases")
            }

            // Every production guard must reconcile a held button to exactly one up.
            for interruption in 0..<11 {
                var s = Session(); s.fps = fps; s.setup(); s.drag()
                check(s.downs == 1, "Interruption fixture starts held")
                switch interruption {
                case 0: s.point = nil
                case 1: s.companion = false
                case 2: s.trusted = false
                case 3: s.running = false
                case 4: s.side = "right"
                case 5: s.cursor.x += 60
                case 6: s.bounds = .zero
                case 7: s.engine.configure(InteractionSettings(allowClicks: false))
                case 8: s.engine.configure(InteractionSettings(pointerEnabled: false))
                case 9: s.destination = .practice
                default: break
                }
                s.frame(age: interruption == 10 ? 0.3 : 0.01)
                check(s.ups == 1 && !s.last.systemDragging, "Interruption \(interruption) releases held input")
                s.frame(); check(s.ups == 1, "Repeated blocked frames never duplicate releases")
            }
            var lost = Session(); lost.fps = fps; lost.setup(); lost.drag()
            lost.companion = false; lost.frame(); lost.companion = true; lost.hold(1)
            check(lost.downs == 1 && lost.ups == 1, "Modifier loss and held-pose return do not silently restart")
            lost.companionL = false; lost.hold(0.25); lost.drag()
            check(lost.downs == 2, "A visible broken L rearms after modifier loss")
            lost.point = nil; lost.frame(); lost.point = aim; lost.hold(1)
            check(lost.downs == 2 && lost.ups == 2, "Owner loss and reacquisition require a fresh gesture")
            lost.primaryL = false; lost.hold(0.25); lost.drag()
            check(lost.downs == 3, "Fresh gesture after owner recovery works")
            lost.frame(dt: 0.3); lost.hold(1)
            check(lost.downs == 3 && lost.ups == 3, "Stalled frames release and cannot restart from held poses")
            var uncertain = Session(); uncertain.fps = fps; uncertain.setup(); uncertain.drag()
            uncertain.releaseVisible = false; uncertain.companionL = false; uncertain.frame()
            uncertain.companionL = true; uncertain.hold(1)
            check(uncertain.ups == 1 && uncertain.downs == 1, "Uncertain landmarks release without rearming")
            uncertain.releaseVisible = true; uncertain.companionL = false; uncertain.frame()
            uncertain.companionL = true; uncertain.hold(0.6)
            check(uncertain.downs == 1, "One noisy release frame cannot rearm")
            uncertain.companionL = false; uncertain.hold(0.25); uncertain.drag()
            check(uncertain.downs == 2, "Sustained visible release permits a fresh drag")

            var malformed = Session(); malformed.fps = fps; malformed.setup(); malformed.drag()
            malformed.point = CGPoint(x: 1.2, y: 0.5); malformed.frame()
            malformed.point = aim; malformed.hold(1)
            check(malformed.ups == 1 && malformed.downs == 1, "Invalid normalized points cancel drag through acquisition recovery")

            var disabled = Session(); disabled.fps = fps; disabled.setup()
            disabled.engine.configure(InteractionSettings(allowScrolling: true, allowDragging: false))
            disabled.hold(1)
            var single = disabled
            disabled.primaryL = true; disabled.companionL = true; disabled.companion = true
            // A bystander cannot suppress ordinary clicking when the feature is off.
            for i in 0..<60 {
                disabled.ratio = i < 20 ? 0.9 : (i < 40 ? 0.1 : 0.9)
                single.ratio = disabled.ratio
                disabled.frame(); single.frame()
                check(disabled.last.click == single.last.click && disabled.last.location == single.last.location,
                      "Disabled modifier preserves single-hand input")
            }
            check(disabled.downs == 0, "Dragging is opt-in")
            var toggled = Session(); toggled.fps = fps; toggled.setup(); toggled.drag()
            toggled.engine.configure(InteractionSettings(allowDragging: false)); toggled.frame()
            check(toggled.ups == 1, "Disabling dragging releases the button")
            toggled.engine.configure(InteractionSettings(allowDragging: true)); toggled.hold(1)
            check(toggled.downs == 1, "Re-enabling while poses remain held requires release")

            var practice = Session(); practice.fps = fps; practice.destination = .practice; practice.trusted = false
            practice.setup(); practice.drag()
            check(practice.last.dragging && !practice.last.systemDragging && practice.events.isEmpty,
                  "Practice exercises real drag detection with no system button events")
            var reset = Session(); reset.fps = fps; reset.setup(); reset.drag()
            reset.events += reset.output.release(); reset.engine.reset(); reset.hold(1)
            check(reset.ups == 1 && reset.downs == 1, "Explicit app reset releases once and preserves rearm requirement")
        }
        var dispatch = DragOutput()
        let start = InteractionStep(location: aim, dragging: true)
        check(!dispatch.dispatch(start, post: { _ in false }) && dispatch.heldLocation == nil,
              "Failed mouse-down allocation cannot leave a held button")
        check(dispatch.dispatch(start, post: { _ in true }), "Posted down commits held state")
        let moved = InteractionStep(location: CGPoint(x: 100, y: 200), dragging: true)
        check(!dispatch.dispatch(moved, post: { _ in false }), "Failed drag movement is reported")
        check(dispatch.release().first?.location == aim, "Failure cleanup releases at last posted position")
        check(dispatch.release().isEmpty, "Cleanup cannot emit duplicate ups")
        print("\(checks) two-hand ownership, L geometry, drag lifecycle and production checks passed")
    }
}
