import AppKit

final class PracticeDiagnosticsView: NSView {
    enum Stage { case preview, recording, review }
    var onRecord: (() -> Void)?
    var onExport: (() -> Void)?
    var onClose: (() -> Void)?
    var onRevealSavedFile: (() -> Void)?
    private(set) var stage: Stage = .preview
    private(set) var showsAdvanced = false

    private let goals: [DiagnosticIntent] = [.click, .aim, .cancel, .free]
    private let step = NSTextField(labelWithString: "1 · Record   →   2 · Review   →   3 · Save if needed")
    private let heading = NSTextField(wrappingLabelWithString: "Test your two-finger click")
    private let introduction = NSTextField(wrappingLabelWithString:
        "Record one attempt to see what the detector recognizes. This does not calibrate or change any settings.")
    private let liveTitle = NSTextField(wrappingLabelWithString: "Check your hand in the preview")
    private let liveDetail = NSTextField(wrappingLabelWithString:
        "Open your hand. When you are ready, start recording and try one click. You do not need to aim at a button.")
    private let progress = NSProgressIndicator()
    private let resultTitle = NSTextField(wrappingLabelWithString: "")
    private let resultDetail = NSTextField(wrappingLabelWithString: "")
    private let nextStep = NSTextField(wrappingLabelWithString: "")
    private let savedFile = NSButton(title: "Show saved file", target: nil, action: nil)
    private let advancedToggle = NSButton(checkboxWithTitle: "Advanced details (optional)", target: nil, action: nil)
    private let intentPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let fingerLabels = (0..<4).map { _ in NSTextField(wrappingLabelWithString: "Waiting for hand") }
    private let technicalState = NSTextField(wrappingLabelWithString: "No observations yet.")
    private let timing = NSTextField(wrappingLabelWithString: "")
    private let notice = NSTextField(wrappingLabelWithString: "")
    private let primary = NSButton(title: "Start recording", target: nil, action: nil)
    private let save = NSButton(title: "Save results…", target: nil, action: nil)
    private let back = NSButton(title: "Back to app", target: nil, action: nil)
    private let privacy = NSTextField(wrappingLabelWithString: "Local camera test · No system mouse input · Nothing uploaded")
    private let scroll = NSScrollView()
    private var live: NSStackView!
    private var result: NSStackView!
    private var advanced: NSStackView!
    private var displayObserver: NSObjectProtocol?
    private var activeIntent: DiagnosticIntent = .click
    private var reviewedResult: DiagnosticResult?
    private var reviewedSampleCount: Int?

    var selectedIntent: DiagnosticIntent {
        goals[max(0, min(goals.count - 1, intentPicker.indexOfSelectedItem))]
    }

