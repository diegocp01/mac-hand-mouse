import Foundation
import CoreGraphics

struct HandLandmark: Codable {
    var x: Double
    var y: Double
    var confidence: Float
    var point: CGPoint { CGPoint(x: x, y: y) }

    static let names = ["wrist", "thumbCMC", "thumbMP", "thumbIP", "thumbTip",
        "indexMCP", "indexPIP", "indexDIP", "indexTip", "middleMCP", "middlePIP", "middleDIP", "middleTip",
        "ringMCP", "ringPIP", "ringDIP", "ringTip", "littleMCP", "littlePIP", "littleDIP", "littleTip"]
}

struct FingerEvidence: Codable {
    enum Issue: String, Codable { case missingJoints, lowConfidence, invalidGeometry, ambiguousShape, recognized }
    let finger: String
    let shape: FingerShape
    let confidence: Float
    let requiredConfidence: Float
    let foldedReachLimit: Double
    let reachRatio: Double?
    let straightness: Double?
    let issue: Issue

    init(finger: String, landmarks: [String: HandLandmark], aspect: Double) {
        self.finger = finger
        let outer = finger == "ring" || finger == "little"
        requiredConfidence = outer ? 0.45 : 0.6
        foldedReachLimit = outer ? 1.45 : 1.2
        let joints = ["Tip", "PIP", "MCP"].map { landmarks[finger + $0] }
        confidence = joints.map { $0?.confidence ?? 0 }.min() ?? 0
        let geometry: ScrollPoseGeometry.Measurement?
        if let tip = joints[0], let pip = joints[1], let base = joints[2] {
            geometry = ScrollPoseGeometry.measure(tip: tip.point, pip: pip.point, base: base.point, aspect: aspect)
        } else { geometry = nil }
        reachRatio = geometry?.reachRatio
        straightness = geometry?.straightness
        if joints.contains(where: { $0 == nil }) {
            shape = .uncertain; issue = .missingJoints
        } else if !joints.allSatisfy({ [requiredConfidence] in ($0?.confidence ?? 0) >= requiredConfidence }) {
            shape = .uncertain; issue = .lowConfidence
        } else if let geometry {
            shape = geometry.shape(foldedReachLimit: foldedReachLimit)
            issue = shape == .uncertain ? .ambiguousShape : .recognized
        } else {
            shape = .uncertain; issue = .invalidGeometry
        }
    }
}

struct PointingObservation {
    let landmarks: [String: HandLandmark]
    let fingers: [FingerEvidence]
    let pose: PointingPose?

    var indexPoint: CGPoint? {
        guard let index = landmarks["indexTip"], index.confidence >= 0.45 else { return nil }
        return index.point
    }

    var hint: String {
        guard indexPoint != nil else { return "Keep your fingers visible" }
        if pose != nil { return "Keep your fingers visible" }
        if fingers[0].shape != .extended { return "Show your index finger clearly" }
        if fingers[1].shape == .uncertain { return "Show your middle finger clearly" }
        return "Keep your curled fingers visible"
    }

    init(landmarks: [String: HandLandmark], aspect: Double) {
        self.landmarks = landmarks
        fingers = ["index", "middle", "ring", "little"].map {
            FingerEvidence(finger: $0, landmarks: landmarks, aspect: aspect)
        }
        if (landmarks["indexTip"]?.confidence ?? 0) >= 0.45 {
            pose = PointingPoseClassifier.classify(index: fingers[0].shape, middle: fingers[1].shape,
                ring: fingers[2].shape, little: fingers[3].shape)
        } else { pose = nil }
    }
}

enum DiagnosticIntent: String, Codable, CaseIterable {
    case free, aim, click, cancel

    var title: String {
        switch self {
        case .free: return "Free test"
        case .aim: return "Aim only"
        case .click: return "One left click"
        case .cancel: return "Cancel a hold"
        }
    }

    var instruction: String {
        switch self {
        case .free: return "Explore comfortable hand positions. This label makes no assumptions about intended clicks."
        case .aim: return "Open your hand and move normally. No click is intended."
        case .click: return "Open your hand, raise index + middle, curl the outer fingers, and hold for one second."
        case .cancel: return "Open your hand, start a two-finger hold, then lower the middle finger before it completes."
        }
    }
}

