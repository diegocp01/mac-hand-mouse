import AppKit
import AVFoundation
import Vision
import ApplicationServices

final class PreviewView: NSView {
    let preview: AVCaptureVideoPreviewLayer
    private let skeleton = CAShapeLayer()
    private let guide = CAShapeLayer()
    private var points: [VNHumanHandPoseObservation.JointName: CGPoint] = [:]
    private var aspect: CGFloat = 4 / 3
    private let placeholder = NSTextField(wrappingLabelWithString: "")
    private let reticle = StandbyReticleView(frame: .zero)

    init(session: AVCaptureSession) {
        preview = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = StartupStyle.background.cgColor
        layer?.borderColor = StartupStyle.accent.withAlphaComponent(0.2).cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 16
        layer?.masksToBounds = true
        preview.videoGravity = .resizeAspect
        layer?.addSublayer(preview)
        skeleton.strokeColor = NSColor.systemMint.cgColor
        skeleton.fillColor = NSColor.systemMint.cgColor
        skeleton.lineWidth = 2
        layer?.addSublayer(skeleton)
        guide.strokeColor = NSColor.white.withAlphaComponent(0.35).cgColor
        guide.fillColor = nil
        guide.lineDashPattern = [6, 6]
        layer?.addSublayer(guide)
        placeholder.textColor = .white
        placeholder.font = .systemFont(ofSize: 15, weight: .medium)
        placeholder.alignment = .center
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholder)
        reticle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(reticle)
        NSLayoutConstraint.activate([
            placeholder.centerXAnchor.constraint(equalTo: centerXAnchor),
            reticle.centerXAnchor.constraint(equalTo: centerXAnchor),
            reticle.centerYAnchor.constraint(equalTo: centerYAnchor),
            reticle.widthAnchor.constraint(equalToConstant: 140),
            reticle.heightAnchor.constraint(equalToConstant: 140),
            placeholder.topAnchor.constraint(equalTo: reticle.bottomAnchor, constant: 10),
            placeholder.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.8)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func layout() {
        super.layout()
        preview.frame = bounds
        drawHand()
    }
    func update(_ frame: HandFrame?, phase: PinchPhase = .waitingForOpen, clicked: Bool = false) {
        if let connection = preview.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        points = frame?.points ?? [:]
        if let frame { aspect = frame.aspect }
        let color: NSColor = clicked ? .white : (phase == .confirming || phase == .held ? .systemCyan : .systemMint)
        skeleton.strokeColor = color.cgColor
        skeleton.fillColor = color.cgColor
        drawHand()
    }
    func showPlaceholder(_ text: String?) {
        placeholder.stringValue = text ?? ""
        placeholder.isHidden = text == nil
        reticle.isHidden = text == nil
        guide.isHidden = text != nil
    }
    private func drawHand() {
        // Match the actual capture format, including cameras that deliver 16:9.
        let rect = HandGeometry.fittedRect(in: bounds, aspect: aspect)
        func pixel(_ p: CGPoint) -> CGPoint { CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height) }
        let path = CGMutablePath()
        let chains: [[VNHumanHandPoseObservation.JointName]] = [
            [.wrist, .thumbCMC, .thumbMP, .thumbIP, .thumbTip],
            [.wrist, .indexMCP, .indexPIP, .indexDIP, .indexTip],
            [.wrist, .middleMCP, .middlePIP, .middleDIP, .middleTip],
            [.wrist, .ringMCP, .ringPIP, .ringDIP, .ringTip],
            [.wrist, .littleMCP, .littlePIP, .littleDIP, .littleTip]]
        for chain in chains {
            for pair in zip(chain, chain.dropFirst()) {
                if let a = points[pair.0], let b = points[pair.1] {
                    path.move(to: pixel(a)); path.addLine(to: pixel(b))
                }
            }
        }
        for point in points.values {
            let p = pixel(point)
            path.addEllipse(in: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6))
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        skeleton.path = path
        guide.isHidden = !placeholder.isHidden
        guide.path = CGPath(roundedRect: rect.insetBy(dx: rect.width * GestureTuning.softInset, dy: rect.height * GestureTuning.softInset),
                            cornerWidth: 10, cornerHeight: 10, transform: nil)
        CATransaction.commit()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var practicingForward = false
    private var lastCameraSource: String?
    private let practiceForward = NSButton(title: "Practice (optional)", target: nil, action: nil)
    private let forwardInstructions = NSTextField(wrappingLabelWithString: "")
    private var forwardControls: NSStackView!
    private let practice = ForwardPracticeView()
    private var practiceMessage = ""
    private var practiceMessageUntil = 0.0
    private let camera = HandCamera()
    private var window: NSWindow!
    private var preview: PreviewView!
    private let titleLabel = NSTextField(labelWithString: "Hand Mouse")
    private let permissionStep = SetupStepView(number: "01", title: "Permissions")
    private let cameraStep = SetupStepView(number: "02", title: "Camera")
    private let practiceStep = SetupStepView(number: "03", title: "Pointer")
    private let optionsToggle = NSButton(title: "Gesture settings", target: nil, action: nil)
    private var optionsRows: NSStackView!
    private let feedback = ClickFeedbackView(frame: .zero)
    private let cursorFeedback = CursorFeedback()
    private let cameraStatus = NSTextField(labelWithString: "Camera off")
    private var setupRows: NSStackView!
    private let setupToggle = NSButton(title: "", target: nil, action: nil)
    private var lastFrameTime = 0.0
    private var cameraReady = false
    private var previouslyTrusted: Bool?
    private var cameraMenuItem: NSMenuItem!
    private let permissionStatus = NSTextField(wrappingLabelWithString: "")
    private let toggle = NSButton(title: "Start camera", target: nil, action: nil)
    private let control = NSButton(checkboxWithTitle: "Move pointer", target: nil, action: nil)
    private let allowClicks = NSButton(checkboxWithTitle: "Allow clicks", target: nil, action: nil)
    private let clickModeControl = NSSegmentedControl(labels: ["Pinch", "Point forward"], trackingMode: .selectOne, target: nil, action: nil)
    private let sensitivity = NSSegmentedControl(labels: ["Precise", "Balanced", "Easy"], trackingMode: .selectOne, target: nil, action: nil)
    private let clickTest = NSButton(title: "Test click: 0", target: nil, action: nil)
    private let pinchFeelLabel = NSTextField(labelWithString: "Pinch feel")
    private let clickModeLabel = NSTextField(labelWithString: "Click with")
    private var statusItem: NSStatusItem!
    private var running = false
    private var engine = InteractionEngine()
    private let dwellDuration = NSSegmentedControl(labels: ["0.65 s", "1 s", "1.5 s"], trackingMode: .selectOne, target: nil, action: nil)
    private let dwellDurationLabel = NSTextField(labelWithString: "Hold time")
    private let displayStatus = NSTextField(labelWithString: "")
    private var lastClickLocation: CGPoint?
    private var lastAnnouncement: String?
    private var lastAnnouncementTime = -Double.infinity
    private var clickMode: ClickMode = .pinch
    private var previewPhase: PinchPhase {
        if clickMode == .forward {
            switch engine.forward.phase {
            case .confirming, .holding: return .confirming
            case .clicked: return .held
            case .ready: return .ready
            case .needsNeutral: return .waitingForOpen
            }
        }
        return engine.pinch.phase
    }
    private var clickedUntil = 0.0
    private var testClicks = 0
    private var targetDisplay = CGMainDisplayID()
    private var timer: Timer?
    private var globalKey: Any?
    private var localKey: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        // Set the running app's Dock image explicitly as well as the bundle icon.
        if let iconURL = Bundle.main.url(forResource: "HandMouse", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
        let appMenu = NSMenu()
        let root = NSMenuItem(); appMenu.addItem(root)
        let submenu = NSMenu(); root.submenu = submenu
        submenu.addItem(withTitle: "Quit Hand Mouse", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        NSApp.mainMenu = appMenu

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 720),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Hand Mouse"
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = StartupStyle.background
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 620, height: 540)
        window.center()
        let content = NSView(); window.contentView = content
        content.wantsLayer = true
        content.layer?.backgroundColor = StartupStyle.background.cgColor

        titleLabel.font = .systemFont(ofSize: 30, weight: .medium)
        preview = PreviewView(session: camera.session)
        preview.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            preview.heightAnchor.constraint(equalTo: preview.widthAnchor, multiplier: 0.43)
        ])
        cameraStatus.font = .systemFont(ofSize: 12, weight: .semibold)
        cameraStatus.textColor = StartupStyle.accent
        permissionStatus.font = .systemFont(ofSize: 11)
        permissionStatus.textColor = .secondaryLabelColor

        toggle.target = self; toggle.action = #selector(toggleCamera)
        toggle.bezelStyle = .rounded
        toggle.bezelColor = StartupStyle.accent
        toggle.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: nil)
        toggle.imagePosition = .imageLeading
        if #available(macOS 11.0, *) { toggle.controlSize = .large }
        toggle.keyEquivalent = "\r"

        control.toolTip = "Move your index finger to move the pointer."
        control.state = .on; control.target = self; control.action = #selector(controlChanged)
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "allowClicks") == nil, let legacy = defaults.object(forKey: "allowPinchClicks") as? Bool {
            defaults.set(legacy, forKey: "allowClicks")
        }
        allowClicks.state = (defaults.object(forKey: "allowClicks") as? Bool ?? false) ? .on : .off
        allowClicks.target = self; allowClicks.action = #selector(allowClicksChanged)

        let permissions = NSButton(title: "Enable Accessibility", target: self, action: #selector(enableAccessibility))
        permissions.bezelStyle = .rounded
        let cameraSettings = NSButton(title: "Camera Settings", target: self, action: #selector(openCameraSettings))
        cameraSettings.bezelStyle = .rounded
        let reveal = NSButton(title: "Show in Finder", target: self, action: #selector(revealApp))
        reveal.bezelStyle = .rounded

        let savedSensitivity = defaults.object(forKey: "clickSensitivity") as? Int ?? 1
        sensitivity.selectedSegment = min(2, max(0, savedSensitivity))
        sensitivity.target = self; sensitivity.action = #selector(sensitivityChanged)
        dwellDuration.selectedSegment = min(2, max(0, defaults.object(forKey: "dwellDurationPreset") as? Int ?? 0))
        dwellDuration.target = self; dwellDuration.action = #selector(dwellDurationChanged)
        dwellDuration.setAccessibilityLabel("Forward click hold duration")
        dwellDuration.toolTip = "How long to hold the forward pose after it is recognized. Moving normally never starts this timer."
        sensitivityChanged()
        let savedMode = defaults.string(forKey: "clickMode") ?? ClickMode.pinch.rawValue
        clickMode = ClickMode.restored(savedMode)
        if savedMode == "dwell" {
            // Preserve the one-time migration from automatic dwell clicking.
            allowClicks.state = .off
            defaults.set(false, forKey: "allowClicks")
            defaults.set(clickMode.rawValue, forKey: "clickMode")
        }
        clickModeControl.selectedSegment = clickMode == .forward ? 1 : 0
        clickModeControl.target = self; clickModeControl.action = #selector(clickModeChanged)
        clickTest.target = self; clickTest.action = #selector(testClick)
        clickTest.bezelStyle = .rounded
        for label in [pinchFeelLabel, clickModeLabel, dwellDurationLabel] {
            label.font = .systemFont(ofSize: 12, weight: .medium)
            label.textColor = .secondaryLabelColor
        }

        let setupRow = NSStackView(views: [permissions, cameraSettings, reveal])
        setupRow.spacing = 10
        setupRows = StartupStyle.column([permissionStatus, setupRow], spacing: 8)
        setupToggle.setButtonType(.pushOnPushOff)
        setupToggle.bezelStyle = .disclosure
        setupToggle.setAccessibilityLabel("Permissions and setup")
        setupToggle.target = self; setupToggle.action = #selector(toggleSetup)
        let cameraPermission = AVCaptureDevice.authorizationStatus(for: .video)
        setupToggle.state = AXIsProcessTrusted() && cameraPermission != .denied && cameraPermission != .restricted ? .off : .on
        toggleSetup()
        let setupLabel = NSTextField(labelWithString: "Permissions")
        setupLabel.font = .systemFont(ofSize: 12, weight: .medium)
        setupLabel.setAccessibilityElement(false)
        let setupDisclosure = NSStackView(views: [setupToggle, setupLabel])
        setupDisclosure.spacing = 6
        let primaryRow = NSStackView(views: [cameraStatus, NSView(), toggle])
        primaryRow.spacing = 12
        let steps = NSStackView(views: [permissionStep, cameraStep, practiceStep])
        steps.distribution = .fillEqually; steps.spacing = 10
        let modeRow = NSStackView(views: [clickModeLabel, clickModeControl])
        modeRow.spacing = 12
        let tuningRow = NSStackView(views: [pinchFeelLabel, sensitivity, dwellDurationLabel, dwellDuration])
        tuningRow.spacing = 10
        let hint = NSTextField(wrappingLabelWithString: "Esc pauses · On-device")
        hint.font = .systemFont(ofSize: 11); hint.textColor = StartupStyle.muted
        displayStatus.font = .systemFont(ofSize: 11)
        displayStatus.textColor = StartupStyle.muted
        practiceForward.target = self; practiceForward.action = #selector(toggleForwardPractice)
        practiceForward.bezelStyle = .rounded
        practiceForward.keyEquivalent = "p"; practiceForward.keyEquivalentModifierMask = [.command, .shift]
        forwardInstructions.font = .systemFont(ofSize: 12)
        forwardInstructions.textColor = StartupStyle.muted
        let setupActions = NSStackView(views: [practiceForward])
        setupActions.spacing = 10
        forwardControls = StartupStyle.column([forwardInstructions, setupActions], spacing: 6)
        optionsToggle.setButtonType(.pushOnPushOff)
        optionsToggle.bezelStyle = .inline
        optionsToggle.target = self; optionsToggle.action = #selector(toggleOptions)
        optionsToggle.setAccessibilityLabel("Gesture settings")
        optionsToggle.state = clickMode == .forward ? .on : .off
        optionsRows = StartupStyle.column([modeRow, tuningRow, forwardControls, displayStatus])
        toggleOptions()
        let controls = NSStackView(views: [control, NSView(), allowClicks])
        controls.spacing = 12
        let actions = NSStackView(views: [optionsToggle, NSView(), clickTest])
        actions.spacing = 12
        let header = StartupStyle.column([
            titleLabel, primaryRow
        ], spacing: 8)
        header.translatesAutoresizingMaskIntoConstraints = false
        let stack = StartupStyle.column([
            steps, setupDisclosure, setupRows, preview, feedback, practice,
            controls, actions, optionsRows
        ], spacing: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        // Keep Start/Pause and the escape hint visible while the rest scrolls on small displays.
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let document = TopAlignedDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        hint.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(header); content.addSubview(scroll); content.addSubview(hint)
        document.addSubview(stack)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            header.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            header.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 16),
            scroll.bottomAnchor.constraint(equalTo: hint.topAnchor, constant: -10),
            hint.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            hint.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            hint.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -12),
            primaryRow.widthAnchor.constraint(equalTo: header.widthAnchor)
        ])
        for view in [steps, setupRows!, permissionStatus, preview!, feedback, practice, controls, actions,
                     optionsRows!, forwardControls!, forwardInstructions] {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        practice.heightAnchor.constraint(equalToConstant: 180).isActive = true

        refreshClickChrome()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "hand.point.up.left", accessibilityDescription: "Hand Mouse")
        let menu = NSMenu()
        menu.addItem(withTitle: "Show Hand Mouse", action: #selector(showWindow), keyEquivalent: "").target = self
        cameraMenuItem = menu.addItem(withTitle: "Start camera", action: #selector(toggleCamera), keyEquivalent: "")
        cameraMenuItem.target = self
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        camera.onFrame = { [weak self] frame in self?.handle(frame) }
        camera.onStatus = { [weak self] _ in
            guard let self, self.running else { return }
            guard !self.cameraReady else { return }
            self.cameraReady = true
            self.lastFrameTime = ProcessInfo.processInfo.systemUptime
            self.cameraStatus.stringValue = "Looking for hand"
            self.preview.showPlaceholder(nil)
            self.showFeedback("Show one hand", "Palm visible, inside the guide.")
        }
        camera.onError = { [weak self] message in
            guard let self, self.running else { return }
            self.pause()
            self.showFeedback("Camera unavailable", message)
            self.setupToggle.state = .on; self.toggleSetup()
        }
        localKey = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.pause(); return nil }; return event
        }
        globalKey = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.pause() }
        }
        let watchdog = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(watchdog, forMode: .common)
        timer = watchdog
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(environmentPaused(_:)), name: name, object: nil)
        }
        configureInteraction(); refresh(); showWindow(); updateDisplayStatus()

    }

    @objc private func toggleSetup() {
        setupRows.isHidden = setupToggle.state == .off
        setupToggle.setAccessibilityExpanded(setupToggle.state == .on)
    }

    @objc private func toggleOptions() {
        optionsRows.isHidden = optionsToggle.state == .off
        optionsToggle.title = optionsToggle.state == .on ? "▾ Gesture settings" : "▸ Gesture settings"
        optionsToggle.setAccessibilityExpanded(optionsToggle.state == .on)
    }

    private func refreshSetupSteps(trusted: Bool) {
        let authorization = AVCaptureDevice.authorizationStatus(for: .video)
        permissionStep.update(complete: trusted, active: !trusted,
                              detail: trusted ? "Accessibility enabled" : "Enable Accessibility")
        cameraStep.update(complete: running && cameraReady, active: trusted && !cameraReady,
                          detail: authorization == .denied || authorization == .restricted
                            ? "Open Camera Settings"
                            : (running ? (cameraReady ? "Camera is on" : "Starting camera…") : "Start camera"))
        practiceStep.update(complete: false, active: cameraReady,
                            detail: !cameraReady ? "Show one hand"
                                : (allowClicks.state == .on ? "Clicks on · Aim, then click" : "Move your index · Clicks off"))
    }

    private func configureInteraction() {
        engine.configure(InteractionSettings(mode: clickMode, allowClicks: practicingForward || allowClicks.state == .on,
            pointerEnabled: practicingForward || control.state == .on,
            pinchThreshold: [0.34, 0.42, 0.50][min(2, max(0, sensitivity.selectedSegment))],
            dwellSeconds: [0.65, 1.0, 1.5][min(2, max(0, dwellDuration.selectedSegment))]))
    }

    private func updateDisplayStatus() {
        guard let window else { return }
        let screen = running ? NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == targetDisplay
        } : window.screen
        displayStatus.stringValue = (practicingForward ? "Practice display: " : (running ? "Controlling: " : "Target display: ")) + (screen?.localizedName ?? "Unavailable")
    }

    @objc private func environmentPaused(_ notification: Notification) {
        guard running else { return }
        pause()
        showFeedback("Paused for system change", "Camera and mouse control stopped. Start camera to resume when ready.")
    }

    func applicationDidChangeScreenParameters(_ notification: Notification) {
        if running {
            pause()
            showFeedback("Displays changed · Paused", "Place this window on your target display, then start the camera again.")
        }
        updateDisplayStatus()
    }
    func windowDidChangeScreen(_ notification: Notification) { updateDisplayStatus() }


    private func showFeedback(_ title: String, _ detail: String, progress: Double? = nil, clicked: Bool = false) {
        // The standby preview already communicates idle state; retain actionable errors.
        feedback.isHidden = !running && (title == "Ready when you are" || title == "Paused")
        feedback.update(title: title, detail: detail, fraction: progress, clicked: clicked)
        let announcement: String? = clicked ? "Click sent" : (["Looking for your hand", "Tracking interrupted", "Tracking delayed", "Enable Accessibility", "Paused"].contains(title) ? title : nil)
        if let announcement, lastAnnouncement != announcement {
            let now = ProcessInfo.processInfo.systemUptime
            // A click or explicit pause must not disappear behind the camera-status throttle.
            if announcement == "Click sent" || announcement == "Paused" || now - lastAnnouncementTime > 0.4 {
                NSAccessibility.post(element: feedback, notification: .announcementRequested,
                    userInfo: [.announcement: announcement, .priority: NSAccessibilityPriorityLevel.low.rawValue])
                lastAnnouncementTime = now
                lastAnnouncement = announcement
            }
        } else if announcement == nil {
            lastAnnouncement = nil
        }
    }

    private func clearClickFeedback() {
        cursorFeedback.hide(); clickedUntil = 0; lastClickLocation = nil
    }

    private func readyFeedback() {
        clearClickFeedback()
        if !running {
            showFeedback("Ready when you are", "Start the camera, then show one hand with your palm visible.")
        } else if control.state != .on {
            showFeedback("Preview only", "Pointer and clicks off.")
        } else if allowClicks.state != .on {
            showFeedback("Clicks off", "Point to move.")
        } else {
            showFeedback(clickMode == .forward ? "Point forward to click" : "Pinch to click",
                         clickMode == .forward ? "Aim normally, point toward the camera, then hold. Pull back to cancel." : "Touch thumb + index, then release.")
        }
    }

    private func refreshClickChrome() {
        let clicksOn = allowClicks.state == .on
        configureInteraction()
        clickModeControl.isEnabled = true
        clickModeLabel.textColor = .secondaryLabelColor
        sensitivity.isEnabled = clickMode == .pinch
        pinchFeelLabel.isHidden = clickMode != .pinch
        sensitivity.isHidden = clickMode != .pinch
        pinchFeelLabel.textColor = sensitivity.isEnabled ? .secondaryLabelColor : .tertiaryLabelColor
        dwellDuration.isHidden = clickMode != .forward
        dwellDurationLabel.isHidden = clickMode != .forward
        let learning = practicingForward
        clickTest.isEnabled = clicksOn && !learning
        allowClicks.isEnabled = !learning
        control.isEnabled = !learning
        updateForwardPractice(); updateDisplayStatus()
    }

    private func updateForwardPractice() {
        guard forwardControls != nil else { return }
        forwardControls.isHidden = clickMode != .forward
        practice.isHidden = !practicingForward
        preview.isHidden = practicingForward
        practiceForward.title = practicingForward ? "Finish practice" : "Practice (optional)"
        practiceForward.isEnabled = true
        forwardInstructions.stringValue = practicingForward
            ? "Practice only · Aim at green, point forward, then hold. \(practice.hits) targets hit. Finish whenever you like."
            : "Point forward to click · No pose setup needed · Experimental"
    }

    @objc private func toggleForwardPractice() {
        if practicingForward { finishForwardPractice(); return }
        clickMode = .forward; clickModeControl.selectedSegment = 1
        UserDefaults.standard.set(clickMode.rawValue, forKey: "clickMode")
        allowClicks.state = .off; UserDefaults.standard.set(false, forKey: "allowClicks")
        practicingForward = true
        engine.reset(); practice.reset(); clearClickFeedback(); practiceMessageUntil = 0
        if !running { toggleCamera() }
        refreshClickChrome()
    }

    private func finishForwardPractice() {
        practicingForward = false
        engine.reset(); clearClickFeedback(); practice.reset()
        allowClicks.state = .off; UserDefaults.standard.set(false, forKey: "allowClicks")
        refreshClickChrome()
        showFeedback("Practice finished", "Turn on Allow clicks when you want real clicks. No pose setup is needed.")
    }

    private func handleForwardPractice(_ frame: HandFrame, now: Double) {
        guard frame.timestamp.isFinite, frame.timestamp <= now, now - frame.timestamp < 0.20 else {
            engine.trackingInterrupted(); cursorFeedback.hide(); return
        }
        lastFrameTime = now; cameraReady = true; preview.showPlaceholder(nil); preview.update(frame)
        cameraStatus.stringValue = "Practice only"
        cursorFeedback.hide()
        // This branch ends before OS dispatch. Simulation also exposes no system output.
        let screen = CGDisplayBounds(targetDisplay)
        let step = engine.process(index: frame.points[.indexTip], pinchRatio: frame.pinchRatio,
            forwardPose: frame.forwardPose, timestamp: frame.timestamp, now: now,
            bounds: screen, running: running, trusted: false, destination: .practice)
        let simulatedPoint = step.location.map {
            CGPoint(x: ($0.x - screen.minX) / screen.width * practice.bounds.width,
                    y: ($0.y - screen.minY) / screen.height * practice.bounds.height)
        }
        let hit = practice.update(point: simulatedPoint, progress: engine.forward.progress, clicked: step.click)
        if step.click {
            practiceMessage = hit ? "Target hit ✓ · Pull back, then aim at the next target." : "Missed the target · Pull back, aim again, then point forward."
            practiceMessageUntil = now + 1.2
            updateForwardPractice()
        }
        showFeedback("Practice only · No system clicks", now < practiceMessageUntil ? practiceMessage
            : "Move the dot onto green. Point forward to start the timer; pull back to cancel.",
            progress: engine.forward.phase == .holding ? engine.forward.progress : nil)
    }

    @objc private func showWindow() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc private func toggleCamera() {
        if running { pause(); return }
        running = true; cameraReady = false
        engine.reset(); clearClickFeedback()
        lastFrameTime = ProcessInfo.processInfo.systemUptime
        // Lock to the display containing this window for the duration of this session.
        if let number = window.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            targetDisplay = CGDirectDisplayID(number.uint32Value)
        }
        configureInteraction(); updateDisplayStatus()
        toggle.title = "Pause camera"
        toggle.image = NSImage(systemSymbolName: "pause.fill", accessibilityDescription: nil)
        cameraMenuItem.title = "Pause camera"
        cameraStatus.stringValue = "Starting camera…"
        preview.showPlaceholder("Allow camera access.")
        showFeedback("Starting camera", "Show one hand, palm visible.")
        camera.start()
    }
    @objc private func pause() {
        running = false; camera.stop(); engine.reset(); clickedUntil = 0; preview.update(nil)
        clearClickFeedback(); cameraReady = false
        cameraStatus.stringValue = "Camera off"
        preview.showPlaceholder("")
        toggle.title = "Start camera"
        toggle.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: nil)
        cameraMenuItem.title = "Start camera"
        showFeedback("Paused", "Use your mouse normally. Start the camera when you are ready.")
        updateDisplayStatus()
        if practicingForward { finishForwardPractice() }
    }
    @objc private func controlChanged() { configureInteraction(); engine.reset(); readyFeedback() }
    @objc private func allowClicksChanged() {
        UserDefaults.standard.set(allowClicks.state == .on, forKey: "allowClicks")
        engine.reset(); clickedUntil = 0
        refreshClickChrome(); readyFeedback(); refresh()
    }
    @objc private func clickModeChanged() {
        if practicingForward { finishForwardPractice() }
        clickMode = clickModeControl.selectedSegment == 1 ? .forward : .pinch
        UserDefaults.standard.set(clickMode.rawValue, forKey: "clickMode")
        engine.reset(); clickedUntil = 0
        refreshClickChrome(); readyFeedback(); refresh()
    }
    @objc private func sensitivityChanged() {
        let selected = min(2, max(0, sensitivity.selectedSegment))
        UserDefaults.standard.set(selected, forKey: "clickSensitivity")
        configureInteraction(); engine.reset(); readyFeedback()
    }
    @objc private func dwellDurationChanged() {
        UserDefaults.standard.set(min(2, max(0, dwellDuration.selectedSegment)), forKey: "dwellDurationPreset")
        configureInteraction(); engine.reset(); clearClickFeedback()
        refreshClickChrome(); readyFeedback()
    }
    @objc private func testClick() {
        testClicks += 1
        clickTest.title = "Test click: \(testClicks) ✓"
    }
    @objc private func revealApp() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }
    @objc private func enableAccessibility() {
        // Granting permission must not start controlling System Settings mid-setup.
        if running { pause() }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    @objc private func openCameraSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
    }
    private func refresh() {
        let trusted = AXIsProcessTrusted()
        if previouslyTrusted == true && !trusted {
            setupToggle.state = .on; toggleSetup()
            engine.reset(); clearClickFeedback()
        }
        previouslyTrusted = trusted
        refreshSetupSteps(trusted: trusted)
        if running && practicingForward {
            // Optional practice needs no Accessibility access and has no OS output path.
            if cameraReady && ProcessInfo.processInfo.systemUptime - lastFrameTime > GestureTuning.trackingGraceSeconds {
                engine.trackingInterrupted(); cursorFeedback.hide()
                _ = practice.update(point: nil, progress: 0, clicked: false)
            }
            return
        }
        if trusted {
            if control.state != .on {
                permissionStatus.stringValue = "Accessibility enabled · Preview only"
            } else if allowClicks.state != .on {
                permissionStatus.stringValue = "Accessibility enabled"
            } else if clickMode == .forward {
                permissionStatus.stringValue = "Accessibility enabled"
            } else {
                permissionStatus.stringValue = "Accessibility enabled"
            }
        } else {
            permissionStatus.stringValue = "Enable Hand Mouse in Accessibility."
        }
        guard running else { return }
        let now = ProcessInfo.processInfo.systemUptime
        // Camera health must stay accurate in preview mode and before Accessibility is enabled.
        if cameraReady && now - lastFrameTime > GestureTuning.trackingGraceSeconds {
            engine.trackingInterrupted(); clearClickFeedback(); preview.update(nil)
            cameraStatus.stringValue = "Tracking interrupted"
            showFeedback("Tracking interrupted", "Countdown canceled. Pause and restart the camera if tracking does not resume.")
            return
        }
        if !trusted || control.state != .on {
            engine.reset(); clearClickFeedback()
            showFeedback(trusted ? "Preview only" : "Enable Accessibility",
                         trusted ? "Pointer and clicks off." : "Open Permissions to enable control.")
            return
        }
        if allowClicks.state != .on {
            clearClickFeedback()
        }
    }
    private func handle(_ frame: HandFrame) {
        guard running else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if frame.timestamp.isFinite, frame.timestamp <= now, now - frame.timestamp < 0.20 {
            let sourceChanged = lastCameraSource != nil && lastCameraSource != frame.source
            lastCameraSource = frame.source
            if sourceChanged {
                engine.reset(); clearClickFeedback()
                showFeedback("Camera changed", "Point normally to resume. The gesture adapts automatically.")
                return
            }
        }
        if practicingForward { handleForwardPractice(frame, now: now); return }
        guard CGDisplayIsActive(targetDisplay) != 0 else {
            pause(); showFeedback("Display disconnected", "Choose a connected display and start the camera again.")
            return
        }
        let step = engine.process(index: frame.points[.indexTip], pinchRatio: frame.pinchRatio, forwardPose: frame.forwardPose,
                                  timestamp: frame.timestamp, now: now, bounds: CGDisplayBounds(targetDisplay),
                                  running: running, trusted: AXIsProcessTrusted())
        if let blocked = step.blocked {
            clearClickFeedback()
            switch blocked {
            case .staleFrame:
                preview.update(nil)
                cameraStatus.stringValue = "Tracking delayed"
                showFeedback("Tracking delayed", "Countdown canceled. Hold still briefly to reacquire your hand.")
            case .invalidDisplay:
                pause(); showFeedback("Display unavailable", "Choose a connected display, then start camera.")
            case .permission, .previewOnly:
                if frame.timestamp.isFinite, frame.timestamp <= now, now - frame.timestamp < 0.20 {
                    lastFrameTime = now; cameraReady = true; preview.showPlaceholder(nil); preview.update(frame)
                    cameraStatus.stringValue = frame.points[.indexTip] == nil
                        ? "Looking for hand" : "Hand tracked"
                }
                showFeedback(blocked == .permission ? "Enable Accessibility" : "Preview only",
                    blocked == .permission ? "Open Permissions to enable control." : "Pointer and clicks off.")
            case .missingHand:
                lastFrameTime = now; cameraReady = true; preview.showPlaceholder(nil); preview.update(frame)
                cameraStatus.stringValue = "Looking for hand"
                showFeedback("Looking for your hand", "Show your index finger and palm.")
            case .paused: break
            }
            return
        }
        guard let location = step.systemLocation else { return }
        lastFrameTime = now; cameraReady = true; preview.showPlaceholder(nil)
        cameraStatus.stringValue = "Hand tracked"
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: location, mouseButton: .left)?.post(tap: .cghidEventTap)
        let clicksAllowed = engine.settings.allowClicks
        if step.systemClick {
            guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: location, mouseButton: .left),
                  let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: location, mouseButton: .left) else {
                clearClickFeedback()
                showFeedback("Click unavailable", "No click was sent. Move or release your pinch to try again.")
                return
            }
            down.setIntegerValueField(.mouseEventClickState, value: 1)
            up.setIntegerValueField(.mouseEventClickState, value: 1)
            down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
            clickedUntil = now + 0.35
            lastClickLocation = location
        }
        let clicked = now < clickedUntil
        preview.update(frame, phase: previewPhase, clicked: clicked)
        if !clicksAllowed {
            cursorFeedback.hide()
            showFeedback("Clicks off", "Point to move.")
        } else if clicked {
            showFeedback("Clicked ✓", clickMode == .forward ? "Return to your movement pose before pointing forward again." : "Separate thumb + index.", clicked: true)
            cursorFeedback.show(at: lastClickLocation ?? location, displayID: targetDisplay, progress: 1, remaining: 0, clicked: true)
        } else if clickMode == .forward && frame.forwardPose == nil {
            cursorFeedback.hide()
            showFeedback("Finger pose unclear", "Countdown canceled. Keep your palm visible and turn your index slightly so its joints are visible.")
        } else if clickMode == .forward {
            switch engine.forward.phase {
            case .ready:
                cursorFeedback.hide()
                showFeedback("Move to aim", "Point toward the camera when you want to click. Staying still does nothing.")
            case .needsNeutral:
                cursorFeedback.hide()
                showFeedback("Point to move", "Keep your index extended while aiming, then point toward the camera to click.")
            case .confirming:
                cursorFeedback.hide()
                showFeedback("Forward gesture detected", "Keep that pose briefly. Pull back or move sideways to cancel.")
            case .holding:
                let remaining = engine.forward.remainingSeconds
                showFeedback(String(format: "Click in %.1f s", max(0.1, remaining)),
                    "Hold your forward pose · Pull back to cancel · Esc pauses", progress: engine.forward.progress)
                cursorFeedback.show(at: location, displayID: targetDisplay, progress: engine.forward.progress,
                                    remaining: remaining, clicked: false)
            case .clicked:
                cursorFeedback.hide()
                showFeedback("Pull back to click again", "Return to your pointing pose.")
            }
        } else {
            cursorFeedback.hide()
            if frame.pinchRatio == nil {
                showFeedback("Pointing", "Show your thumb and palm to enable a pinch click.")
            } else {
                switch engine.pinch.phase {
                case .waitingForOpen: showFeedback("Open your hand", "Separate thumb + index to get ready.")
                case .ready: showFeedback("Ready to pinch", "Aim, then touch thumb + index.")
                case .confirming: showFeedback("Pinch detected", "Hold your fingertips together briefly.")
                case .held: showFeedback("Release your pinch", "Separate thumb + index.")
                }
            }
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { pause(); return true }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func applicationWillTerminate(_ notification: Notification) {
        cursorFeedback.hide(); camera.stop(); timer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        if let globalKey { NSEvent.removeMonitor(globalKey) }
        if let localKey { NSEvent.removeMonitor(localKey) }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
