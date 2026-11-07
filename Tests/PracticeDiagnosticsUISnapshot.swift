import AppKit

@main
struct PracticeDiagnosticsUISnapshot {
    enum State: String, CaseIterable { case preview, recording, canceled, success, saved, paused, advanced, noData }

    static func main() throws {
        _ = NSApplication.shared
        if !FeatureFlags.diagnostics {
            precondition(PracticeDiagnosticsView(preview: NSView()) == nil,
                "Disabled diagnostics must not construct a screen or any entry controls")
            print("Passed default-off diagnostics screen and entry-point check.")
            return
        }
        let destination = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/diagnostics-ui")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for width in [920.0, 720.0] {
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                for state in State.allCases {
                    try render(width: width, appearance: appearance, state: state, destination: destination)
                }
            }
        }
        print("Passed 32 guided camera-test layout, result, privacy, and control states.")
    }

    static func sample(_ state: State) -> (PracticeDiagnosticRecorder, PracticeDiagnosticInput, PracticeDiagnosticOutcome) {
        var engine = InteractionEngine()
        let settings = InteractionSettings(mode: .pointAndHold)
        engine.configure(settings)
        let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
        var cursor = CGPoint(x: 720, y: 450)
        var recorder = PracticeDiagnosticRecorder()
        if state != .preview {
            recorder.start(width: 1440, height: 900, settings: settings, now: 0, intent: .click)
        }
        var input = PracticeDiagnosticInput(timestamp: 0, now: 0.01, aspect: 4 / 3, landmarks: [:], handSide: "right")
        var outcome = PracticeDiagnosticOutcome(engine: engine, step: InteractionStep(destination: .practice), pose: nil)
        let count = state == .noData ? 0 : ((state == .success || state == .saved) ? 50 : 25)
        for frame in 0..<count {
            var landmarks: [String: HandLandmark] = [:]
            let open = state == .preview || frame < 9
            for (i, finger) in ["index", "middle", "ring", "little"].enumerated() {
                let x = 0.4 + Double(i) * 0.07
                landmarks[finger + "MCP"] = HandLandmark(x: x, y: 0.6, confidence: 0.94)
                landmarks[finger + "PIP"] = HandLandmark(x: x, y: 0.5, confidence: 0.91)
                landmarks[finger + "Tip"] = HandLandmark(x: x, y: open || i < 2 ? 0.4 : 0.47, confidence: 0.89)
            }
            if state == .canceled && frame == count - 1 { landmarks["middlePIP"]?.confidence = 0.59 }
            input = PracticeDiagnosticInput(timestamp: Double(frame) / 30, now: Double(frame) / 30 + 0.01,
                aspect: 4 / 3, landmarks: landmarks, handSide: "right", fiveFingerPinchRatio: 1.2)
            let observation = PointingObservation(landmarks: landmarks, aspect: input.aspect)
            let step = engine.process(index: observation.indexPoint, pinchRatio: nil,
                timestamp: input.timestamp, now: input.now, bounds: bounds, running: true, trusted: false,
                destination: .practice, cursorPosition: cursor, handSide: "right",
                pointingPose: observation.pose, fiveFingerPinchRatio: input.fiveFingerPinchRatio)
            if let location = step.location { cursor = location }
            outcome = PracticeDiagnosticOutcome(engine: engine, step: step, pose: observation.pose)
            recorder.record(input, outcome: outcome, frameInterval: 1 / 30, movement: 0.003, destination: .practice)
            precondition(step.systemLocation == nil && !step.systemClick && !step.systemRightClick,
                "Camera-test samples cannot produce system input")
        }
        if state != .recording && state != .advanced {
            recorder.stop(state == .paused ? .paused : .manual)
        }
        return (recorder, input, outcome)
    }

    static func render(width: Double, appearance: NSAppearance.Name, state: State, destination: URL) throws {
        let preview = NSView()
        let hand = NSImageView(image: NSImage(systemSymbolName: "hand.raised", accessibilityDescription: "Synthetic preview; camera off") ?? NSImage())
        hand.symbolConfiguration = .init(pointSize: 80, weight: .regular)
        hand.contentTintColor = .secondaryLabelColor
        hand.translatesAutoresizingMaskIntoConstraints = false
        preview.addSubview(hand)
        NSLayoutConstraint.activate([
            hand.centerXAnchor.constraint(equalTo: preview.centerXAnchor),
            hand.centerYAnchor.constraint(equalTo: preview.centerYAnchor),
            hand.widthAnchor.constraint(equalToConstant: 90),
            hand.heightAnchor.constraint(equalToConstant: 100)
        ])
        guard let diagnostics = PracticeDiagnosticsView(preview: preview) else {
            preconditionFailure("Enabled diagnostics must construct the test screen")
        }
        precondition(!diagnostics.showsAdvanced, "Technical measurements must be collapsed by default")
        precondition(diagnostics.selectedIntent == .click, "The simple camera test defaults to one left click")
        let (recorder, input, outcome) = sample(state)
        let running = state == .preview || recorder.isRecording
        diagnostics.updateRecorder(recorder, canRecord: true, cameraRunning: running, hasSavedFile: state == .saved)
        diagnostics.setAdvanced(state == .advanced)
        diagnostics.update(input: running ? input : nil, outcome: outcome, frameInterval: 1 / 30, movement: 0.003)
        if state == .saved { diagnostics.showNotice("Saved hand-mouse-diagnostics.json. Attach this file to your chat if you want help. Nothing was uploaded.") }
        if state == .noData { diagnostics.showNotice("Camera unavailable. Go back to the app and check Camera Settings under Permissions.") }

        let guide = GestureGuideView(frame: .zero)
        guide.setDemoTimeForRendering(0)
        let practice = PracticeView(frame: .zero)
        let feedback = ClickFeedbackView(frame: .zero)
        let start = NSButton(title: "Start", target: nil, action: nil)
        start.bezelStyle = .rounded; start.controlSize = .large
        let practiceButton = NSButton(title: "Practice", target: nil, action: nil)
        practiceButton.bezelStyle = .rounded
        let cameraTest = NSButton(title: "Camera test", target: nil, action: nil)
        cameraTest.bezelStyle = .rounded; cameraTest.controlSize = .large
        let settingsButton = NSButton(title: "Settings", target: nil, action: nil)
        settingsButton.bezelStyle = .rounded
        let unused = (0..<3).map { _ -> NSView in
            let view = NSTextField(labelWithString: "Hidden setup control")
            view.isHidden = true
            return view
        }
        let normalPreview = NSView()
        normalPreview.isHidden = true
        let content = LaunchContentView(title: NSTextField(labelWithString: "Hand Mouse"),
            cameraStatus: NSTextField(labelWithString: "Camera off"), start: start,
            practiceButton: practiceButton, settingsButton: settingsButton, guide: guide,
            preview: normalPreview, feedback: feedback, practice: practice,
            setupDisclosure: unused[0], setupRows: unused[1], settingsRows: unused[2],
            diagnostics: diagnostics, cameraTestButton: cameraTest)
        let size = NSSize(width: width, height: width == 720 ? 650 : 720)
        content.appearance = NSAppearance(named: appearance)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false; window.backgroundColor = .clear
        window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.setFrame(NSRect(origin: .zero, size: size), display: false)
        window.contentView = content
        try UIRenderSupport.prepare(content, size: size)
        content.layoutSubtreeIfNeeded()
        precondition(!content.showsDiagnostics && diagnostics.isHidden, "The test screen opens only through its entry point")
        precondition(!cameraTest.isHiddenOrHasHiddenAncestor && content.bounds.contains(cameraTest.convert(cameraTest.bounds, to: content)),
            "The Camera test entry point must be visible without scrolling into Practice")
        content.setDiagnosticsPresented(true)
        content.layoutSubtreeIfNeeded()
        content.layoutSubtreeIfNeeded()
        let context = "\(width) / \(appearance.rawValue) / \(state.rawValue)"
        let visible: (NSView) -> Bool = { !$0.isHiddenOrHasHiddenAncestor }
        let ambiguous = UIRenderSupport.ambiguousViews(in: content).filter(visible)
        precondition(ambiguous.isEmpty, "Ambiguous guided-test layout in \(context): \(ambiguous.map { String(describing: type(of: $0)) })")
        precondition(practice.isHiddenOrHasHiddenAncestor && guide.isHiddenOrHasHiddenAncestor && start.isHiddenOrHasHiddenAncestor,
            "Camera diagnosis must not mix with the practice game, marketing header, or generic Start controls")
        precondition(diagnostics.enclosingScrollView == nil, "The guided test cannot be buried in the main scrolling workspace")
        let buttons = UIRenderSupport.descendants(of: diagnostics).compactMap { $0 as? NSButton }
        let primary = buttons.first { ["Start recording", "Stop & review", "Record another attempt"].contains($0.title) }!
        let save = buttons.first { ["Save results…", "Save another copy…"].contains($0.title) }!
        let back = buttons.first { $0.title == "Back to app" }!
        let advanced = buttons.first { $0.title == "Advanced details (optional)" }!
        precondition(primary.isEnabled && back.isEnabled, "Users must always be able to start/stop or leave the test")
        precondition(save.isEnabled == (recorder.sampleCount > 0 && !recorder.isRecording), "Saving requires a finished recording with samples")
        precondition(save.isHidden == (diagnostics.stage != .review), "Save is introduced only at the result step")
        let actionRects = [primary, save, back].map { $0.convert($0.bounds, to: content) }
        for button in [primary, save, back] where !button.isHidden {
            precondition(button.enclosingScrollView == nil && content.bounds.contains(button.convert(button.bounds, to: content)),
                "Recording/save/navigation controls must stay visible in \(context)")
        }
        if state == .preview || state == .recording {
            let clip = preview.enclosingScrollView!.contentView
            let document = preview.enclosingScrollView!.documentView!
            let cameraRect = preview.convert(preview.bounds, to: document)
            precondition(clip.documentVisibleRect.contains(cameraRect),
                "Camera must fit without scrolling in \(context): camera \(cameraRect), viewport \(clip.documentVisibleRect), panel \(diagnostics.bounds)")
        }
        var actions = 0
        diagnostics.onRecord = { actions += 1 }
        primary.performClick(nil)
        precondition(actions == 1 && recorder.sampleCount == (state == .preview || state == .noData ? 0 : ((state == .success || state == .saved) ? 50 : 25)),
            "View actions are explicit callbacks and rendering cannot record or mutate samples")
        precondition(advanced.state == (state == .advanced ? .on : .off), "Technical detail state must match the disclosure")
        if state == .advanced, let scroll = preview.enclosingScrollView, let document = scroll.documentView {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, document.bounds.height - scroll.contentView.bounds.height)))
            scroll.reflectScrolledClipView(scroll.contentView)
            content.layoutSubtreeIfNeeded()
            precondition([primary, save, back].map { $0.convert($0.bounds, to: content) } == actionRects,
                "Scrolling advanced measurements cannot move recording controls")
        }
        let labels = UIRenderSupport.descendants(of: diagnostics).compactMap { $0 as? NSTextField }.filter(visible).map(\.stringValue)
        if state == .success || state == .saved { precondition(labels.contains("One click detected"), "A successful attempt needs a readable result") }
        if state == .canceled { precondition(labels.contains { $0.contains("middle finger") }, "Cancellation results name the unclear finger") }
        if state == .saved {
            precondition(labels.contains { $0.contains("Saved file kept on this Mac") } &&
                !labels.contains { $0.contains("Unsaved results disappear") }, "Saved results must not be presented as unsaved")
        }
        let theme = appearance == .darkAqua ? "dark" : "light"
        try UIRenderSupport.writePNG(of: content, size: size,
            to: destination.appendingPathComponent("camera-test-\(Int(width))-\(theme)-\(state.rawValue).png"))
        content.setDiagnosticsPresented(false)
        content.layoutSubtreeIfNeeded()
        precondition(diagnostics.isHidden && !cameraTest.isHiddenOrHasHiddenAncestor,
            "Leaving the test restores the normal workspace without losing its entry point")
        window.close()
    }
}
