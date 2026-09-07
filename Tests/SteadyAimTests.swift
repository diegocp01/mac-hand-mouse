import Foundation
import CoreGraphics

@main struct SteadyAimTests {
    static var checks = 0
    static let hand = CGPoint(x: 0.5, y: 0.5)
    static let display = CGRect(x: 0, y: 0, width: 1440, height: 900)

    static func check(_ condition: Bool, _ message: String) {
        checks += 1
        if !condition { fatalError(message) }
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        hypot(a.x - b.x, a.y - b.y)
    }

    struct Motion {
        var filter = PointerFilter()
        var bounds: CGRect
        var fps: Double
        var enabled: Bool
        var precision: Bool
        var time = 0.0
        var point = hand
        var cursor: CGPoint

        init(fps: Double, enabled: Bool, bounds: CGRect = display, precision: Bool = false) {
            self.fps = fps; self.enabled = enabled; self.bounds = bounds
            self.precision = precision
            cursor = CGPoint(x: bounds.midX, y: bounds.midY)
            filter.reanchor(point: point, cursor: cursor, bounds: bounds, time: time)
        }

        mutating func frame(_ next: CGPoint, frozen: Bool = false) {
            time += 1 / fps; point = next
            cursor = filter.update(point: point, bounds: bounds, time: time,
                precision: precision, steadyAim: enabled, freeze: frozen)
            check(cursor.x.isFinite && cursor.y.isFinite &&
                cursor.x >= bounds.minX && cursor.x <= bounds.maxX - 1 &&
                cursor.y >= bounds.minY && cursor.y <= bounds.maxY - 1,
                "Steady aiming remains finite and inside the actual display")
        }

        mutating func move(to end: CGPoint, seconds: Double) {
            let start = point
            let count = max(1, Int(ceil(seconds * fps)))
            for i in 1...count {
                let fraction = Double(i) / Double(count)
                frame(CGPoint(x: start.x + (end.x - start.x) * fraction,
                    y: start.y + (end.y - start.y) * fraction))
            }
        }

        mutating func hold(_ seconds: Double) {
            for _ in 0..<Int(ceil(seconds * fps)) { frame(point) }
        }
    }

    struct Session {
        var engine = InteractionEngine()
        var fps: Double
        var destination: InteractionDestination
        var time = 0.0
        var cursor = CGPoint(x: 720, y: 450)
        var clicks = 0
        var last = InteractionStep()

        init(fps: Double, practice: Bool, enabled: Bool? = nil, mode: ClickMode = .twoFingerTap,
                allowClicks: Bool = true, allowDragging: Bool = false) {
            self.fps = fps; destination = practice ? .practice : .system
            var settings = InteractionSettings(mode: mode, allowClicks: allowClicks, allowDragging: allowDragging)
            if let enabled { settings.steadyAim = enabled }
            engine.configure(settings)
        }

        @discardableResult mutating func frame(_ point: CGPoint? = hand, pose: TapPose? = .raised,
                separation: Double? = 0.6, trusted: Bool = true, companion: Bool = false) -> InteractionStep {
            time += 1 / fps
            last = engine.process(index: point, pinchRatio: 0.9,
                timestamp: time, now: time + 0.01, bounds: display, running: true,
                trusted: trusted && destination == .system, destination: destination,
                cursorPosition: cursor, handSide: "left", companionPresent: companion, tapPose: pose,
                fingerSeparationRatio: separation)
            if let location = last.location { cursor = location }
            if last.click { clicks += 1 }
            if destination == .practice {
                check(last.systemLocation == nil && !last.systemClick && last.systemScrollY == 0 &&
                    !last.systemButtonHeld, "Steady aim practice never becomes system input")
            }
            return last
        }

        mutating func hold(_ point: CGPoint = hand, seconds: Double = 0.7) {
            for _ in 0..<Int(ceil(seconds * fps)) { frame(point) }
        }
    }