enum DiagnosticStopReason: String, Codable {
    case manual, paused, practiceFinished, taskChanged, cameraChanged, interactionReset, limit

    var title: String {
        switch self {
        case .manual: return "Stopped"
        case .paused: return "Camera paused"
        case .practiceFinished: return "Practice finished"
        case .taskChanged: return "Practice task changed"
        case .cameraChanged: return "Camera changed"
        case .interactionReset: return "Interaction reset"
        case .limit: return "Recording limit reached"
        }
    }
}

struct PracticeDiagnosticInput: Codable {
    var timestamp: Double
    var now: Double
    var aspect: Double
    var landmarks: [String: HandLandmark]
    var handSide: String?
    var fiveFingerPinchRatio: Double? = nil
    var threeFingerPinchRatio: Double? = nil
}

struct PracticeDiagnosticOutcome: Codable {
    let pose: PointingPose?
    let phase: PointHoldDetector.Phase
    let progress: Double
    let cancellation: PointHoldDetector.Cancellation?
    let blocked: InteractionBlock?
    let click: Bool
    let rightClick: Bool

    init(engine: InteractionEngine, step: InteractionStep, pose: PointingPose?) {
        self.pose = pose
        phase = engine.pointHold.phase
        progress = engine.pointHold.progress
        cancellation = engine.pointHold.lastCancellation
        blocked = step.blocked
        click = step.click
        rightClick = step.rightClick
    }

    func matches(_ other: Self) -> Bool {
        pose == other.pose && phase == other.phase && abs(progress - other.progress) < 1e-6 &&
            cancellation == other.cancellation && blocked == other.blocked && click == other.click && rightClick == other.rightClick
    }
}

struct PracticeDiagnosticEntry: Codable {
    enum Event: String, Codable { case frame, trackingInterrupted }
    let event: Event
    let time: Double
    let attempt: Int
    let intent: DiagnosticIntent
    let input: PracticeDiagnosticInput?
    let fingers: [FingerEvidence]
    let outcome: PracticeDiagnosticOutcome
    let frameInterval: Double?
    let movement: Double?
}

struct PracticeDiagnosticSession: Codable {
    var schemaVersion = 1
    var detector = "pointAndHold-1"
    var width: Double
    var height: Double
    var precisionMode: Bool
    var steadyAim: Bool
    var entries: [PracticeDiagnosticEntry] = []
    var stopReason: DiagnosticStopReason?

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> Self {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        return try decoder.decode(Self.self, from: data)
    }
}

struct PracticeDiagnosticRecorder {
    private(set) var session: PracticeDiagnosticSession?
    private(set) var isRecording = false
    private(set) var attempt = 0
    private(set) var intent: DiagnosticIntent = .free
    private(set) var leftClicks = 0
    private(set) var rightClicks = 0
    private var origin = 0.0
    let maximumSamples: Int
    let maximumDuration: Double
    var sampleCount: Int { session?.entries.count ?? 0 }

    init(maximumSamples: Int = 9_000, maximumDuration: Double = 180) {
        self.maximumSamples = maximumSamples
        self.maximumDuration = maximumDuration
    }

    mutating func start(width: Double, height: Double, settings: InteractionSettings, now: Double, intent: DiagnosticIntent) {
        session = PracticeDiagnosticSession(width: width, height: height,
            precisionMode: settings.precisionMode, steadyAim: settings.steadyAim)
        origin = now; attempt = 1; self.intent = intent
        leftClicks = 0; rightClicks = 0; isRecording = true
    }

    mutating func nextAttempt(intent: DiagnosticIntent) {
        guard isRecording else { return }
        attempt += 1; self.intent = intent
    }

    mutating func record(_ input: PracticeDiagnosticInput, outcome: PracticeDiagnosticOutcome,
                         frameInterval: Double? = nil, movement: Double? = nil, destination: InteractionDestination) {
        guard isRecording, destination == .practice else { return }
        var local = input
        local.timestamp -= origin; local.now -= origin
        local.landmarks = local.landmarks.filter { HandLandmark.names.contains($0.key) }
        local.handSide = ["left", "right"].contains(local.handSide ?? "") ? local.handSide : nil
        append(PracticeDiagnosticEntry(event: .frame, time: local.now, attempt: attempt, intent: intent,
            input: local, fingers: PointingObservation(landmarks: local.landmarks, aspect: local.aspect).fingers,
            outcome: outcome, frameInterval: frameInterval, movement: movement))
    }