    init?(preview: NSView) {
        guard FeatureFlags.diagnostics else { return nil }
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 20
        setAccessibilityRole(.group)
        setAccessibilityLabel("Guided camera test; no system mouse input")

        step.font = .systemFont(ofSize: 11, weight: .semibold)
        step.textColor = StartupStyle.accent
        heading.font = .systemFont(ofSize: 22, weight: .semibold)
        introduction.font = .systemFont(ofSize: 13)
        introduction.textColor = StartupStyle.muted
        let header = StartupStyle.column([step, heading, introduction], spacing: 5)
        for label in [step, heading, introduction] { label.widthAnchor.constraint(equalTo: header.widthAnchor).isActive = true }

        liveTitle.font = .systemFont(ofSize: 17, weight: .semibold)
        liveDetail.font = .systemFont(ofSize: 13)
        liveDetail.textColor = StartupStyle.muted
        progress.isIndeterminate = false
        progress.minValue = 0; progress.maxValue = 1
        progress.style = .bar
        progress.setAccessibilityLabel("Observed one-second click hold")
        let guidance = StartupStyle.column([liveTitle, liveDetail, progress], spacing: 10)
        guidance.setHuggingPriority(.required, for: .vertical)
        live = NSStackView(views: [preview, guidance])
        live.alignment = .centerY
        live.spacing = 20
        preview.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            preview.widthAnchor.constraint(equalTo: live.widthAnchor, multiplier: 0.46),
            preview.heightAnchor.constraint(equalTo: preview.widthAnchor, multiplier: 0.75),
            guidance.trailingAnchor.constraint(equalTo: live.trailingAnchor),
            progress.heightAnchor.constraint(equalToConstant: 8)
        ])
        for view in [liveTitle, liveDetail, progress] { view.widthAnchor.constraint(equalTo: guidance.widthAnchor).isActive = true }

        resultTitle.font = .systemFont(ofSize: 22, weight: .semibold)
        resultDetail.font = .systemFont(ofSize: 14)
        nextStep.font = .systemFont(ofSize: 13)
        nextStep.textColor = StartupStyle.muted
        savedFile.bezelStyle = .rounded
        savedFile.target = self; savedFile.action = #selector(revealSavedFile)
        result = StartupStyle.column([resultTitle, resultDetail, nextStep, savedFile], spacing: 14)
        for label in [resultTitle, resultDetail, nextStep] { label.widthAnchor.constraint(equalTo: result.widthAnchor).isActive = true }

        advancedToggle.target = self; advancedToggle.action = #selector(toggleAdvanced)
        advancedToggle.setAccessibilityLabel("Show optional technical details and other test goals")
        intentPicker.addItems(withTitles: goals.map(\.title))
        intentPicker.target = self; intentPicker.action = #selector(goalChanged)
        intentPicker.setAccessibilityLabel("Goal for the next recording")
        intentPicker.toolTip = "This labels what you intend. It does not change the detector or relabel an existing recording."
        let goalRow = NSStackView(views: [NSTextField(labelWithString: "Next test goal"), intentPicker, NSView()])
        goalRow.alignment = .centerY; goalRow.spacing = 8
        let legend = NSTextField(wrappingLabelWithString: "Internal measurements for debugging; you do not need to interpret these.")
        legend.font = .systemFont(ofSize: 11)
        legend.textColor = StartupStyle.muted
        for label in fingerLabels + [technicalState, timing] { label.font = .monospacedSystemFont(ofSize: 11, weight: .regular) }
        advanced = StartupStyle.column([goalRow, legend] + fingerLabels + [technicalState, timing], spacing: 8)
        for view in [goalRow, legend] + fingerLabels + [technicalState, timing] {
            view.widthAnchor.constraint(equalTo: advanced.widthAnchor).isActive = true
        }
        notice.font = .systemFont(ofSize: 12, weight: .medium)
        notice.textColor = StartupStyle.accent
        notice.isHidden = true
        let body = StartupStyle.column([live, result, notice, advancedToggle, advanced], spacing: 18)
        let document = TopAlignedDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        body.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(body)
        scroll.documentView = document
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false

        for button in [primary, save, back] {
            button.bezelStyle = .rounded
            button.controlSize = .large
            button.font = .systemFont(ofSize: 13, weight: .medium)
        }
        primary.contentTintColor = StartupStyle.accent
        primary.target = self; primary.action = #selector(recordPressed)
        save.target = self; save.action = #selector(savePressed)
        back.target = self; back.action = #selector(closePressed)
        let actions = NSStackView(views: [primary, save, NSView(), back])
        actions.alignment = .centerY; actions.spacing = 10
        privacy.font = .systemFont(ofSize: 11)
        privacy.textColor = StartupStyle.muted
        let footer = StartupStyle.column([actions, privacy], spacing: 8)
        actions.widthAnchor.constraint(equalTo: footer.widthAnchor).isActive = true
        privacy.widthAnchor.constraint(equalTo: footer.widthAnchor).isActive = true
        for view in [header, scroll, footer] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            header.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            scroll.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 16),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -14),
            footer.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            body.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            body.topAnchor.constraint(equalTo: document.topAnchor, constant: 2),
            body.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -4)
        ])
        let bodyRows: [NSView] = [live, result, notice, advancedToggle, advanced]
        for view in bodyRows { view.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true }
        setAdvanced(false)
        updateRecorder(PracticeDiagnosticRecorder(), canRecord: false, cameraRunning: false)
        displayObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.updateColors() }
        updateColors()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let displayObserver { NSWorkspace.shared.notificationCenter.removeObserver(displayObserver) }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = StartupStyle.surface.cgColor
            layer?.borderColor = StartupStyle.border.cgColor
            layer?.borderWidth = SurfacePreferences.current.increaseContrast ? 1.5 : 0.5
        }
    }

    func setAdvanced(_ visible: Bool) {
        showsAdvanced = visible
        advanced.isHidden = !visible
        advancedToggle.state = visible ? .on : .off
        advancedToggle.setAccessibilityExpanded(visible)
    }

    func update(input: PracticeDiagnosticInput?, outcome: PracticeDiagnosticOutcome,
                frameInterval: Double? = nil, movement: Double? = nil) {
        let observation = PointingObservation(landmarks: input?.landmarks ?? [:], aspect: input?.aspect ?? 1)
        if stage == .recording {
            let guidance = DiagnosticGuidance(outcome: outcome, fingers: observation.fingers, intent: activeIntent)
            liveTitle.stringValue = guidance.title
            liveDetail.stringValue = guidance.detail
            progress.doubleValue = outcome.progress
        }
        guard showsAdvanced else { return }
        for (label, finger) in zip(fingerLabels, observation.fingers) {
            label.stringValue = String(format: "%@: %@ · confidence %.2f / %.2f · reach %@ · straightness %@",
                finger.finger.capitalized, finger.shape.rawValue, finger.confidence, finger.requiredConfidence,
                finger.reachRatio.map { String(format: "%.2f", $0) } ?? "—",
                finger.straightness.map { String(format: "%.2f", $0) } ?? "—")
        }
        technicalState.stringValue = "Pose: \(outcome.pose?.rawValue ?? "uncertain") · State: \(outcome.phase.rawValue)\nLast canceled: \(outcome.cancellation?.title ?? "none")"
        timing.stringValue = "Frame age \(input.map { String(format: "%.0f ms", ($0.now - $0.timestamp) * 1000) } ?? "—") · Gap \(frameInterval.map { String(format: "%.0f ms", $0 * 1000) } ?? "—") · Movement \(movement.map { String(format: "%.3f", $0) } ?? "—")"
    }

    func updateRecorder(_ recorder: PracticeDiagnosticRecorder, canRecord: Bool, cameraRunning: Bool,
                        exporting: Bool = false, hasSavedFile: Bool = false) {
        let nextStage: Stage = recorder.isRecording ? .recording : (recorder.session == nil ? .preview : .review)
        let changed = nextStage != stage
        stage = nextStage
        activeIntent = recorder.isRecording ? recorder.intent : selectedIntent
        primary.title = stage == .recording ? "Stop & review" : (stage == .review ? "Record another attempt" : "Start recording")
        primary.isEnabled = (canRecord || recorder.isRecording) && !exporting
        save.title = hasSavedFile ? "Save another copy…" : "Save results…"
        save.isHidden = stage != .review
        save.isEnabled = recorder.sampleCount > 0 && !recorder.isRecording && !exporting
        back.isEnabled = !exporting
        intentPicker.isEnabled = canRecord && !recorder.isRecording && !exporting
        savedFile.isHidden = !hasSavedFile
        live.isHidden = stage == .review
        result.isHidden = stage != .review
        progress.isHidden = stage != .recording
        switch stage {
        case .preview:
            reviewedResult = nil; reviewedSampleCount = nil
            heading.stringValue = "Test your two-finger click"
            introduction.stringValue = "Input: one hand gesture. Output: a readable result, plus an optional file for debugging. No automatic calibration."
            liveTitle.stringValue = cameraRunning ? "Preview only — not recording" : "Camera is paused"
            liveDetail.stringValue = selectedIntent == .click
                ? "Open your hand. Press Start recording, try one click, then Stop & review. You do not need to aim at a button."
                : selectedIntent.instruction + " Start recording when you are ready, then choose Stop & review."
            step.stringValue = "1 · Record   →   2 · Review   →   3 · Save if needed"
        case .recording:
            reviewedResult = nil; reviewedSampleCount = nil
            heading.stringValue = "Recording one attempt"
            introduction.stringValue = recorder.intent.instruction + " Then choose Stop & review."
            step.stringValue = "1 · Recording locally — your Mac is not being controlled"
            if changed { liveTitle.stringValue = "Open your hand first"; liveDetail.stringValue = recorder.intent.instruction }
        case .review:
            if reviewedSampleCount != recorder.sampleCount || reviewedResult == nil, let session = recorder.session {
                reviewedResult = DiagnosticResult(session: session)
                reviewedSampleCount = recorder.sampleCount
            }
            heading.stringValue = "Your test result"
            introduction.stringValue = "This explains what the detector observed. It does not tune sensitivity or train the detector."
            step.stringValue = hasSavedFile ? "3 · Saved locally — share the file only if you choose" : "2 · Review   →   3 · Save if you want help with a fix"
            resultTitle.stringValue = reviewedResult?.title ?? "No recording yet"
            resultTitle.textColor = reviewedResult?.verdict == .confirmed ? .systemGreen : StartupStyle.text
            resultDetail.stringValue = reviewedResult?.explanation ?? "Start a recording to test the detector."
            nextStep.stringValue = hasSavedFile
                ? "Your JSON is saved. Use Show saved file, then attach that file to your chat if you want help with a fix. It contains numbers, not camera video. Nothing was uploaded."
                : (reviewedResult?.nextStep ?? "") + "\n\nTo get help: save the JSON and attach it to your chat. It contains numbers, not camera video. Nothing is sent automatically."
        }
        if exporting {
            privacy.stringValue = "Saving to the location you selected… No upload is taking place."
        } else if recorder.isRecording {
            privacy.stringValue = "Camera on · Recording numbers in memory · No video, audio, or uploads · Esc stops"
        } else {
            let storage = hasSavedFile ? "Saved file kept on this Mac" : (recorder.session == nil ? "Nothing saved" : "Unsaved results disappear when you quit")
            privacy.stringValue = "\(cameraRunning ? "Camera on; preview only" : "Camera off") · \(storage) · Nothing uploaded"
        }
        if changed {
            layoutSubtreeIfNeeded()
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }

    func showNotice(_ message: String?) {
        notice.stringValue = message ?? ""
        notice.isHidden = message == nil
    }

    @objc private func recordPressed() { onRecord?() }
    @objc private func savePressed() { onExport?() }
    @objc private func closePressed() { onClose?() }
    @objc private func revealSavedFile() { onRevealSavedFile?() }
    @objc private func toggleAdvanced() { setAdvanced(!showsAdvanced) }
    @objc private func goalChanged() {
        if stage == .preview { liveDetail.stringValue = selectedIntent.instruction + " Start recording when you are ready." }
    }
}
