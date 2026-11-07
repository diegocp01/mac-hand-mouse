import Foundation
import CoreGraphics

@main
struct PracticeDiagnosticsTests {
    static var checks = 0

    static func check(_ condition: Bool, _ message: String) {
        checks += 1
        if !condition { fatalError(message) }
    }

    static func landmarks(click: Bool, confidence: Float = 0.9) -> [String: HandLandmark] {
        var result: [String: HandLandmark] = [:]
        for (i, name) in ["index", "middle", "ring", "little"].enumerated() {
            let x = 0.35 + Double(i) * 0.08
            let reach = click && i >= 2 ? 0.13 : 0.2
            result[name + "MCP"] = HandLandmark(x: x, y: 0.6, confidence: confidence)
            result[name + "PIP"] = HandLandmark(x: x, y: 0.5, confidence: confidence)
            result[name + "Tip"] = HandLandmark(x: x, y: 0.6 - reach, confidence: confidence)
        }
        return result
    }

    struct Trace {
        var engine = InteractionEngine()
        var recorder = PracticeDiagnosticRecorder()
        var time = 100_000.0
        var cursor = CGPoint(x: 720, y: 450)
        var lastTime: Double?
        let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let fps: Double

        init(fps: Double) {
            self.fps = fps
            let settings = InteractionSettings(mode: .pointAndHold)
            engine.configure(settings)
            recorder.start(width: 1440, height: 900, settings: settings, now: time, intent: .click)
        }

        mutating func frame(_ landmarks: [String: HandLandmark], gap: Double? = nil, age: Double = 0.01,
                            right: Double? = 1.2) {
            time += gap ?? 1 / fps
            let input = PracticeDiagnosticInput(timestamp: time, now: time + age, aspect: 4 / 3,
                landmarks: landmarks, handSide: "right", fiveFingerPinchRatio: right)
            let observation = PointingObservation(landmarks: landmarks, aspect: input.aspect)
            let movement = engine.pointHold.movement(from: observation.indexPoint)
            let step = engine.process(index: observation.indexPoint, pinchRatio: nil,
                timestamp: input.timestamp, now: input.now, bounds: bounds, running: true, trusted: false,
                destination: .practice, cursorPosition: cursor, handSide: input.handSide,
                pointingPose: observation.pose, fiveFingerPinchRatio: right)
            if let location = step.location { cursor = location }
            let outcome = PracticeDiagnosticOutcome(engine: engine, step: step, pose: observation.pose)
            recorder.record(input, outcome: outcome, frameInterval: lastTime.map { time - $0 },
                movement: movement, destination: .practice)
            lastTime = time
            check(step.systemLocation == nil && !step.systemClick && !step.systemRightClick &&
                step.systemScrollY == 0 && !step.systemButtonHeld, "Diagnostics never expose system input")
        }

        mutating func hold(_ points: [String: HandLandmark], seconds: Double) {
            for _ in 0..<Int(ceil(seconds * fps)) { frame(points) }
        }

        mutating func interrupt() {
            time += 0.2
            engine.trackingInterrupted()
            recorder.interrupt(at: time, outcome: PracticeDiagnosticOutcome(engine: engine,
                step: InteractionStep(blocked: .staleFrame, destination: .practice), pose: nil))
        }
    }