    mutating func interrupt(at now: Double, outcome: PracticeDiagnosticOutcome) {
        guard isRecording else { return }
        append(PracticeDiagnosticEntry(event: .trackingInterrupted, time: now - origin, attempt: attempt,
            intent: intent, input: nil, fingers: [], outcome: outcome, frameInterval: nil, movement: nil))
    }

    private mutating func append(_ entry: PracticeDiagnosticEntry) {
        guard entry.time.isFinite, entry.time <= maximumDuration, sampleCount < maximumSamples else {
            stop(.limit); return
        }
        session?.entries.append(entry)
        if entry.outcome.click { leftClicks += 1 }
        if entry.outcome.rightClick { rightClicks += 1 }
        if sampleCount == maximumSamples { stop(.limit) }
    }

    mutating func expire(at now: Double) {
        if isRecording && now - origin >= maximumDuration { stop(.limit) }
    }

    mutating func stop(_ reason: DiagnosticStopReason) {
        guard isRecording else { return }
        isRecording = false; session?.stopReason = reason
    }

    mutating func discard() {
        session = nil; isRecording = false; attempt = 0; leftClicks = 0; rightClicks = 0
    }
}

enum CameraTestPolicy {
    static func usesPracticeOutput(practicing: Bool, presented: Bool) -> Bool { practicing || presented }

    static func allowsCameraToggle(presented: Bool, running: Bool, hasRecording: Bool) -> Bool {
        !presented || running || !hasRecording
    }

    static func shouldStopCamera(presented: Bool, running: Bool, hasRecording: Bool, recording: Bool) -> Bool {
        presented && running && hasRecording && !recording
    }
}

struct DiagnosticGuidance {
    let title: String
    let detail: String

    init(outcome: PracticeDiagnosticOutcome, fingers: [FingerEvidence], intent: DiagnosticIntent) {
        if let blocked = outcome.blocked {
            switch blocked {
            case .missingHand, .acquiring, .differentHand:
                title = "Show one hand to the camera"
                detail = "Keep your palm, fingertips, and knuckles in view. This test does not move your Mac's pointer."
            case .staleFrame:
                title = "Tracking paused briefly"
                detail = "Keep your hand visible and wait for fresh camera updates. No click is pending."
            default:
                title = "The camera test is not ready"
                detail = "Stop and start another recording. No mouse input is sent to other apps."
            }
            return
        }
        if intent == .free {
            title = "Explore comfortable hand positions"
            detail = "This is an ungraded recording. Choose Stop & review when you have captured what you want to inspect."
            return
        }
        if intent == .aim {
            title = outcome.click || outcome.rightClick ? "An unwanted click was detected" : "Move your open hand normally"
            detail = "Do not make a click gesture. When you have tried moving, choose Stop & review."
            return
        }
        switch outcome.phase {
        case .needsMove:
            title = "Open your hand first"
            detail = "Show your palm and fingers clearly to prepare the detector. Then try the gesture once."
        case .ready:
            let unclear = fingers.filter { $0.shape == .uncertain }.map { "\($0.finger) finger" }
            if outcome.pose == nil && !unclear.isEmpty {
                title = "Keep your fingers in view"
                detail = "The detector cannot clearly read your \(unclear.joined(separator: " and ")). Adjust your hand until it is clear."
            } else {
                title = "Now raise just two fingers"
                detail = "Keep index and middle up. Curl ring and little fingers toward your palm, then hold still for one second."
            }
        case .holding:
            if intent == .cancel {
                title = "Now lower your middle finger"
                detail = "Release before the hold completes. Then choose Stop & review to check that no click was detected."
            } else {
                title = "Keep those two fingers raised"
                detail = String(format: "Hold still: %.1f seconds left. The bar shows what the detector has actually observed.",
                    max(0, 1 - outcome.progress))
            }
        case .clicked:
            title = "Click detected"
            detail = "Open your hand again, then choose Stop & review. There is no Send button to aim at in this test."
        }
    }
}

