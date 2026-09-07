import Foundation

/// The visible next action must agree with the detector at camera cadence.
@main struct TapGuidanceTests {
    static var checks = 0

    static func check(_ condition: Bool, _ message: String) {
        checks += 1
        if !condition { fatalError(message) }
    }

    struct Trial {
        var detector = TwoFingerTapDetector()
        var time = 0.0
        var clicks = 0

        mutating func feed(_ pose: TapPose?, frames: Int = 1) {
            for _ in 0..<frames {
                time += 1.0 / 30
                if detector.update(pose, time: time) { clicks += 1 }
                for locked in [false, true] {
                    let guidance = TapGuidance(tap: detector, locked: locked)
                    check(guidance.action != .lift || detector.canReleaseToClick,
                        "feedback must never ask for a release before a click is possible")
                }
            }
        }

        mutating func arm() {
            feed(.raised, frames: 7)
            check(detector.phase == .ready, "a sustained raise makes the tap ready")
        }

        func expectAction(_ action: TapGuidance.Action, _ message: String) {
            for locked in [false, true] {
                check(TapGuidance(tap: detector, locked: locked).action == action, message)
            }
        }

        func expectRetry(_ reason: TwoFingerTapDetector.Cancellation) {
            check(detector.cancellation == reason, "the expected cancellation is observable")
            expectAction(.raise, "a canceled tap asks for a fresh raise even with the pointer locked")
            for locked in [false, true] {
                let guidance = TapGuidance(tap: detector, locked: locked)
                check(guidance.caption?.lowercased().contains("raise") == true,
                    "retry feedback beside the cursor names the required action")
            }
            check(clicks == 0, "the canceled attempt must not send a click")
        }

        mutating func rearmAfterRetry() {
            arm()
            check(detector.cancellation == nil, "a fresh raise clears retry feedback")
            check(TapGuidance(tap: detector, locked: false).action == .aim,
                "rearmed feedback returns to aiming")
            check(TapGuidance(tap: detector, locked: false).caption == nil,
                "rearmed aiming does not retain the retry caption")
            check(TapGuidance(tap: detector, locked: true).action == .bend,
                "rearmed locked feedback offers the next bend")
        }
    }

    static func main() {
        var cycle = Trial()
        cycle.expectAction(.raise, "initial guidance starts with raising both fingers")
        cycle.arm()
        check(TapGuidance(tap: cycle.detector, locked: false).action == .aim,
            "ready and unlocked asks the user to aim")
        check(TapGuidance(tap: cycle.detector, locked: true).action == .bend,
            "ready and locked asks the user to bend at the target")

        cycle.feed(.transition, frames: 3)
        check(cycle.detector.shouldFreeze && !cycle.detector.canReleaseToClick,
            "preparation has frozen the target without qualifying a click")
        cycle.expectAction(.bend, "an unqualified pending attempt still asks for a bend")
        cycle.feed(.bent)
        cycle.expectAction(.bend, "a single bent observation must not prompt release")
        cycle.feed(.bent)
        check(cycle.detector.canReleaseToClick, "the bend now qualifies for release")
        cycle.expectAction(.lift, "a confirmed bend prompts the user to lift")
        cycle.feed(.raised)
        check(cycle.clicks == 1, "following the confirmed lift produces exactly one click")
        cycle.expectAction(.raise, "a consumed click begins a fresh raised cycle")

        var fastBend = Trial()
        fastBend.arm()
        fastBend.feed(.bent, frames: 2)
        fastBend.expectAction(.bend, "two direct bend frames still respect minimum press time")
        fastBend.feed(.bent)
        fastBend.expectAction(.lift, "confirmed direct bending becomes ready to lift")

        for bentFirst in [false, true] {
            var timedOut = Trial()
            timedOut.arm()
            timedOut.feed(bentFirst ? .bent : .transition, frames: 30)
            timedOut.expectRetry(.timedOut)
            timedOut.rearmAfterRetry()
        }

        for bentFrames in [0, 1] {
            var incomplete = Trial()
            incomplete.arm()
            incomplete.feed(.transition, frames: 2)
            incomplete.feed(.bent, frames: bentFrames)
            incomplete.feed(.raised)
            incomplete.expectRetry(.incompleteBend)
            incomplete.rearmAfterRetry()
        }

        for missing in [nil, TapPose.uncertain] {
            var interrupted = Trial()
            interrupted.arm()
            interrupted.feed(.bent, frames: 3)
            interrupted.expectAction(.lift, "the interrupted trial starts with a qualified bend")
            interrupted.feed(missing)
            interrupted.expectRetry(.trackingLost)
            interrupted.rearmAfterRetry()
        }

        var stale = Trial()
        stale.arm()
        stale.feed(.bent, frames: 3)
        stale.time += 0.2
        stale.feed(.raised)
        stale.expectRetry(.trackingLost)
        stale.rearmAfterRetry()

        print("Passed \(checks) tap guidance behavior checks")
    }
}