    static func humanReadableResults() throws {
        for practicing in [false, true] {
            check(CameraTestPolicy.usesPracticeOutput(practicing: practicing, presented: true),
                "A presented camera test always uses simulated output, including after pause")
        }
        check(!CameraTestPolicy.usesPracticeOutput(practicing: false, presented: false),
            "Leaving the test retains normal output routing")
        check(!CameraTestPolicy.allowsCameraToggle(presented: true, running: false, hasRecording: true),
            "A resume shortcut cannot silently restart the camera while reviewing results")
        check(CameraTestPolicy.allowsCameraToggle(presented: true, running: true, hasRecording: true),
            "Pause must remain available during recording")
        check(CameraTestPolicy.shouldStopCamera(presented: true, running: true, hasRecording: true, recording: false),
            "Finishing or expiring a recording stops the test camera")
        check(!CameraTestPolicy.shouldStopCamera(presented: true, running: true, hasRecording: false, recording: false),
            "A clearly labeled preview can run without recording")
        check(!CameraTestPolicy.shouldStopCamera(presented: false, running: true, hasRecording: true, recording: false),
            "An old test result cannot stop normal camera control after leaving the test")
        let open = landmarks(click: false)
        let click = landmarks(click: true)
        var success = Trace(fps: 30)
        success.hold(open, seconds: 0.4)
        success.hold(click, seconds: 1.3)
        success.recorder.stop(.manual)
        let before = try success.recorder.session!.encoded()
        let result = DiagnosticResult(session: success.recorder.session!)
        check(result.verdict == .confirmed && result.leftClicks == 1 && result.rightClicks == 0,
            "A single recorded click gets a plain-English confirmation")
        check(try success.recorder.session!.encoded() == before, "Review does not change the recording or detector settings")

        var missed = Trace(fps: 30)
        missed.hold(open, seconds: 1.5)
        missed.recorder.stop(.manual)
        let missedResult = DiagnosticResult(session: missed.recorder.session!)
        check(missedResult.verdict == .notConfirmed && missedResult.explanation.contains("two-finger hold"),
            "A recording with no click pose explains what was not observed")

        var unprepared = Trace(fps: 30)
        unprepared.hold(click, seconds: 1.3)
        unprepared.recorder.stop(.manual)
        check(DiagnosticResult(session: unprepared.recorder.session!).explanation.contains("open hand"),
            "A click pose that never armed the detector explains the missing preparation step")

        var short = Trace(fps: 30)
        short.hold(open, seconds: 0.4)
        short.hold(click, seconds: 0.3)
        short.recorder.stop(.manual)
        check(DiagnosticResult(session: short.recorder.session!).explanation.contains("recording stopped"),
            "Stopping mid-hold is not blamed on an unseen finger failure")

        var unclear = click
        unclear["middlePIP"]?.confidence = 0.59
        var canceled = Trace(fps: 30)
        canceled.hold(open, seconds: 0.4)
        canceled.hold(click, seconds: 0.4)
        canceled.frame(unclear)
        canceled.hold(open, seconds: 0.5)
        canceled.recorder.stop(.manual)
        let canceledResult = DiagnosticResult(session: canceled.recorder.session!)
        check(canceledResult.verdict == .notConfirmed && canceledResult.explanation.contains("middle finger"),
            "Review uses the actual cancellation frame even after the hand becomes clear again")

        var noHand = Trace(fps: 30)
        noHand.hold([:], seconds: 0.4)
        noHand.recorder.stop(.manual)
        check(DiagnosticResult(session: noHand.recorder.session!).verdict == .noData,
            "No tracked hand is not a successful no-click test")
        let empty = PracticeDiagnosticSession(width: 1440, height: 900, precisionMode: false, steadyAim: true)
        check(DiagnosticResult(session: empty).verdict == .noData, "Empty recordings explain that no data was captured")

        var aim = Trace(fps: 30)
        aim.recorder.nextAttempt(intent: .aim)
        aim.hold(open, seconds: 0.8)
        aim.recorder.stop(.manual)
        check(DiagnosticResult(session: aim.recorder.session!).verdict == .confirmed,
            "A labeled move-only attempt can confirm that no click was detected")

        var repeated = Trace(fps: 30)
        for _ in 0..<2 {
            repeated.hold(open, seconds: 0.4)
            repeated.hold(click, seconds: 1.3)
        }
        repeated.recorder.stop(.manual)
        check(DiagnosticResult(session: repeated.recorder.session!).verdict == .unexpected,
            "Multiple clicks are not reported as one successful intended click")

        var right = Trace(fps: 30)
        right.hold(open, seconds: 0.4)
        for _ in 0..<8 { right.frame(click, right: 0.3) }
        right.recorder.stop(.manual)
        check(DiagnosticResult(session: right.recorder.session!).verdict == .unexpected,
            "A right click does not satisfy a left-click test")

        let ready = PracticeDiagnosticOutcome(engine: missed.engine, step: InteractionStep(), pose: .move)
        let guidance = DiagnosticGuidance(outcome: ready, fingers: PointingObservation(landmarks: open, aspect: 1).fingers, intent: .click)
        check(guidance.detail.contains("ring") && guidance.detail.contains("little"),
            "Ready guidance tells the user what to do with their fingers instead of showing internal state names")
    }

    static func main() throws {
        if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--replay" {
            guard FeatureFlags.diagnostics else {
                fputs("Diagnostics are disabled. Set FeatureFlags.diagnostics to true and rebuild to replay recordings.\n", stderr)
                exit(1)
            }
            let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
            let session = try PracticeDiagnosticSession.decode(data)
            let report = try PracticeDiagnosticReplay.run(session)
            print(report.summary)
            return
        }