struct DiagnosticResult {
    enum Verdict { case confirmed, notConfirmed, unexpected, noData, recorded }
    let verdict: Verdict
    let title: String
    let explanation: String
    let nextStep: String
    let leftClicks: Int
    let rightClicks: Int
    let frameCount: Int

    init(session: PracticeDiagnosticSession) {
        let frames = session.entries.filter { $0.event == .frame }
        frameCount = frames.count
        leftClicks = frames.filter { $0.outcome.click }.count
        rightClicks = frames.filter { $0.outcome.rightClick }.count
        let counts = "Detected \(leftClicks) left click\(leftClicks == 1 ? "" : "s") and \(rightClicks) right click\(rightClicks == 1 ? "" : "s")."
        let usable = frames.contains { entry in
            guard entry.outcome.blocked == nil, let index = entry.input?.landmarks["indexTip"] else { return false }
            return index.confidence >= 0.45 && index.x.isFinite && index.y.isFinite &&
                (0...1).contains(index.x) && (0...1).contains(index.y)
        }
        guard usable else {
            verdict = .noData
            title = frameCount == 0 ? "No camera samples were recorded" : "No usable hand sample"
            explanation = frameCount == 0
                ? "The recording did not receive camera data. Check camera permission and try again."
                : "Camera updates arrived, but the detector did not get a clear, usable hand sample. Updates may have been unclear or delayed."
            nextStep = "Try again with one hand, good light, and your fingertips and knuckles in view."
            return
        }
        let intents = Set(frames.map { $0.intent.rawValue })
        let attempts = Set(frames.map(\.attempt))
        let intent = frames.first?.intent ?? .free
        if intents.count != 1 || attempts.count != 1 || intent == .free {
            verdict = .recorded; title = "Recording captured"
            explanation = counts + " This is a free test or contains multiple labeled attempts, so it is not graded as one click."
            nextStep = "Save the JSON to keep it or share it for analysis. Detection thresholds stayed the same."
            return
        }
        if rightClicks > 0 || (intent == .click ? leftClicks > 1 : leftClicks > 0) {
            verdict = .unexpected
            title = rightClicks > 0 ? "A right click was detected" : "Extra clicks were detected"
            explanation = counts + " That does not match the selected goal: \(intent.title.lowercased())."
            nextStep = "Save this recording for analysis. If you made more than one attempt, try a separate one-attempt recording."
            return
        }
        if intent == .click && leftClicks == 1 || intent == .aim && leftClicks == 0 {
            verdict = .confirmed
            title = intent == .click ? "One click detected" : "No unwanted clicks detected"
            explanation = counts + " This recording matched your selected goal."
            nextStep = "Save the results if you want to keep or share them. Detection thresholds stayed the same."
            return
        }
        let held = frames.contains { $0.outcome.phase == .holding }
        var cancellation: PracticeDiagnosticEntry?
        var previous: PracticeDiagnosticEntry?
        for entry in session.entries {
            if previous?.outcome.phase == .holding, entry.outcome.phase != .holding,
               !entry.outcome.click, entry.outcome.cancellation != nil {
                cancellation = entry
            }
            previous = entry
        }
        if intent == .cancel && cancellation != nil {
            verdict = .confirmed; title = "The hold ended without a click"
            explanation = counts + " " + Self.cancellationDescription(cancellation!)
            nextStep = "Save the recording if you want to keep or share it. Detection thresholds stayed the same."
            return
        }
        verdict = .notConfirmed
        title = "No click was confirmed"
        if let cancellation {
            explanation = Self.cancellationDescription(cancellation)
        } else if held {
            explanation = "The recording stopped before a complete one-second hold was observed. This does not prove the gesture failed."
        } else if frames.contains(where: { $0.outcome.pose == .click }) && !frames.contains(where: { $0.outcome.phase == .ready }) {
            explanation = "The click pose was seen before the detector was ready. Begin with an open hand briefly, then raise just index and middle."
        } else {
            explanation = "No two-finger hold started in this recording. The detector did not confirm the click pose."
        }
        nextStep = "Try once more with index and middle raised and ring and little fingers curled. Or save this recording so someone can inspect the evidence."
    }

