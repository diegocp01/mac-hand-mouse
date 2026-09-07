import Foundation

/// Synthetic observations exercise timing and feedback, not physical recognition.
@main struct TapTimingTests {
    static var checks = 0
    static func check(_ condition: Bool, _ message: String) {
        checks += 1
        if !condition { fatalError(message) }
    }

    struct Trial {
        var detector = TwoFingerTapDetector()
        var time = 0.0
        let fps: Double
        var clicks = 0

        @discardableResult mutating func feed(_ pose: TapPose?, frames: Int = 1) -> Int {
            var fired = 0
            for _ in 0..<frames {
                time += 1 / fps
                if detector.update(pose, time: time) { fired += 1; clicks += 1 }
            }
            return fired
        }

        mutating func arm() {
            feed(.raised, frames: Int(ceil(0.2 * fps)) + 1)
            check(detector.phase == .ready, "a sustained raise arms at \(fps) fps")
            check(detector.cancellation == nil, "successful rearm clears the retry reason")
        }
    }

    static func main() {
        for fps in [15.0, 20, 30, 60] {
            var slow = Trial(fps: fps)
            slow.arm()
            slow.feed(.transition, frames: Int(ceil(0.7 * fps)))
            check(slow.detector.shouldFreeze && !slow.detector.canReleaseToClick,
                "preparation freezes the target without promising a click")
            slow.feed(.bent)
            check(!slow.detector.canReleaseToClick, "one bent frame is insufficient")
            slow.feed(.bent)
            check(slow.detector.canReleaseToClick, "confirmed bend permits release after slow preparation")
            check(slow.feed(.raised) == 1, "slow preparation leaves time to complete a tap at \(fps) fps")
            check(!slow.detector.canReleaseToClick, "release consumes click evidence")
            slow.feed(.bent, frames: 3)
            check(slow.feed(.raised) == 0, "a second bend cannot skip sustained raise rearming")
            slow.arm()
            slow.feed(.bent, frames: 3)
            check(slow.feed(.raised) == 1, "a fresh raised cycle allows the next click")

            var preparationTimeout = Trial(fps: fps)
            preparationTimeout.arm()
            preparationTimeout.feed(.transition, frames: Int(ceil(0.9 * fps)) + 1)
            check(preparationTimeout.detector.cancellation == .timedOut,
                "preparation remains bounded")
            preparationTimeout.feed(.bent, frames: 3)
            check(preparationTimeout.feed(.raised) == 0, "a late bend cannot revive expired preparation")
            check(preparationTimeout.detector.cancellation == .timedOut,
                "the timeout reason remains visible until rearmed")
            preparationTimeout.arm()

            var held = Trial(fps: fps)
            held.arm()
            held.feed(.bent, frames: Int(ceil(0.8 * fps)) + 1)
            check(held.detector.cancellation == .timedOut && !held.detector.shouldFreeze,
                "a direct bend retains the existing 0.65-second maximum hold")
            check(held.feed(.raised) == 0, "long hold release never clicks")
            held.arm()

            var jitter = Trial(fps: fps)
            jitter.arm()
            jitter.feed(.bent, frames: 2)
            for _ in 0..<Int(ceil(0.4 * fps)) {
                jitter.feed(.transition)
                jitter.feed(.bent)
            }
            check(jitter.detector.cancellation == .timedOut,
                "transition jitter never restarts the first-bend deadline")
            check(jitter.feed(.raised) == 0, "jitter cannot delay a click past the deadline")

            for bentFrames in [0, 1] {
                var incomplete = Trial(fps: fps)
                incomplete.arm()
                incomplete.feed(.transition, frames: 2)
                incomplete.feed(.bent, frames: bentFrames)
                check(!incomplete.detector.canReleaseToClick, "partial bend never advertises release")
                check(incomplete.feed(.raised) == 0, "partial bend does not click")
                check(incomplete.detector.cancellation == .incompleteBend,
                    "an incomplete bend explains the missed click")
                incomplete.arm()
            }

            for missing in [nil, TapPose.uncertain] {
                var interrupted = Trial(fps: fps)
                interrupted.arm()
                interrupted.feed(.bent, frames: 3)
                interrupted.feed(missing)
                check(interrupted.detector.cancellation == .trackingLost
                    && !interrupted.detector.canReleaseToClick,
                    "missing or uncertain evidence immediately cancels")
                check(interrupted.feed(.raised) == 0, "restored tracking cannot finish an old click")
                interrupted.arm()
            }

            var stale = Trial(fps: fps)
            stale.arm()
            stale.feed(.bent, frames: 3)
            stale.time += 0.2
            check(stale.feed(.raised) == 0 && stale.detector.cancellation == .trackingLost,
                "a stale cycle is canceled before release")
            stale.arm()
            stale.feed(.bent, frames: 3)
            check(!stale.detector.update(.raised, time: stale.time)
                && stale.detector.cancellation == .trackingLost,
                "duplicate timestamps cannot complete a click")
            stale.detector.reset()
            check(stale.detector.cancellation == nil && stale.detector.phase == .waiting,
                "an explicit reset clears old retry feedback")
        }

        var fast = Trial(fps: 60)
        fast.arm()
        fast.feed(.bent, frames: 2)
        check(!fast.detector.canReleaseToClick, "two fast frames do not bypass minimum press time")
        check(fast.feed(.raised) == 0 && fast.detector.cancellation == .incompleteBend,
            "a cycle under 50 ms does not click")

        var minimum = Trial(fps: 60)
        minimum.arm()
        minimum.feed(.bent, frames: 4)
        check(minimum.detector.canReleaseToClick, "release feedback becomes ready at the 50 ms boundary")
        check(minimum.feed(.raised) == 1, "minimum-duration confirmation clicks on release")

        for lateBy in [0.0, 0.00001] {
            var boundary = TwoFingerTapDetector()
            for step in 0...20 { _ = boundary.update(.raised, time: Double(step) / 100) }
            _ = boundary.update(.bent, time: 0.21)
            for step in 22...85 { _ = boundary.update(.bent, time: Double(step) / 100) }
            check(boundary.update(.raised, time: 0.86 + lateBy) == (lateBy == 0),
                "the 0.65-second first-bend deadline is inclusive and bounded")
        }

        print("Passed \(checks) tap timing and retry-feedback checks")
    }
}
