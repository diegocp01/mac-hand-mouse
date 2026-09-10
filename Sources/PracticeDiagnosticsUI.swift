import AppKit

final class PracticeDiagnosticsView: NSView {
    var onExpand: (() -> Void)?
    var onRecord: (() -> Void)?
    var onExport: (() -> Void)?
    var onDiscard: (() -> Void)?
    var onNextAttempt: (() -> Void)?
    var onIntentChange: (() -> Void)?
    private(set) var isExpanded = false
    private let disclosure = NSButton(title: "Show camera diagnostics", target: nil, action: nil)
    private let fingerLabels = (0..<4).map { _ in NSTextField(wrappingLabelWithString: "Waiting for hand") }
    private let state = NSTextField(wrappingLabelWithString: "Start Click Practice to inspect your hand.")
    private let cancellation = NSTextField(wrappingLabelWithString: "Last canceled: none")
    private let timing = NSTextField(wrappingLabelWithString: "Frame age, callback interval, and movement appear here.")
    private let progress = NSProgressIndicator()
    private let intentPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let instruction = NSTextField(wrappingLabelWithString: "")
    private let record = NSButton(title: "Record session", target: nil, action: nil)
    private let nextAttempt = NSButton(title: "Next attempt", target: nil, action: nil)
    private let export = NSButton(title: "Export JSON…", target: nil, action: nil)
    private let discard = NSButton(title: "Discard", target: nil, action: nil)
    private let recordingStatus = NSTextField(wrappingLabelWithString: "Not recording. Nothing is saved automatically.")
    private var body: NSStackView!
    private var live: NSStackView!

    var selectedIntent: DiagnosticIntent {
        DiagnosticIntent.allCases[max(0, min(DiagnosticIntent.allCases.count - 1, intentPicker.indexOfSelectedItem))]
    }

    init(preview: NSView) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.borderWidth = 1
        setAccessibilityRole(.group)
        setAccessibilityLabel("Click practice camera diagnostics")

        disclosure.setButtonType(.pushOnPushOff)
        disclosure.bezelStyle = .rounded
        disclosure.target = self; disclosure.action = #selector(toggleExpanded)
        disclosure.setAccessibilityLabel("Show or hide camera diagnostics")
        let safety = NSTextField(labelWithString: "Practice only · no system input")
        safety.font = .systemFont(ofSize: 11)
        safety.textColor = StartupStyle.muted
        let header = NSStackView(views: [disclosure, NSView(), safety])
        header.alignment = .centerY

        let legend = NSTextField(wrappingLabelWithString: "Finger state · minimum joint confidence / required")
        legend.font = .systemFont(ofSize: 11)
        legend.textColor = StartupStyle.muted
        for label in fingerLabels {
            label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            label.maximumNumberOfLines = 2
        }
        let fingers = StartupStyle.column([legend] + fingerLabels, spacing: 6)
        fingers.setHuggingPriority(.required, for: .vertical)
        live = NSStackView(views: [preview, fingers])
        live.alignment = .centerY
        live.spacing = 16
        progress.isIndeterminate = false
        progress.minValue = 0; progress.maxValue = 100
        progress.style = .bar
        progress.setAccessibilityLabel("Observed two-finger hold progress")
        state.font = .systemFont(ofSize: 12, weight: .medium)
        cancellation.font = .systemFont(ofSize: 11)
        timing.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        timing.textColor = StartupStyle.muted