    private static func cancellationDescription(_ entry: PracticeDiagnosticEntry) -> String {
        switch entry.outcome.cancellation {
        case .uncertainPose:
            let fingers = entry.fingers.filter { $0.shape == .uncertain }.map { "\($0.finger) finger" }
            return fingers.isEmpty
                ? "The detector could not reliably read the finger pose, so it canceled the hold."
                : "The detector could not clearly read your \(fingers.joined(separator: " and ")) during the hold, so it canceled the click."
        case .releasedPose:
            return "The fingers returned to an aiming pose before the one-second hold completed."
        case .movement:
            return "The tracked index fingertip moved too far during the hold, so the detector canceled it."
        case .frameGap, .trackingInterrupted, .invalidTime:
            return "Hand tracking was interrupted or delayed during the hold, so the detector canceled the click."
        case .invalidPoint:
            return "The detector lost a usable index-fingertip position during the hold."
        case .competingGesture:
            return "Another gesture took priority and interrupted the click hold."
        case .clicksDisabled:
            return "Click detection was disabled before the hold completed."
        case nil:
            return "The hold did not complete."
        }
    }
}

enum PracticeDiagnosticError: Error { case unsupportedSession }

enum PracticeDiagnosticReplay {
    struct Report {
        var frames = 0
        var leftClicks = 0
        var rightClicks = 0
        var mismatches = 0
        var missedClickAttempts = 0
        var falseClickAttempts = 0

        var summary: String {
            "Replayed \(frames) frames through PointingObservation and InteractionEngine (practice only).\n" +
            "Left clicks: \(leftClicks); right clicks: \(rightClicks); decision mismatches: \(mismatches).\n" +
            "Tagged click attempts with no left click: \(missedClickAttempts).\n" +
            "Tagged aim/cancel attempts with a click: \(falseClickAttempts).\n" +
            "Attempt results depend on your labels; replay does not rerun Vision or validate physical tracking."
        }
    }

    static func run(_ session: PracticeDiagnosticSession) throws -> Report {
        guard session.schemaVersion == 1, session.detector == "pointAndHold-1",
              session.width.isFinite, session.height.isFinite, session.width > 1, session.height > 1 else {
            throw PracticeDiagnosticError.unsupportedSession
        }
        var engine = InteractionEngine()
        engine.configure(InteractionSettings(mode: .pointAndHold,
            precisionMode: session.precisionMode, steadyAim: session.steadyAim))
        let bounds = CGRect(x: 0, y: 0, width: session.width, height: session.height)
        var cursor = CGPoint(x: bounds.midX, y: bounds.midY)
        var report = Report()
        var attempts: [Int: (intent: DiagnosticIntent, left: Int, right: Int)] = [:]
        for entry in session.entries {
            let outcome: PracticeDiagnosticOutcome
            switch entry.event {
            case .trackingInterrupted:
                engine.trackingInterrupted()
                outcome = PracticeDiagnosticOutcome(engine: engine,
                    step: InteractionStep(blocked: .staleFrame, destination: .practice), pose: nil)
            case .frame:
                guard let input = entry.input else { throw PracticeDiagnosticError.unsupportedSession }
                let observation = PointingObservation(landmarks: input.landmarks, aspect: input.aspect)
                let step = engine.process(index: observation.indexPoint, pinchRatio: nil,
                    timestamp: input.timestamp, now: input.now, bounds: bounds, running: true, trusted: false,
                    destination: .practice, cursorPosition: cursor, handSide: input.handSide,
                    pointingPose: observation.pose, fiveFingerPinchRatio: input.fiveFingerPinchRatio,
                    threeFingerPinchRatio: input.threeFingerPinchRatio)
                if let location = step.location { cursor = location }
                outcome = PracticeDiagnosticOutcome(engine: engine, step: step, pose: observation.pose)
                report.frames += 1
                var attempt = attempts[entry.attempt] ?? (entry.intent, 0, 0)
                if outcome.click { report.leftClicks += 1; attempt.left += 1 }
                if outcome.rightClick { report.rightClicks += 1; attempt.right += 1 }
                attempts[entry.attempt] = attempt
            }
            if !outcome.matches(entry.outcome) { report.mismatches += 1 }
        }
        report.missedClickAttempts = attempts.values.filter { $0.intent == .click && $0.left == 0 }.count
        report.falseClickAttempts = attempts.values.filter {
            ($0.intent == .aim || $0.intent == .cancel) && $0.left + $0.right > 0
        }.count
        return report
    }
}
