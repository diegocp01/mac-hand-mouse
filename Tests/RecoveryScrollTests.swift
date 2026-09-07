import Foundation
import CoreGraphics

@main struct RecoveryScrollTests {
    static var checks = 0
    static let aim = CGPoint(x: 0.3, y: 0.5)
    static let returned = CGPoint(x: 0.7, y: 0.5)
    static func check(_ condition: Bool, _ description: String) {
        checks += 1
        if !condition { fatalError(description) }
    }
    struct Session {
        var engine = InteractionEngine()
        var bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
        var cursor = CGPoint(x: 250, y: 450)
        var fps = 30.0
        var time = 0.0
        var trusted = true
        var running = true
        var destination: InteractionDestination = .system
        var clicks = 0
        var scrolled = 0
        var last = InteractionStep()
        mutating func setup() { engine.configure(InteractionSettings(allowClicks: true, allowScrolling: true)) }
        @discardableResult mutating func frame(_ point: CGPoint? = aim, ratio: Double? = 0.9,
                side: String? = "left", scroll: CGPoint? = nil, dt: Double? = nil) -> InteractionStep {
            time += dt ?? (1 / fps)
            last = engine.process(index: point, pinchRatio: ratio, timestamp: time, now: time + 0.01,
                bounds: bounds, running: running, trusted: trusted, destination: destination,
                cursorPosition: cursor, handSide: side, scrollPoint: scroll)
            if let location = last.location { cursor = location }
            if last.click { clicks += 1 }
            scrolled += Int(last.scrollY)
            return last
        }
        mutating func hold(_ point: CGPoint = aim, seconds: Double = 0.7, ratio: Double? = 0.9,
                           side: String? = "left", scroll: CGPoint? = nil) {
            for _ in 0..<Int(ceil(seconds * fps)) { frame(point, ratio: ratio, side: side, scroll: scroll) }
        }
    }