        if !FeatureFlags.diagnostics {
            let replay = Process()
            let output = Pipe()
            replay.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            replay.arguments = ["--replay", "diagnostics-must-not-be-opened.json"]
            replay.standardError = output
            try replay.run()
            replay.waitUntilExit()
            let message = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            check(replay.terminationStatus == 1 && message.contains("Diagnostics are disabled."),
                "Disabled replay must stop before opening a recording")
        }

        try humanReadableResults()
        let open = landmarks(click: false)
        let click = landmarks(click: true)
        let observation = PointingObservation(landmarks: click, aspect: 4 / 3)
        check(observation.pose == .click, "Real landmark geometry classifies the two-finger pose")
        check(observation.fingers.count == 4, "Every pointing finger has diagnostic evidence")
        check(observation.fingers[2].shape == .folded, "Relaxed outer curls keep the production cutoff")
        check(abs((observation.fingers[2].reachRatio ?? 0) - 1.3) < 1e-9, "Reach ratio is observable")
        check(observation.fingers[0].requiredConfidence == 0.6, "Raised fingers keep the original confidence floor")
        check(observation.fingers[2].requiredConfidence == 0.45, "Outer fingers keep the original confidence floor")

        var hidden = click
        hidden.removeValue(forKey: "ringTip")
        check(PointingObservation(landmarks: hidden, aspect: 4 / 3).pose == .click,
            "One hidden outer finger remains tolerated")
        hidden.removeValue(forKey: "littleTip")
        check(PointingObservation(landmarks: hidden, aspect: 4 / 3).pose == nil,
            "Two hidden outer fingers never become a click")
        hidden = click
        hidden["middlePIP"]?.confidence = 0.59
        let uncertain = PointingObservation(landmarks: hidden, aspect: 4 / 3)
        check(uncertain.pose == nil && uncertain.fingers[1].issue == .lowConfidence,
            "A visible skeleton can still fail the stricter click confidence gate")
        check(uncertain.fingers[1].reachRatio != nil, "Low-confidence geometry remains inspectable, not accepted")
        hidden["middlePIP"]?.confidence = 0.6
        check(PointingObservation(landmarks: hidden, aspect: 4 / 3).pose == .click,
            "Float confidence at the existing boundary remains accepted")
        hidden = open
        hidden["indexTip"]?.confidence = 0.44
        check(PointingObservation(landmarks: hidden, aspect: 4 / 3).pose == nil,
            "Outer fingers cannot bypass the camera's index-tip gate")
        check(PointingObservation(landmarks: [:], aspect: 1).fingers.allSatisfy { $0.issue == .missingJoints },
            "Missing hands expose missing evidence, never invented folded fingers")

        for fps in [15.0, 30, 60] {
            var trace = Trace(fps: fps)
            trace.hold(open, seconds: 0.4)
            trace.hold(click, seconds: 1.4)
            trace.hold(click, seconds: 1.2)
            trace.recorder.nextAttempt(intent: .cancel)
            trace.hold(open, seconds: 0.3)
            trace.hold(click, seconds: 0.4)
            trace.frame(uncertain.landmarks)
            check(trace.engine.pointHold.lastCancellation == .uncertainPose, "The actual detector explains an uncertain cancellation")
            trace.recorder.nextAttempt(intent: .aim)
            trace.hold(open, seconds: 0.4)
            trace.hold(click, seconds: 0.3)
            trace.interrupt()
            check(trace.engine.pointHold.lastCancellation == .trackingInterrupted, "Watchdog cancellation is retained")
            trace.hold(open, seconds: 0.3)
            trace.hold(click, seconds: 0.4)
            trace.frame(click, gap: 0.15)
            check(trace.engine.pointHold.lastCancellation == .frameGap, "Callback gaps have an explicit reason")
            trace.hold(open, seconds: 0.3)
            trace.frame(click, age: 0.25)
            trace.frame([:])
            trace.recorder.stop(.manual)
            let session = trace.recorder.session!
            let encoded = try session.encoded()
            let decoded = try PracticeDiagnosticSession.decode(encoded)
            let report = try PracticeDiagnosticReplay.run(decoded)
            check(report.mismatches == 0, "Exported landmarks replay the same production decisions at \(fps) fps")
            check(report.leftClicks == 1 && report.rightClicks == 0, "Replay preserves one-click-per-raise")
            check(report.missedClickAttempts == 0 && report.falseClickAttempts == 0,
                "Explicit attempt labels, not classifier guesses, determine trial results")
            check(session.entries.allSatisfy { $0.time < 20 && ($0.input?.timestamp ?? 0) < 20 },
                "Exports contain session-relative time, never machine uptime")
            let json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
            check(Set(json.keys) == Set(["schemaVersion", "detector", "width", "height", "precisionMode", "steadyAim", "entries", "stopReason"]),
                "The export has an explicit metadata allowlist with no device IDs, paths, video, or audio")
            check(decoded.entries.contains { $0.input?.landmarks["middlePIP"]?.confidence == 0.59 },
                "Export retains low-confidence joints for calibration instead of dropping them")
        }

