import AppKit

@main
struct PracticeDiagnosticsUISnapshot {
    enum State: String, CaseIterable { case collapsed, holding, canceled, recording, paused }

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
        print("Passed 20 camera-free diagnostics layout, control, and appearance states.")
    }

    static func render(width: Double, appearance: NSAppearance.Name, state: State, destination: URL) throws {
        let preview = NSImageView(image: NSImage(systemSymbolName: "hand.raised", accessibilityDescription: "Synthetic preview; camera off") ?? NSImage())
        preview.symbolConfiguration = .init(pointSize: 70, weight: .regular)
        preview.contentTintColor = .secondaryLabelColor
        guard let diagnostics = PracticeDiagnosticsView(preview: preview) else {
            preconditionFailure("Enabled diagnostics must construct the test screen")
        }
        precondition(!diagnostics.isExpanded, "Diagnostics must not expand or record automatically")
        diagnostics.setExpanded(state != .collapsed)
        var engine = InteractionEngine()
        let settings = InteractionSettings(mode: .pointAndHold)
        engine.configure(settings)
        let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
        var cursor = CGPoint(x: 720, y: 450)
        var step = InteractionStep(destination: .practice)
        for frame in 1...24 {
            step = engine.process(index: CGPoint(x: 0.4, y: 0.4), pinchRatio: nil,
                timestamp: Double(frame) / 30, now: Double(frame) / 30 + 0.01,
                bounds: bounds, running: true, trusted: false, destination: .practice,
                cursorPosition: cursor, handSide: "right", pointingPose: frame < 9 ? .move : .click,
                fiveFingerPinchRatio: 1.2)
            if let location = step.location { cursor = location }
        }
        var landmarks: [String: HandLandmark] = [:]
        for (i, finger) in ["index", "middle", "ring", "little"].enumerated() {
            let x = 0.4 + Double(i) * 0.07
            landmarks[finger + "MCP"] = HandLandmark(x: x, y: 0.6, confidence: 0.94)
            landmarks[finger + "PIP"] = HandLandmark(x: x, y: 0.5, confidence: 0.91)
            landmarks[finger + "Tip"] = HandLandmark(x: x, y: i < 2 ? 0.4 : 0.47, confidence: 0.89)
        }
        if state == .canceled {
            landmarks["middlePIP"]?.confidence = 0.59
            step = engine.process(index: CGPoint(x: 0.4, y: 0.4), pinchRatio: nil,
                timestamp: 0.84, now: 0.85, bounds: bounds, running: true, trusted: false,
                destination: .practice, cursorPosition: cursor, handSide: "right", pointingPose: nil)
        }
        let input = PracticeDiagnosticInput(timestamp: 0.84, now: 0.85, aspect: 4 / 3, landmarks: landmarks, handSide: "right")
        let outcome = PracticeDiagnosticOutcome(engine: engine, step: step,
            pose: state == .canceled ? nil : .click)
        var recorder = PracticeDiagnosticRecorder()
        if state == .recording || state == .paused {
            recorder.start(width: 1440, height: 900, settings: settings, now: 0, intent: .click)
            recorder.record(input, outcome: outcome, frameInterval: 1 / 30, movement: 0.003, destination: .practice)
            if state == .paused { recorder.stop(.paused) }
        }
        diagnostics.update(input: state == .paused ? nil : input, outcome: outcome, frameInterval: 1 / 30, movement: 0.003)
        diagnostics.updateRecorder(recorder, canRecord: state != .paused)

        let guide = GestureGuideView(frame: .zero)
        guide.setDemoTimeForRendering(0)
        let practice = PracticeView(frame: .zero)
        practice.isHidden = state == .paused
        let feedback = ClickFeedbackView(frame: .zero)
        let start = NSButton(title: state == .paused ? "Start" : "Pause", target: nil, action: nil)
        start.bezelStyle = .rounded
        start.keyEquivalent = "\r"
        let practiceButton = NSButton(title: state == .paused ? "Practice" : "Finish practice", target: nil, action: nil)
        practiceButton.bezelStyle = .rounded
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
            cameraStatus: NSTextField(labelWithString: state == .paused ? "Camera off" : "Practice only"),
            start: start, practiceButton: practiceButton, settingsButton: settingsButton, guide: guide,
            preview: normalPreview, feedback: feedback, practice: practice,
            setupDisclosure: unused[0], setupRows: unused[1], settingsRows: unused[2], diagnostics: diagnostics)
        let size = NSSize(width: width, height: width == 720 ? 650 : 720)
        content.appearance = NSAppearance(named: appearance)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = content
        try UIRenderSupport.prepare(content, size: size)
        content.layoutSubtreeIfNeeded()
        let context = "\(width) / \(appearance.rawValue) / \(state.rawValue)"
        let visible: (NSView) -> Bool = { !$0.isHiddenOrHasHiddenAncestor }
        let ambiguous = UIRenderSupport.ambiguousViews(in: content).filter(visible)
        precondition(ambiguous.isEmpty, "Ambiguous diagnostics layout in \(context): \(ambiguous.map { String(describing: type(of: $0)) })")
        precondition(content.bounds.contains(start.convert(start.bounds, to: content)), "Pause must stay visible in \(context)")
        let buttons = UIRenderSupport.descendants(of: diagnostics).compactMap { $0 as? NSButton }
        let record = buttons.first { $0.title == "Record session" || $0.title == "Stop recording" }!
        let export = buttons.first { $0.title == "Export JSON…" }!
        let next = buttons.first { $0.title == "Next attempt" }!
        precondition(record.isEnabled == (state != .paused), "Record availability must follow click practice")
        precondition(export.isEnabled == (state == .paused), "Export requires a stopped, retained recording")
        precondition(next.isEnabled == (state == .recording), "Attempt markers require an active recording")
        if state != .collapsed {
            for control in UIRenderSupport.descendants(of: diagnostics).compactMap({ $0 as? NSControl }).filter(visible) {
                let rect = control.convert(control.bounds, to: diagnostics)
                precondition(rect.width > 0 && rect.height > 0 && diagnostics.bounds.insetBy(dx: -1, dy: -1).contains(rect),
                    "Clipped diagnostics control \(type(of: control)) in \(context): \(rect)")
                if let label = control as? NSTextField, label.maximumNumberOfLines == 2 {
                    precondition(label.bounds.height >= 25, "Both finger evidence lines must fit in \(context)")
                }
            }
            var actions = 0
            diagnostics.onRecord = { actions += 1 }
            if record.isEnabled { record.performClick(nil); precondition(actions == 1, "Record action must be explicit") }
            precondition(engine.pointHold.progress == outcome.progress, "Rendering cannot advance or reset the detector")
        }
        content.layoutSubtreeIfNeeded()
        let top = NSRect(x: 0, y: max(0, diagnostics.bounds.height - 260), width: diagnostics.bounds.width,
                         height: min(260, diagnostics.bounds.height))
        diagnostics.scrollToVisible(top)
        content.layoutSubtreeIfNeeded()
        let theme = appearance == .darkAqua ? "dark" : "light"
        let url = destination.appendingPathComponent("diagnostics-\(Int(width))-\(theme)-\(state.rawValue).png")
        try UIRenderSupport.writePNG(of: content, size: size, to: url)
        print(url.path)
        if state == .recording {
            diagnostics.scrollToVisible(NSRect(x: 0, y: 0, width: diagnostics.bounds.width, height: min(260, diagnostics.bounds.height)))
            try UIRenderSupport.writePNG(of: content, size: size,
                to: destination.appendingPathComponent("diagnostics-\(Int(width))-\(theme)-recording-controls.png"))
        }
        window.close()
    }
}