    static func main() {
        for fps in [15.0, 30.0, 60.0] {
            for bounds in [CGRect(x: 0, y: 0, width: 1440, height: 900),
                           CGRect(x: -2560, y: -100, width: 2560, height: 1440)] {
                var s = Session(); s.setup(); s.fps = fps; s.bounds = bounds
                s.cursor = CGPoint(x: bounds.minX + bounds.width * 0.2, y: bounds.midY)
                let original = s.cursor
                check(s.frame().location == nil, "A first observed frame cannot move the pointer")
                s.hold()
                check(s.engine.acquisition.active && s.cursor == original, "Steady open activation preserves the actual cursor")
                for _ in 0..<5 { s.frame(nil) }
                let firstReturn = s.frame(returned)
                check(firstReturn.location == nil && !firstReturn.click && firstReturn.scrollY == 0,
                      "HM-06: return at x=0.7 after five missing frames emits no input")
                s.hold(returned, seconds: 0.10)
                check(s.cursor == original && !s.engine.acquisition.active, "Returning hand must settle before resuming")
                s.hold(returned)
                check(s.cursor == original && s.engine.acquisition.active && s.clicks == 0,
                      "Reacquisition anchors at the existing cursor, without an eased or immediate warp")
                s.hold(CGPoint(x: 0.72, y: 0.5), seconds: 0.3)
                check(s.cursor.x > original.x && s.cursor.x - original.x < 170,
                      "Small motion after resuming stays small and responsive")
                s.frame(nil); s.hold(aim, ratio: 0.1)
                check(!s.engine.acquisition.active && s.clicks == 0 && s.last.location == nil,
                      "Returning with an already-closed pinch cannot take control or click")
                s.hold(aim, side: "right")
                check(s.last.blocked == .differentHand && s.last.location == nil,
                      "A different hand does not inherit an active session")
                s.cursor = CGPoint(x: bounds.minX + bounds.width * 0.6, y: bounds.minY + bounds.height * 0.25)
                let manual = s.cursor
                s.hold(aim)
                check(s.cursor == manual && s.engine.acquisition.active, "Resume respects physical mouse use while the hand was absent")
                s.cursor.x += 60
                let takeover = s.cursor
                check(s.frame().location == nil, "Physical mouse movement interrupts active hand control")
                s.hold()
                check(s.cursor == takeover, "Resuming after manual takeover cannot snap back")
                check(s.frame(returned, dt: 0.3).location == nil, "A delivery gap reacquires even without explicit missing-hand frames")
                s.hold(returned)
                check(s.cursor == takeover, "A callback gap cannot create a delayed pointer jump")
                s.cursor = CGPoint(x: bounds.maxX + 10, y: bounds.midY)
                check(s.frame().blocked == .cursorUnavailable && s.last.systemLocation == nil,
                      "A cursor on another display is never warped back")
            }

            var scroll = Session(); scroll.setup(); scroll.fps = fps; scroll.hold()
            let locked = scroll.cursor
            scroll.frame(ratio: 0.1, scroll: aim)
            check(scroll.clicks == 0 && scroll.scrolled == 0 && scroll.cursor == locked,
                  "Scroll candidate suppresses click detection immediately")
            scroll.hold(seconds: 0.4, ratio: 0.1, scroll: aim)
            check(scroll.engine.scroll.phase == .scrolling && scroll.scrolled == 0,
                  "Two fingers must be held deliberately before scrolling")
            var bounded = true
            for i in 1...Int(fps) {
                let p = CGPoint(x: 0.3, y: 0.5 - 0.1 * Double(i) / fps)
                let step = scroll.frame(p, ratio: 0.1, scroll: p)
                bounded = bounded && abs(Double(step.scrollY)) <= 600 / fps + 1
            }
            check((98...101).contains(scroll.scrolled) && bounded && scroll.cursor == locked && scroll.clicks == 0,
                  "Scrolling follows motion consistently across frame rates, with the pointer fixed and no clicks")
            let stopped = scroll.scrolled
            scroll.hold(CGPoint(x: 0.3, y: 0.4), seconds: 1, scroll: CGPoint(x: 0.3, y: 0.4))
            check(scroll.scrolled == stopped, "A still scroll pose emits no continuing scroll or inertia")
            scroll.frame(returned, ratio: 0.1)
            scroll.hold(returned, ratio: 0.1)
            check(scroll.scrolled == stopped && scroll.clicks == 0 && !scroll.engine.acquisition.active,
                  "Leaving scrolling with a closed pinch cannot click or jump")
            scroll.hold(returned)
            check(scroll.cursor == locked, "Leaving scroll mode reanchors normal pointing at the same cursor")
            scroll.hold(returned, seconds: 0.2, ratio: 0.1)
            check(scroll.clicks == 1, "A fresh pinch works after scrolling and rearming")

            var outlier = Session(); outlier.setup(); outlier.fps = fps; outlier.hold()
            outlier.hold(scroll: aim)
            check(outlier.frame(scroll: CGPoint(x: 0.3, y: 0.1)).scrollY == 0 && outlier.engine.scroll.phase == .idle,
                  "A tracking outlier cancels instead of scrolling an entire page")
            outlier.hold(scroll: aim)
            check(!outlier.engine.acquisition.active && outlier.scrolled == 0,
                  "A scroll outlier requires fresh pointing before held scrolling can resume")
            outlier.trusted = false; outlier.frame(scroll: aim)
            outlier.trusted = true; outlier.hold(scroll: aim)
            check(outlier.scrolled == 0 && !outlier.engine.acquisition.active,
                  "Permission restoration cannot resume scrolling with the old pose still held")

            var simulated = Session(); simulated.setup(); simulated.fps = fps
            simulated.destination = .practice; simulated.trusted = false
            simulated.hold(); simulated.hold(scroll: aim)
            var leaked = false
            for i in 1...Int(fps) {
                let p = CGPoint(x: 0.3, y: 0.5 + 0.1 * Double(i) / fps)
                let step = simulated.frame(p, scroll: p)
                leaked = leaked || step.systemLocation != nil || step.systemClick || step.systemScrollY != 0
            }
            check(simulated.scrolled < -95 && !leaked, "Practice scroll changes only the simulation")
        }
        for gate in ["clicksOff", "scrollOff", "preview", "permission", "pause"] {
            var s = Session(); s.setup(); s.hold(); s.hold(scroll: aim)
            switch gate {
            case "clicksOff": s.engine.configure(InteractionSettings(allowClicks: false, allowScrolling: true))
            case "scrollOff": s.engine.configure(InteractionSettings(allowClicks: true, allowScrolling: false))
            case "preview": s.engine.configure(InteractionSettings(allowClicks: true, pointerEnabled: false, allowScrolling: true))
            case "permission": s.trusted = false
            default: s.running = false
            }
            let step = s.frame(scroll: CGPoint(x: 0.3, y: 0.48))
            check(step.scrollY == 0 && !step.click, "Changing \(gate) cancels current output")
        }
        var off = Session(); off.engine.configure(InteractionSettings(allowClicks: false, allowScrolling: false))
        off.hold(); off.hold(scroll: aim)
        check(off.engine.scroll.phase == .idle && off.scrolled == 0, "Scrolling is off by default")
        var independent = Session(); independent.engine.configure(InteractionSettings(allowClicks: false, allowScrolling: true))
        independent.hold(); independent.hold(scroll: aim)
        independent.frame(scroll: CGPoint(x: 0.3, y: 0.49))
        check(independent.scrolled > 0 && independent.clicks == 0, "Scrolling has its own opt-in and works with clicks disabled")
        var pinchPractice = Session(); pinchPractice.setup(); pinchPractice.destination = .practice; pinchPractice.trusted = false
        pinchPractice.hold()
        var practiceClickLeaked = false
        for _ in 0..<10 {
            let step = pinchPractice.frame(ratio: 0.1)
            practiceClickLeaked = practiceClickLeaked || step.systemClick || step.systemLocation != nil || step.systemScrollY != 0
        }
        check(pinchPractice.clicks == 1 && !practiceClickLeaked, "Pinch practice clicks work without Accessibility and expose no system input")

        var keyboard = ActivationPolicy()
        check(keyboard.press() && !keyboard.press(), "Holding the shortcut toggles only once")
        keyboard.release(); check(keyboard.press(), "Releasing and pressing permits the next toggle")
        keyboard.release(); keyboard.awake = false; keyboard.displaysAwake = false; keyboard.sessionActive = false
        check(!keyboard.press(), "Inactive sessions consume shortcuts without starting the camera")
        keyboard.awake = true; keyboard.release(); check(!keyboard.press(), "Wake alone does not override a sleeping display or inactive session")
        keyboard.displaysAwake = true; keyboard.release(); check(!keyboard.press(), "Display wake cannot override an inactive session")
        keyboard.sessionActive = true
        check(!keyboard.press(), "A held key does not become a new resume request after wake")
        keyboard.release(); check(keyboard.press(), "A fresh press in an active session can resume")

        // Corner reach after off-center acquisition: the previous translated,
        // clamped map could never reach the opposite edge from these anchors.
        for fps in [15.0, 30.0, 60.0] {
            for bounds in [CGRect(x: 0, y: 0, width: 1440, height: 900),
                           CGRect(x: -2560, y: -100, width: 2560, height: 1440)] {
                for hand in [CGPoint(x: 0.3, y: 0.7), CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.7, y: 0.3)] {
                    for fraction in [0.1, 0.5, 0.9] {
                        for corner in [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1)] {
                            var s = Session(); s.setup(); s.fps = fps; s.bounds = bounds
                            s.cursor = CGPoint(x: bounds.minX + fraction * (bounds.width - 1),
                                               y: bounds.minY + (1 - fraction) * (bounds.height - 1))
                            let original = s.cursor
                            s.hold(hand)
                            check(s.cursor == original, "An off-center hand does not move the cursor during acquisition")
                            let region = s.engine.pointerControlRegion
                            check(region.minX >= 0.17 && region.maxX <= 0.83 && region.minY >= 0.17 && region.maxY <= 0.83,
                                  "Normal return poses keep fingertip travel away from camera boundaries")
                            let destination = CGPoint(x: corner.x == 0 ? region.minX : region.maxX,
                                                      y: corner.y == 0 ? region.minY : region.maxY)
                            s.hold(destination, seconds: 0.7)
                            let expected = CGPoint(x: corner.x == 0 ? bounds.minX : bounds.maxX - 1,
                                                   y: corner.y == 0 ? bounds.minY : bounds.maxY - 1)
                            check(s.cursor == expected && s.clicks == 0,
                                  "Every corner is reachable inside the guide after no-jump acquisition")
                            let inside = CGPoint(x: destination.x + (corner.x == 0 ? 0.01 : -0.01),
                                                 y: destination.y + (corner.y == 0 ? 0.01 : -0.01))
                            s.frame(inside)
                            check(s.cursor.x != expected.x && s.cursor.y != expected.y,
                                  "Reversing at a corner moves immediately without a hidden dead zone")
                            s.frame(nil); let resting = s.cursor
                            s.hold(hand)
                            check(s.cursor == resting && s.clicks == 0, "Corner return still preserves the cursor and cannot click")
                        }
                    }
                }
            }
        }
        var frozen = PointerFilter()
        let display = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        let target = CGPoint(x: -900, y: 400)
        frozen.reanchor(point: aim, cursor: target, bounds: display, time: 0)
        let frozenRegion = frozen.controlRegion
        for i in 1...10 {
            check(frozen.update(point: CGPoint(x: 0.98, y: 0.98), bounds: display, time: Double(i) / 30, freeze: true) == target,
                  "Click freeze ignores motion even beyond the smaller region")
            check(frozen.controlRegion == frozenRegion, "A frozen click cannot silently rebase the travel guide")
        }
        for hand in [0.0, 0.01, 0.22, 0.5, 0.78, 0.99, 1.0] {
            for cursor in [0.0, 0.5, 1.0] {
                let axis = PointerAxisMap(hand: hand, screen: cursor)
                check(axis.map(hand) == cursor, "Boundary anchors are finite and retain their cursor position")
                var previous = 0.0
                for i in 0...100 {
                    let current = axis.map(Double(i) / 100)
                    check(current.isFinite && current >= previous && current >= 0 && current <= 1,
                          "Axis mapping stays monotone and bounded, including camera-boundary anchors")
                    previous = current
                }
            }
        }

        let base = CGPoint(x: 0.5, y: 0.6), pip = CGPoint(x: 0.5, y: 0.5)
        check(ScrollPoseGeometry.shape(tip: CGPoint(x: 0.5, y: 0.35), pip: pip, base: base, aspect: 1.5) == .extended,
              "An extended finger is recognized")
        check(ScrollPoseGeometry.shape(tip: CGPoint(x: 0.51, y: 0.59), pip: pip, base: base, aspect: 1.5) == .folded,
              "A folded finger is recognized")
        check(ScrollPoseGeometry.shape(tip: CGPoint(x: CGFloat.nan, y: 0.35), pip: pip, base: base, aspect: 1.5) == .uncertain,
              "Invalid landmarks cannot establish scroll intent")
        print("Passed \(checks) recovery, scroll, practice, and keyboard activation checks.")
    }
}