        var detector = PointHoldDetector()
        for t in [0.0, 0.08, 0.16] { _ = detector.update(pose: .move, point: CGPoint(x: 0.5, y: 0.5), time: t) }
        _ = detector.update(pose: .click, point: CGPoint(x: 0.5, y: 0.5), time: 0.2)
        check(abs((detector.movement(from: CGPoint(x: 0.53, y: 0.5)) ?? 0) - 0.03) < 1e-9,
            "Diagnostics can read displacement without advancing the detector")
        check(!detector.update(pose: .click, point: CGPoint(x: 0.53, y: 0.5), time: 0.24), "Movement still cancels")
        check(detector.lastCancellation == .movement, "The existing movement limit reports its reason")
        detector.reset()
        check(detector.lastCancellation == nil, "A fresh session clears old cancellation feedback")

        var bounded = PracticeDiagnosticRecorder(maximumSamples: 2)
        let settings = InteractionSettings(mode: .pointAndHold)
        let input = PracticeDiagnosticInput(timestamp: 100, now: 100.01, aspect: 1, landmarks: open, handSide: "right")
        let outcome = PracticeDiagnosticOutcome(engine: InteractionEngine(), step: InteractionStep(), pose: .move)
        bounded.record(input, outcome: outcome, destination: .practice)
        check(bounded.session == nil, "No recording exists before explicit consent")
        bounded.start(width: 1440, height: 900, settings: settings, now: 100, intent: .aim)
        bounded.record(input, outcome: outcome, destination: .system)
        check(bounded.sampleCount == 0, "System-control frames cannot enter a practice recording")
        bounded.record(input, outcome: outcome, destination: .practice)
        bounded.record(input, outcome: outcome, destination: .practice)
        check(!bounded.isRecording && bounded.session?.stopReason == .limit && bounded.sampleCount == 2,
            "Recording stops at its memory bound without discarding the captured evidence")
        bounded.record(input, outcome: outcome, destination: .practice)
        check(bounded.sampleCount == 2, "Stopped recordings never silently resume")
        bounded.discard()
        check(bounded.session == nil && !bounded.isRecording, "Discard clears only the opt-in in-memory recording")
        var duration = PracticeDiagnosticRecorder(maximumDuration: 0.5)
        duration.start(width: 1440, height: 900, settings: settings, now: 99, intent: .free)
        duration.record(input, outcome: outcome, destination: .practice)
        check(!duration.isRecording && duration.session?.stopReason == .limit, "Recording also has a duration bound")

        duration.start(width: 1440, height: 900, settings: settings, now: 100, intent: .free)
        duration.expire(at: 100.5)
        check(!duration.isRecording && duration.session?.stopReason == .limit,
            "A stalled camera cannot keep a recording active beyond its duration limit")
        for reason in [DiagnosticStopReason.paused, .practiceFinished, .taskChanged, .cameraChanged, .interactionReset] {
            bounded.start(width: 1440, height: 900, settings: settings, now: 100, intent: .aim)
            bounded.record(input, outcome: outcome, destination: .practice)
            bounded.stop(reason)
            bounded.nextAttempt(intent: .click)
            bounded.record(input, outcome: outcome, destination: .practice)
            check(bounded.sampleCount == 1 && bounded.session?.stopReason == reason && bounded.attempt == 1,
                "Stopping for \(reason) retains data without resuming or relabeling it")
        }
        var sanitized = input
        sanitized.landmarks["cameraIdentifier"] = HandLandmark(x: 1, y: 1, confidence: 1)
        sanitized.handSide = "not-a-hand-side"
        bounded.start(width: 1440, height: 900, settings: settings, now: 100, intent: .free)
        bounded.record(sanitized, outcome: outcome, destination: .practice)
        check(bounded.session?.entries[0].input?.landmarks["cameraIdentifier"] == nil &&
            bounded.session?.entries[0].input?.handSide == nil, "Only named joints and known hand sides can be exported")