    static func main() {
        check(InteractionSettings().steadyAim, "Steady aiming defaults on")
        var slowTravel: [Double] = []
        var fastTravel: [Double] = []

        for fps in [15.0, 30.0, 60.0] {
            let end = CGPoint(x: 0.54, y: 0.5)
            var slow = Motion(fps: fps, enabled: true)
            var fast = Motion(fps: fps, enabled: true)
            var normal = Motion(fps: fps, enabled: false)
            let start = slow.cursor
            slow.move(to: end, seconds: 2); slow.hold(1)
            fast.move(to: end, seconds: 0.15); fast.hold(1)
            normal.move(to: end, seconds: 0.15); normal.hold(1)
            let slowDistance = distance(start, slow.cursor)
            let fastDistance = distance(start, fast.cursor)
            let normalDistance = distance(start, normal.cursor)
            check(slowDistance > 1 && slowDistance < fastDistance * 0.75,
                "Small deliberate movement gives materially finer aiming than a quick move at \(fps) fps")
            check(fastDistance >= normalDistance * 0.75,
                "Quick movement retains practical screen travel at \(fps) fps")
            check(slow.cursor.y == start.y && fast.cursor.y == start.y,
                "Horizontal fine motion does not create vertical drift")
            slowTravel.append(slowDistance); fastTravel.append(fastDistance)

            let settled = slow.cursor
            slow.hold(3)
            check(distance(settled, slow.cursor) < 0.1,
                "Holding a fine adjustment does not creep back toward the unassisted target")
            var stationary = Motion(fps: fps, enabled: true)
            stationary.hold(3)
            check(stationary.cursor == start, "An unmoving hand cannot generate pointer drift")

            let lock = slow.cursor
            for _ in 0..<Int(fps) { slow.frame(CGPoint(x: 0.72, y: 0.65), frozen: true) }
            check(slow.cursor == lock, "Target freeze discards movement while steady aiming")
            slow.filter.reanchor(point: slow.point, cursor: lock, bounds: slow.bounds, time: slow.time)
            slow.hold(0.5)
            check(slow.cursor == lock, "Unlock reanchoring cannot release accumulated hand movement")
            slow.move(to: CGPoint(x: 0.73, y: 0.65), seconds: 0.5)
            check(slow.cursor.x > lock.x && slow.cursor.x - lock.x < 40,
                "Fine aiming resumes with useful small movement after unlocking")

            var directUnlock = Motion(fps: fps, enabled: true)
            directUnlock.move(to: end, seconds: 2); directUnlock.hold(1)
            let directLock = directUnlock.cursor
            for _ in 0..<Int(fps) { directUnlock.frame(CGPoint(x: 0.72, y: 0.65), frozen: true) }
            directUnlock.frame(directUnlock.point)
            check(directUnlock.cursor == directLock,
                "Direct filter unfreeze cannot jump even without a caller-provided reanchor")
            directUnlock.hold(1)
            check(directUnlock.cursor == directLock,
                "A direct unlock discards frozen travel instead of releasing it gradually")
            directUnlock.move(to: CGPoint(x: 0.73, y: 0.65), seconds: 0.5)
            check(directUnlock.cursor.x > directLock.x && directUnlock.cursor.x - directLock.x < 40,
                "Direct unlock still permits subsequent fine correction")

            var precisionOnly = Motion(fps: fps, enabled: false, precision: true)
            var combined = Motion(fps: fps, enabled: true, precision: true)
            precisionOnly.move(to: end, seconds: 2); precisionOnly.hold(1)
            combined.move(to: end, seconds: 2); combined.hold(1)
            check(distance(start, combined.cursor) > 1 &&
                distance(start, combined.cursor) < distance(start, precisionOnly.cursor) * 0.75,
                "Steady aiming adds useful fine control when manual Precision is also enabled")

            for bounds in [display, CGRect(x: -2560, y: -250, width: 2560, height: 1440)] {
                for direction in [-1.0, 1.0] {
                    var edges = Motion(fps: fps, enabled: true, bounds: bounds)
                    let limit = direction < 0 ? 0.02 : 0.98
                    edges.move(to: CGPoint(x: limit, y: limit), seconds: 0.4)
                    edges.hold(0.6)
                    let corner = CGPoint(x: direction < 0 ? bounds.minX : bounds.maxX - 1,
                        y: direction < 0 ? bounds.minY : bounds.maxY - 1)
                    check(edges.cursor == corner, "Fast travel still reaches exact display corners")
                    edges.move(to: CGPoint(x: limit - direction * 0.02, y: limit - direction * 0.02), seconds: 0.3)
                    edges.hold(0.3)
                    check((edges.cursor.x - corner.x) * direction < -1 &&
                        (edges.cursor.y - corner.y) * direction < -1,
                        "Reversing from a display edge has no hidden dead zone")

                    var slowEdges = Motion(fps: fps, enabled: true, bounds: bounds)
                    slowEdges.move(to: CGPoint(x: limit, y: limit), seconds: 12)
                    slowEdges.hold(1)
                    check(slowEdges.cursor == corner,
                        "Slow assisted travel also reaches exact display corners")
                    slowEdges.move(to: CGPoint(x: limit - direction * 0.02, y: limit - direction * 0.02), seconds: 1)
                    slowEdges.hold(0.3)
                    check((slowEdges.cursor.x - corner.x) * direction < -1 &&
                        (slowEdges.cursor.y - corner.y) * direction < -1,
                        "Slow edge arrival preserves immediate direction reversal")
                }
            }

            for practice in [false, true] {
                var session = Session(fps: fps, practice: practice)
                let initial = session.cursor
                session.hold()
                check(session.engine.acquisition.active && session.cursor == initial,
                    "Default steady aiming acquires the existing cursor without a jump")
                for i in 1...Int(fps * 2) {
                    session.frame(CGPoint(x: 0.5 + 0.04 * Double(i) / (fps * 2), y: 0.5))
                }
                session.hold(end)
                check(session.clicks == 0 && session.cursor.x > initial.x,
                    "Aiming with raised fingers moves without an accidental click")
                let aim = session.cursor
                session.frame(CGPoint(x: 0.65, y: 0.6), separation: 0.2)
                check(session.cursor == aim && session.clicks == 0,
                    "The first close-finger observation still locks the fine-aimed target")
                // Use an ordinary tap duration, away from the detector's exact 50 ms boundary.
                for _ in 0..<Int(ceil(0.12 * fps)) {
                    session.frame(CGPoint(x: 0.65, y: 0.65), pose: .bent, separation: 0.2)
                }
                session.frame(CGPoint(x: 0.65, y: 0.6), separation: 0.2)
                check(session.cursor == aim && session.clicks == 1,
                    "A complete tap still clicks once at the locked fine-aimed location")
                session.frame(CGPoint(x: 0.65, y: 0.6), separation: 0.6)
                check(session.cursor == aim, "Separating fingers preserves the click target")
                session.hold(CGPoint(x: 0.65, y: 0.6), seconds: 0.4)
                for _ in 0..<2 { session.frame(CGPoint(x: 0.65, y: 0.6), pose: .bent) }
                session.frame(nil, pose: nil)
                session.hold(CGPoint(x: 0.65, y: 0.6))
                check(session.clicks == 1 && session.cursor == aim,
                    "Tracking loss cancels an unfinished tap and reacquires without drift")
                if !practice {
                    let denied = session.frame(CGPoint(x: 0.7, y: 0.6), trusted: false)
                    check(denied.blocked == .permission && denied.systemLocation == nil && !denied.systemClick,
                        "Steady aiming does not bypass Accessibility permission")
                }

                var clicksOff = Session(fps: fps, practice: practice, allowClicks: false)
                var clicksOffUnassisted = Session(fps: fps, practice: practice, enabled: false, allowClicks: false)
                clicksOff.hold(); clicksOffUnassisted.hold()
                for i in 1...Int(fps * 2) {
                    let point = CGPoint(x: 0.5 + 0.04 * Double(i) / (fps * 2), y: 0.5)
                    clicksOff.frame(point, separation: 0.2)
                    clicksOffUnassisted.frame(point, separation: 0.2)
                }
                clicksOff.hold(end); clicksOffUnassisted.hold(end)
                check(distance(initial, clicksOff.cursor) > 1 &&
                    distance(initial, clicksOff.cursor) < distance(initial, clicksOffUnassisted.cursor) * 0.75,
                    "Default steady aiming works with clicks disabled and does not acquire a finger lock")
                for _ in 0..<Int(ceil(0.12 * fps)) { clicksOff.frame(end, pose: .bent) }
                clicksOff.frame(end)
                check(clicksOff.clicks == 0 && !clicksOff.last.systemClick,
                    "Fine aiming with clicks disabled never turns a completed tap into a click")

                var companion = Session(fps: fps, practice: practice, allowDragging: true)
                companion.hold()
                for i in 1...Int(fps * 2) {
                    companion.frame(CGPoint(x: 0.5 + 0.04 * Double(i) / (fps * 2), y: 0.5))
                }
                companion.hold(end)
                let companionAim = companion.cursor
                for _ in 0..<Int(fps) {
                    let step = companion.frame(end, companion: true)
                    check(distance(companionAim, companion.cursor) < 0.01 && !step.click && !step.systemButtonHeld,
                        "A companion hand without an L cannot discard the accumulated fine-aim offset")
                }
                companion.hold(end)
                check(distance(companionAim, companion.cursor) < 0.01 && companion.clicks == 0,
                    "Removing a non-dragging companion preserves the fine-aimed cursor")
            }

            var legacy = Session(fps: fps, practice: false, enabled: false, mode: .pinch)
            var unchanged = Session(fps: fps, practice: false, enabled: true, mode: .pinch)
            legacy.hold(); unchanged.hold()
            for i in 1...Int(fps * 2) {
                let point = CGPoint(x: 0.5 + 0.04 * Double(i) / (fps * 2), y: 0.5)
                legacy.frame(point); unchanged.frame(point)
                check(legacy.cursor == unchanged.cursor,
                    "The tap-only steady aim setting does not alter legacy pinch motion")
            }
        }

        for values in [slowTravel, fastTravel] {
            check(values.max()! - values.min()! < values.max()! * 0.25,
                "Equivalent hand paths have comparable travel at 15, 30, and 60 fps")
        }
        print("Passed \(checks) steady aiming checks")
    }
}