        intentPicker.addItems(withTitles: DiagnosticIntent.allCases.map(\.title))
        intentPicker.target = self; intentPicker.action = #selector(intentChanged)
        intentPicker.setAccessibilityLabel("Intended gesture for the recorded attempt")
        intentPicker.toolTip = "Choose what you intend, not what the detector sees. Changing this label begins a new recorded attempt."
        nextAttempt.target = self; nextAttempt.action = #selector(advanceAttempt)
        nextAttempt.toolTip = "Mark a new attempt with the same intent. This does not reset the detector."
        let intentRow = NSStackView(views: [NSTextField(labelWithString: "Intent"), intentPicker, nextAttempt, NSView()])
        intentRow.spacing = 8
        intentRow.alignment = .centerY
        instruction.font = .systemFont(ofSize: 12)
        instruction.stringValue = selectedIntent.instruction
        record.target = self; record.action = #selector(toggleRecording)
        record.toolTip = "Start a fresh Click Practice session and record numeric observations in memory. No video or audio."
        export.target = self; export.action = #selector(exportRecording)
        discard.target = self; discard.action = #selector(discardRecording)
        for button in [record, nextAttempt, export, discard] { button.bezelStyle = .rounded }
        let actions = NSStackView(views: [record, export, discard, NSView()])
        actions.spacing = 8
        actions.alignment = .centerY
        recordingStatus.font = .systemFont(ofSize: 11, weight: .medium)
        let privacy = NSTextField(wrappingLabelWithString:
            "Opt-in landmarks and timing only. No images, audio, camera IDs, or uploads. Export saves JSON where you choose. " +
            "Limit: 3 minutes or 9,000 events. Pause or leave Click Practice to stop. Export before quitting.")
        privacy.font = .systemFont(ofSize: 11)
        privacy.textColor = StartupStyle.muted
        body = StartupStyle.column([live, state, progress, cancellation, timing, intentRow, instruction, actions, recordingStatus, privacy], spacing: 10)
        let column = StartupStyle.column([header, body], spacing: 12)
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        let layoutViews: [NSView] = [header, body, live, fingers, preview, progress, intentRow, actions]
        for view in layoutViews { view.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            column.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            column.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            column.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            header.widthAnchor.constraint(equalTo: column.widthAnchor),
            body.widthAnchor.constraint(equalTo: column.widthAnchor),
            preview.widthAnchor.constraint(equalToConstant: 208),
            preview.heightAnchor.constraint(equalToConstant: 156),
            fingers.trailingAnchor.constraint(equalTo: live.trailingAnchor),
            intentPicker.widthAnchor.constraint(equalToConstant: 150)
        ])
        let rows: [NSView] = [live, state, progress, cancellation, timing, intentRow, instruction, actions, recordingStatus, privacy]
        for view in rows { view.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true }
        for label in [legend] + fingerLabels { label.widthAnchor.constraint(equalTo: fingers.widthAnchor).isActive = true }
        setExpanded(false)
        updateRecorder(PracticeDiagnosticRecorder(), canRecord: false)
        updateColors()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = StartupStyle.surface.cgColor
            layer?.borderColor = NSColor.separatorColor.cgColor
        }
    }

    func setExpanded(_ expanded: Bool) {
        isExpanded = expanded
        body.isHidden = !expanded
        disclosure.state = expanded ? .on : .off
        disclosure.title = expanded ? "Hide camera diagnostics" : "Show camera diagnostics"
        disclosure.setAccessibilityExpanded(expanded)
    }

    func update(input: PracticeDiagnosticInput?, outcome: PracticeDiagnosticOutcome,
                frameInterval: Double? = nil, movement: Double? = nil) {
        let observation = PointingObservation(landmarks: input?.landmarks ?? [:], aspect: input?.aspect ?? 1)
        for (label, finger) in zip(fingerLabels, observation.fingers) {
            let reach = finger.reachRatio.map { String(format: "%.2f", $0) } ?? "—"
            let straight = finger.straightness.map { String(format: "%.2f", $0) } ?? "—"
            label.stringValue = String(format: "%@: %@ · %.2f / %.2f\nreach %@ · straight %@",
                finger.finger.capitalized, finger.shape.rawValue, finger.confidence, finger.requiredConfidence, reach, straight)
            label.textColor = finger.shape == .uncertain ? .secondaryLabelColor : StartupStyle.text
            let explanation = "\(finger.issue.rawValue). Confidence is the minimum of tip, middle knuckle, and base; it is not a probability. Extended needs reach > 1.60 and straightness > 0.90; folded needs reach < \(finger.foldedReachLimit)."
            label.toolTip = explanation
            label.setAccessibilityHelp(explanation)
        }
        let phase: String
        switch outcome.phase {
        case .needsMove: phase = "Open hand to prepare"
        case .ready: phase = "Ready"
        case .holding: phase = "Holding"
        case .clicked: phase = "Clicked; reopen before repeating"
        }
        let block = outcome.blocked.map { " · Blocked: \($0.rawValue)" } ?? ""
        state.stringValue = "Pose: \(outcome.pose?.rawValue ?? "uncertain") · \(phase)\(block)"
        progress.doubleValue = outcome.progress * 100
        cancellation.stringValue = "Last canceled: " + (outcome.cancellation?.title ?? "none")
        let age = input.map { String(format: "%.0f ms", ($0.now - $0.timestamp) * 1000) } ?? "—"
        let interval = frameInterval.map { String(format: "%.0f ms", $0 * 1000) } ?? "—"
        let motion = movement.map { String(format: "%.3f", $0) } ?? "—"
        timing.stringValue = "Frame age \(age) · Gap \(interval) · Move \(motion) / 0.025"
    }

    func updateRecorder(_ recorder: PracticeDiagnosticRecorder, canRecord: Bool, exporting: Bool = false) {
        live.isHidden = !canRecord
        record.title = recorder.isRecording ? "Stop recording" : "Record session"
        record.isEnabled = (canRecord || recorder.isRecording) && !exporting
        nextAttempt.isEnabled = recorder.isRecording
        intentPicker.isEnabled = canRecord
        export.isEnabled = recorder.sampleCount > 0 && !recorder.isRecording && !exporting
        discard.isEnabled = recorder.session != nil && !recorder.isRecording && !exporting
        if exporting {
            recordingStatus.stringValue = "Exporting local JSON…"
        } else if recorder.isRecording {
            recordingStatus.stringValue = "Recording in memory · Attempt \(recorder.attempt): \(recorder.intent.title) · \(recorder.sampleCount) events · \(recorder.leftClicks) left / \(recorder.rightClicks) right clicks. Choose Next attempt before repeating."
        } else if let session = recorder.session {
            recordingStatus.stringValue = "\(session.stopReason?.title ?? "Stopped") · \(recorder.sampleCount) events · \(recorder.leftClicks) left / \(recorder.rightClicks) right clicks. Export to keep this session."
        } else {
            recordingStatus.stringValue = "Not recording. Nothing is saved automatically. Record session resets Click Practice; the detector rules stay unchanged."
        }
        if !canRecord {
            state.stringValue = "Start Click Practice to inspect your hand."
            progress.doubleValue = 0
            timing.stringValue = "No live camera observations."
        }
    }

    func showExportResult(_ message: String) { recordingStatus.stringValue = message }

    @objc private func toggleExpanded() { setExpanded(!isExpanded); onExpand?() }
    @objc private func toggleRecording() { onRecord?() }
    @objc private func exportRecording() { onExport?() }
    @objc private func discardRecording() { onDiscard?() }
    @objc private func advanceAttempt() { onNextAttempt?() }
    @objc private func intentChanged() { instruction.stringValue = selectedIntent.instruction; onIntentChange?() }
}