        var falsePositive = Trace(fps: 30)
        falsePositive.recorder.nextAttempt(intent: .aim)
        falsePositive.hold(open, seconds: 0.4)
        falsePositive.hold(click, seconds: 1.3)
        falsePositive.recorder.nextAttempt(intent: .click)
        falsePositive.hold(open, seconds: 0.4)
        let labeled = try PracticeDiagnosticReplay.run(falsePositive.recorder.session!)
        check(labeled.falseClickAttempts == 1 && labeled.missedClickAttempts == 1,
            "Replay reports false and missed clicks against user intent rather than predicted poses")
        var right = Trace(fps: 30)
        right.hold(open, seconds: 0.4)
        right.hold(click, seconds: 0.3)
        right.frame(click, right: 0.3)
        check(right.engine.pointHold.lastCancellation == .competingGesture, "Right-click priority cancels a pending left hold explicitly")
        for _ in 0..<8 { right.frame(click, right: 0.3) }
        let rightReport = try PracticeDiagnosticReplay.run(right.recorder.session!)
        check(rightReport.mismatches == 0 && rightReport.rightClicks == 1 && rightReport.leftClicks == 0,
            "Replay retains competing right-click evidence and priority")

        for aspect in [0.75, 1.0, 16.0 / 9.0] {
            for confidence: Float in [0.34, 0.35, 0.44, 0.45, 0.59, 0.6, 0.9] {
                for reach in [0.11, 0.12, 0.13, 0.145, 0.15, 0.16, 0.2] {
                    var points = landmarks(click: true, confidence: confidence)
                    points["ringTip"]?.y = 0.6 - reach
                    points["middleTip"]?.y = 0.6 - reach
                    func originalShape(_ finger: String, minimum: Float, fold: Double) -> FingerShape {
                        guard ["Tip", "PIP", "MCP"].allSatisfy({ (points[finger + $0]?.confidence ?? 0) >= minimum }),
                              let tip = points[finger + "Tip"]?.point,
                              let pip = points[finger + "PIP"]?.point,
                              let base = points[finger + "MCP"]?.point else { return .uncertain }
                        func distance(_ a: CGPoint, _ b: CGPoint) -> Double { hypot((a.x - b.x) * aspect, a.y - b.y) }
                        let proximal = distance(pip, base), reach = distance(tip, base), distal = distance(tip, pip)
                        guard proximal > 0.015 else { return .uncertain }
                        if reach / proximal > 1.6 && reach / max(proximal + distal, 1e-9) > 0.9 { return .extended }
                        if reach / proximal < fold { return .folded }
                        return .uncertain
                    }
                    let expected = confidence < 0.45 ? nil : PointingPoseClassifier.classify(
                        index: originalShape("index", minimum: 0.6, fold: 1.2),
                        middle: originalShape("middle", minimum: 0.6, fold: 1.2),
                        ring: originalShape("ring", minimum: 0.45, fold: 1.45),
                        little: originalShape("little", minimum: 0.45, fold: 1.45))
                    check(PointingObservation(landmarks: points, aspect: aspect).pose == expected,
                        "Extracted camera classification preserves the original geometry and confidence boundaries")
                }
            }
        }

        var malformed = landmarks(click: true)
        malformed["middleTip"]?.x = .nan
        check(PointingObservation(landmarks: malformed, aspect: 1).pose == nil, "Malformed coordinates remain uncertain")
        var invalid = Trace(fps: 30)
        invalid.frame(malformed)
        let roundTrip = try PracticeDiagnosticSession.decode(invalid.recorder.session!.encoded())
        check(roundTrip.entries[0].input?.landmarks["middleTip"]?.x.isNaN == true,
            "Invalid numeric observations remain replayable without invalid JSON")
        var wrongVersion = roundTrip
        wrongVersion.schemaVersion = 99
        do {
            _ = try PracticeDiagnosticReplay.run(wrongVersion)
            check(false, "Unknown schemas must not be interpreted as current recordings")
        } catch PracticeDiagnosticError.unsupportedSession {}
        print("Passed \(checks) practice diagnostics, privacy, recording, and replay checks.")
    }
}
