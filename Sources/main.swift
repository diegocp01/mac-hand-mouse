import AppKit
import AVFoundation
import Vision
import ApplicationServices
import UniformTypeIdentifiers

final class PreviewView: NSView {
    let preview: AVCaptureVideoPreviewLayer
    private let skeleton = CAShapeLayer()
    private let guide = CAShapeLayer()
    var controlRegion = PointerFilter().controlRegion { didSet { drawHand() } }
    private var points: [VNHumanHandPoseObservation.JointName: CGPoint] = [:]
    private var aspect: CGFloat = 4 / 3
    private let placeholder = NSTextField(wrappingLabelWithString: "")
    private let reticle = StandbyReticleView(frame: .zero)

    init(session: AVCaptureSession) {
        preview = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.borderWidth = 1
        layer?.cornerRadius = 18
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
        placeholder.textColor = StartupStyle.muted
        placeholder.font = .systemFont(ofSize: 12, weight: .medium)
        placeholder.alignment = .center
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholder)
        reticle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(reticle)
        NSLayoutConstraint.activate([
            placeholder.centerXAnchor.constraint(equalTo: centerXAnchor),
            reticle.centerXAnchor.constraint(equalTo: centerXAnchor),
            reticle.centerYAnchor.constraint(equalTo: centerYAnchor),
            reticle.widthAnchor.constraint(equalToConstant: 82),
            reticle.heightAnchor.constraint(equalToConstant: 82),
            placeholder.topAnchor.constraint(equalTo: reticle.bottomAnchor, constant: 5),
            placeholder.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.8)
        ])
        updateColors()
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }
    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = (placeholder.isHidden ? NSColor.black : StartupStyle.surface).cgColor
            layer?.borderColor = NSColor.separatorColor.cgColor
        }
    }
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
        updateColors()
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
        let travelRect = CGRect(x: rect.minX + controlRegion.minX * rect.width,
            y: rect.minY + controlRegion.minY * rect.height,
            width: controlRegion.width * rect.width, height: controlRegion.height * rect.height)
        guide.path = CGPath(roundedRect: travelRect, cornerWidth: 10, cornerHeight: 10, transform: nil)
        CATransaction.commit()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var practicing = false
    private var lastCameraSource: String?
    private let forwardInstructions = NSTextField(wrappingLabelWithString: "")
    private var forwardControls: NSStackView!
    private let practice = PracticeView()
    private var practiceCursor: CGPoint?
    private let practiceButton = NSButton(title: "Practice", target: nil, action: nil)
    private var diagnostics: PracticeDiagnosticsView?
    private var diagnosticPreview: PreviewView?
    private var diagnosticsButton: NSButton?
    private var diagnosticsPresented = false
    private var diagnosticSavedURL: URL?
    private var diagnosticRecorder = PracticeDiagnosticRecorder()
    private var diagnosticLastFrame: Double?
    private var diagnosticRenderedAt = -Double.infinity
    private var diagnosticInterrupted = false
    private var exportingDiagnostics = false
    private var diagnosticExportMessage: String?
    private let allowPinchDragging = NSButton(checkboxWithTitle: "Pinch to drag (experimental)", target: nil, action: nil)
    private let allowDragging = NSButton(checkboxWithTitle: "Select text", target: nil, action: nil)
    private let allowScrolling = NSButton(checkboxWithTitle: "Scroll", target: nil, action: nil)
    private let shortcutChoice = NSPopUpButton(frame: .zero, pullsDown: false)
    private let shortcutStatus = NSTextField(wrappingLabelWithString: "")
    private let shortcut = ResumeShortcut()
    private var activation = ActivationPolicy()
    private var practiceMessage = ""
    private var practiceMessageUntil = 0.0
    private let camera = HandCamera()
    private var window: NSWindow!
    private var preview: PreviewView!
    private let titleLabel = NSTextField(labelWithString: "Hand Mouse")
    private let gestureGuide = GestureGuideView(frame: .zero)
    private let startingPoseTitle = "Show your hand to move"
    private let startingPoseDetail = "Keep your hand visible. Move to aim."
    private var latestPointingPose: PointingPose?
    private var latestPointingHint = "Keep your fingers visible"
    private let optionsToggle = NSButton(title: "Settings", target: nil, action: nil)
    private var optionsRows: NSStackView!
    private let feedback = ClickFeedbackView(frame: .zero)
    private let cursorFeedback = CursorFeedback()
    private let cameraStatus = NSTextField(labelWithString: "Camera off")
    private var setupRows: NSStackView!
    private let setupToggle = NSButton(title: "", target: nil, action: nil)
    private let setupLabel = NSTextField(labelWithString: "Permissions")
    private var lastFrameTime = 0.0
    private var cameraReady = false
    private var previouslyTrusted: Bool?
    private var cameraMenuItem: NSMenuItem!
    private let permissionStatus = NSTextField(wrappingLabelWithString: "")
    private let toggle = NSButton(title: "Start", target: nil, action: nil)
    private let control = NSButton(checkboxWithTitle: "Move pointer", target: nil, action: nil)
    private let precisionMode = NSButton(checkboxWithTitle: "Precision", target: nil, action: nil)
    private let steadyAim = NSButton(checkboxWithTitle: "Steady aim", target: nil, action: nil)
    private let allowClicks = NSButton(checkboxWithTitle: "Click", target: nil, action: nil)
    private let clickModeControl = NSSegmentedControl(labels: ["Point and hold"], trackingMode: .selectOne, target: nil, action: nil)
    private let sensitivity = NSSegmentedControl(labels: ["Precise", "Balanced", "Easy"], trackingMode: .selectOne, target: nil, action: nil)
    private let clickTest = NSButton(title: "Test click: 0", target: nil, action: nil)
    private let pinchFeelLabel = NSTextField(labelWithString: "Pinch feel")
    private let clickModeLabel = NSTextField(labelWithString: "Click with")
    private var statusItem: NSStatusItem!
    private var running = false
    private var engine = InteractionEngine()
    private var ownership = HandOwnership()
    private var lastForwardIssue: ForwardPoseIssue?
    private var dragOutput = DragOutput()
    private var dragReleaseEvent: CGEvent?
    private let dwellDuration = NSSegmentedControl(labels: ["0.65 s", "1 s", "1.5 s"], trackingMode: .selectOne, target: nil, action: nil)
    private let dwellDurationLabel = NSTextField(labelWithString: "Hold time")
    private let displayStatus = NSTextField(labelWithString: "")
    private var lastClickLocation: CGPoint?
    private var lastClickWasRight = false
    private var lastAnnouncement: String?
    private var lastAnnouncementTime = -Double.infinity
    private var clickMode: ClickMode = .pointAndHold
    private var previewPhase: PinchPhase {
        if clickMode == .pointAndHold {
            if engine.rightGestureActive {
                return engine.rightPinch.phase == .held ? .held : .confirming
            }
            if engine.scroll.phase != .idle { return .confirming }
            switch engine.pointHold.phase {
            case .needsMove: return .waitingForOpen
            case .ready: return .ready
            case .holding: return .confirming
            case .clicked: return .held
            }
        }
        if clickMode == .twoFingerTap {
            switch engine.tap.phase {
            case .waiting: return .waitingForOpen
            case .ready: return .ready
            case .pressed: return .confirming
            }
        }
        if engine.scroll.phase != .idle { return .confirming }
        if clickMode == .forward {
            switch engine.forward.phase {
            case .confirming, .holding: return .confirming
            case .clicked: return .held
            case .ready: return .ready
            case .needsNeutral: return .waitingForOpen
            }
        }
        if engine.settings.allowPinchDragging {
            switch engine.pinchDrag.phase {
            case .waitingForOpen: return .waitingForOpen
            case .ready: return .ready
            case .confirming: return .confirming
            case .pressed, .dragging: return .held
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
    private var updateMenuItem: NSMenuItem!
    private var checkingForUpdate = false

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
        updateMenuItem = submenu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        updateMenuItem.target = self
        submenu.addItem(NSMenuItem.separator())
        submenu.addItem(withTitle: "Quit Hand Mouse", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        NSApp.mainMenu = appMenu

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 720),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Hand Mouse"
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 720, height: 650)
        window.center()

        preview = PreviewView(session: camera.session)
        preview.translatesAutoresizingMaskIntoConstraints = false
        if FeatureFlags.diagnostics {
            let diagnosticPreview = PreviewView(session: camera.session)
            self.diagnosticPreview = diagnosticPreview
            diagnostics = PracticeDiagnosticsView(preview: diagnosticPreview)
            diagnostics?.onRecord = { [weak self] in self?.toggleDiagnosticRecording() }
            diagnostics?.onExport = { [weak self] in self?.exportDiagnosticRecording() }
            diagnostics?.onClose = { [weak self] in self?.closeDiagnostics() }
            diagnostics?.onRevealSavedFile = { [weak self] in
                if let url = self?.diagnosticSavedURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
            let test = NSButton(title: "Camera test", target: self, action: #selector(openDiagnostics))
            test.bezelStyle = .rounded
            test.controlSize = .large
            test.setAccessibilityLabel("Camera test: diagnose one click without controlling your Mac")
            test.toolTip = "Preview your hand, record one attempt, and see a readable result. Nothing is uploaded."
            diagnosticsButton = test
        }
        cameraStatus.font = .systemFont(ofSize: 11, weight: .medium)
        cameraStatus.textColor = StartupStyle.muted
        permissionStatus.font = .systemFont(ofSize: 11)
        permissionStatus.textColor = .secondaryLabelColor

        toggle.target = self; toggle.action = #selector(toggleCamera)
        toggle.bezelStyle = .rounded
        toggle.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: nil)
        toggle.imagePosition = .imageLeading
        toggle.setAccessibilityLabel("Start camera tracking")
        if #available(macOS 11.0, *) { toggle.controlSize = .large }
        toggle.keyEquivalent = "\r"

        control.toolTip = "Move your index finger to move the pointer."
        control.setAccessibilityLabel("Move pointer with your index finger")
        control.state = .on; control.target = self; control.action = #selector(controlChanged)
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "allowClicks") == nil, let legacy = defaults.object(forKey: "allowPinchClicks") as? Bool {
            defaults.set(legacy, forKey: "allowClicks")
        }
        allowClicks.state = ClickPreference.restored(saved: defaults.object(forKey: "allowClicks") as? Bool,
            legacy: defaults.object(forKey: "allowPinchClicks") as? Bool) ? .on : .off
        allowClicks.target = self; allowClicks.action = #selector(allowClicksChanged)
        allowClicks.setAccessibilityLabel("Enable left-click and right-click gestures")
        allowClicks.toolTip = "Raise index + middle and hold for one second to click. Pinch all five fingertips together to right-click."
        allowDragging.state = defaults.bool(forKey: "allowDragging") ? .on : .off
        allowDragging.target = self; allowDragging.action = #selector(draggingChanged)
        allowDragging.toolTip = "Start with one hand. Make an L with both thumbs + index fingers; fold the other fingers. Hold briefly, then move your original hand to drag. Open either hand to release."
        allowDragging.setAccessibilityLabel("Enable two-hand L gesture for dragging and selecting text")
        allowScrolling.state = (defaults.object(forKey: "allowScrolling") as? Bool ?? true) ? .on : .off
        precisionMode.state = defaults.bool(forKey: "precisionMode") ? .on : .off
        precisionMode.target = self; precisionMode.action = #selector(precisionChanged)
        precisionMode.toolTip = "Reduce pointer travel for small targets. Lower and raise your hand to reposition."
        precisionMode.setAccessibilityLabel("Precision mode for slower pointer movement")
        steadyAim.state = (defaults.object(forKey: "steadyAim") as? Bool ?? true) ? .on : .off
        steadyAim.target = self; steadyAim.action = #selector(steadyAimChanged)
        steadyAim.toolTip = "Slow hand movements make smaller pointer adjustments. Move faster to cross the screen."
        steadyAim.setAccessibilityLabel("Steady aim for easier small targets")
        allowScrolling.target = self; allowScrolling.action = #selector(scrollingChanged)
        allowScrolling.toolTip = "Pinch thumb + index + middle together, hold briefly, then move your hand up/down. Release to stop scrolling."
        allowScrolling.setAccessibilityLabel("Enable thumb, index, and middle finger pinch scrolling with vertical hand movement")
        practiceButton.target = self; practiceButton.action = #selector(startPractice)
        practiceButton.bezelStyle = .rounded
        practiceButton.font = .systemFont(ofSize: 13, weight: .medium)
        practiceButton.keyEquivalent = "t"; practiceButton.keyEquivalentModifierMask = [.command, .shift]
        practice.onTaskChange = { [weak self] task in self?.practiceTaskChanged(task) }
        shortcutChoice.addItems(withTitles: ["⌃⌥⌘H", "⌃⌥⌘M", "Off"])
        shortcutChoice.selectItem(at: min(2, max(0, defaults.integer(forKey: "resumeShortcut"))))
        shortcutChoice.target = self; shortcutChoice.action = #selector(shortcutChanged)
        shortcutChoice.setAccessibilityLabel("Global camera pause and resume shortcut")
        shortcutStatus.font = .systemFont(ofSize: 11); shortcutStatus.textColor = .secondaryLabelColor

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
        clickMode = .pointAndHold
        allowPinchDragging.state = clickMode == .pinch && allowDragging.state != .on && defaults.bool(forKey: "allowPinchDragging") ? .on : .off
        allowPinchDragging.target = self; allowPinchDragging.action = #selector(pinchDraggingChanged)
        allowPinchDragging.toolTip = "Pinch + release to click. Hold + move your hand to drag or select text. Release to finish. Requires Allow clicks."
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
        let shortcutRow = NSStackView(views: [NSTextField(labelWithString: "Pause / resume anywhere"), shortcutChoice])
        shortcutRow.spacing = 8
        shortcutChoice.setContentHuggingPriority(.required, for: .horizontal)
        setupRows = StartupStyle.column([permissionStatus, setupRow, shortcutRow, shortcutStatus], spacing: 8)
        for row in [setupRow, shortcutRow] {
            row.translatesAutoresizingMaskIntoConstraints = false
            row.widthAnchor.constraint(equalTo: setupRows.widthAnchor).isActive = true
        }
        setupRow.distribution = .fillEqually
        permissionStatus.widthAnchor.constraint(equalTo: setupRows.widthAnchor).isActive = true
        shortcutStatus.widthAnchor.constraint(equalTo: setupRows.widthAnchor).isActive = true
        setupToggle.setButtonType(.pushOnPushOff)
        setupToggle.bezelStyle = .disclosure
        setupToggle.setAccessibilityLabel("Permissions and app setup")
        setupToggle.target = self; setupToggle.action = #selector(toggleSetup)
        let cameraPermission = AVCaptureDevice.authorizationStatus(for: .video)
        setupToggle.state = AXIsProcessTrusted() && cameraPermission != .denied && cameraPermission != .restricted ? .off : .on
        toggleSetup()
        setupLabel.font = .systemFont(ofSize: 12, weight: .medium)
        setupLabel.setAccessibilityElement(false)
        let setupDisclosure = NSStackView(views: [setupToggle, setupLabel])
        setupDisclosure.spacing = 6
        displayStatus.font = .systemFont(ofSize: 11)
        displayStatus.textColor = StartupStyle.muted
        forwardInstructions.font = .systemFont(ofSize: 12)
        forwardInstructions.textColor = StartupStyle.muted
        forwardControls = StartupStyle.column([forwardInstructions], spacing: 6)
        optionsToggle.setButtonType(.pushOnPushOff)
        optionsToggle.bezelStyle = .rounded
        optionsToggle.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: nil)
        optionsToggle.imagePosition = .imageLeading
        optionsToggle.target = self; optionsToggle.action = #selector(toggleOptions)
        optionsToggle.setAccessibilityLabel("Settings")
        optionsToggle.state = .off
        let pointerControls = NSStackView(views: [control, allowClicks, allowScrolling])
        let extraControls = NSStackView(views: [steadyAim, precisionMode, allowDragging])
        for row in [pointerControls, extraControls] {
            row.alignment = .centerY
            row.spacing = 20
        }
        optionsRows = StartupStyle.column([pointerControls, extraControls, clickTest, displayStatus], spacing: 12)
        for row in [pointerControls, extraControls] {
            row.translatesAutoresizingMaskIntoConstraints = false
            row.distribution = .fillEqually
            row.widthAnchor.constraint(equalTo: optionsRows.widthAnchor).isActive = true
        }
        toggleOptions()
        gestureGuide.select(.move)
        let content = LaunchContentView(title: titleLabel, cameraStatus: cameraStatus,
            start: toggle, practiceButton: practiceButton, settingsButton: optionsToggle,
            guide: gestureGuide, preview: preview, feedback: feedback, practice: practice,
            setupDisclosure: setupDisclosure, setupRows: setupRows, settingsRows: optionsRows,
            diagnostics: diagnostics, cameraTestButton: diagnosticsButton)
        window.contentView = content

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
            self.showFeedback(self.startingPoseTitle, self.startingPoseDetail)
        }
        camera.onError = { [weak self] message in
            guard let self, self.running else { return }
            self.pause()
            self.showFeedback("Camera unavailable", message)
            if self.diagnosticsPresented {
                self.diagnosticExportMessage = "Camera unavailable. " + message
                self.refreshDiagnosticControls()
            }
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
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(environmentResumed(_:)), name: name, object: nil)
        }
        shortcut.onPress = { [weak self] in
            guard let self, self.activation.press() else { return }
            guard CameraTestPolicy.allowsCameraToggle(presented: self.diagnosticsPresented,
                running: self.running, hasRecording: self.diagnosticRecorder.session != nil) else { return }
            self.toggleCamera()
        }
        shortcut.onRelease = { [weak self] in self?.activation.release() }
        shortcutChanged()
        configureInteraction(); refresh(); showWindow(); updateDisplayStatus()
        if setupToggle.state == .on { revealInWorkspace(setupRows) }
        DispatchQueue.main.async { [weak self] in self?.showCompletedUpdate() }

    }

    @objc private func toggleSetup() {
        setupRows.isHidden = setupToggle.state == .off
        setupToggle.setAccessibilityExpanded(setupToggle.state == .on)
        if setupToggle.state == .on { revealInWorkspace(setupRows) }
    }

    @objc private func toggleOptions() {
        optionsRows.isHidden = optionsToggle.state == .off
        optionsToggle.title = "Settings"
        optionsToggle.setAccessibilityExpanded(optionsToggle.state == .on)
        if optionsToggle.state == .on { revealInWorkspace(optionsRows) }
    }

    private func revealInWorkspace(_ view: NSView) {
        StartupStyle.reveal(view)
    }

    private func refreshSetupSteps(trusted: Bool) {
        let authorization = AVCaptureDevice.authorizationStatus(for: .video)
        let cameraBlocked = authorization == .denied || authorization == .restricted
        let next = !trusted || cameraBlocked ? "Permissions · Action needed" : "Permissions"
        if setupLabel.stringValue != next { setupLabel.stringValue = next }
    }

    private func configureInteraction() {
        let practiceTask = practice.currentTask
        let settings = InteractionSettings(mode: practicing ? .pointAndHold : clickMode,
            allowClicks: practicing || allowClicks.state == .on,
            pointerEnabled: practicing || control.state == .on,
            pinchThreshold: [0.34, 0.42, 0.50][min(2, max(0, sensitivity.selectedSegment))],
            dwellSeconds: [0.65, 1.0, 1.5][min(2, max(0, dwellDuration.selectedSegment))],
            allowScrolling: practicing ? practiceTask == .scroll : allowScrolling.state == .on,
            allowDragging: practicing ? practiceTask == .select : allowDragging.state == .on,
            allowPinchDragging: !practicing && clickMode == .pinch && allowPinchDragging.state == .on,
            precisionMode: precisionMode.state == .on, steadyAim: steadyAim.state == .on)
        if settings != engine.settings { stopDiagnosticRecording(.interactionReset); releaseDrag() }
        engine.configure(settings)
    }

    private func updateDisplayStatus() {
        guard let window else { return }
        let screen = running ? NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == targetDisplay
        } : window.screen
        displayStatus.stringValue = (practicing ? "Practice display: " : (running ? "Controlling: " : "Target display: ")) + (screen?.localizedName ?? "Unavailable")
    }

    @objc private func environmentPaused(_ notification: Notification) {
        switch notification.name {
        case NSWorkspace.willSleepNotification: activation.awake = false
        case NSWorkspace.screensDidSleepNotification: activation.displaysAwake = false
        default: activation.sessionActive = false
        }
        guard running else { return }
        pause()
        showFeedback("Paused for system change", "Camera and mouse control stopped. Start camera to resume when ready.")
    }

    @objc private func environmentResumed(_ notification: Notification) {
        switch notification.name {
        case NSWorkspace.didWakeNotification: activation.awake = true
        case NSWorkspace.screensDidWakeNotification: activation.displaysAwake = true
        default: activation.sessionActive = true
        }
        // Waking never restarts the camera. A fresh explicit action is required.
    }

    @objc private func shortcutChanged() {
        let choice = shortcutChoice.indexOfSelectedItem
        UserDefaults.standard.set(choice, forKey: "resumeShortcut")
        activation.release()
        let registered = shortcut.configure(choice)
        shortcutStatus.stringValue = !registered ? "Shortcut unavailable. Choose the other key combination or Off."
            : (choice == 2 ? "Global shortcut off. Use Start camera or the menu-bar hand."
               : "\(shortcutChoice.titleOfSelectedItem ?? "") pauses or resumes the camera from another app. Esc pauses.")
    }

    private func disablePinchDragging(persist: Bool = true) {
        allowPinchDragging.state = .off
        if persist { UserDefaults.standard.set(false, forKey: "allowPinchDragging") }
    }

    @objc private func pinchDraggingChanged() {
        if allowPinchDragging.state == .on {
            allowDragging.state = .off
            UserDefaults.standard.set(false, forKey: "allowDragging")
        }
        UserDefaults.standard.set(allowPinchDragging.state == .on, forKey: "allowPinchDragging")
        configureInteraction(); resetInteraction(); clearClickFeedback(); readyFeedback()
    }

    @objc private func draggingChanged() {
        if allowDragging.state == .on { disablePinchDragging() }
        UserDefaults.standard.set(allowDragging.state == .on, forKey: "allowDragging")
        configureInteraction(); resetInteraction(); clearClickFeedback(); readyFeedback()
    }

    @objc private func precisionChanged() {
        UserDefaults.standard.set(precisionMode.state == .on, forKey: "precisionMode")
        configureInteraction()
    }

    @objc private func steadyAimChanged() {
        UserDefaults.standard.set(steadyAim.state == .on, forKey: "steadyAim")
        configureInteraction(); clearClickFeedback(); readyFeedback()
    }

    @objc private func scrollingChanged() {
        UserDefaults.standard.set(allowScrolling.state == .on, forKey: "allowScrolling")
        configureInteraction(); resetInteraction(); clearClickFeedback(); readyFeedback()
    }

    func applicationDidChangeScreenParameters(_ notification: Notification) {
        if running {
            pause()
            showFeedback("Displays changed · Paused", "Place this window on your target display, then start the camera again.")
        }
        updateDisplayStatus()
    }
    func windowDidChangeScreen(_ notification: Notification) { updateDisplayStatus() }


    private func showFeedback(_ title: String, _ detail: String, progress: Double? = nil,
                              clicked: Bool = false, rightClicked: Bool = false) {
        // Visible feedback stays to one short status; VoiceOver receives the full detail.
        feedback.isHidden = false
        feedback.update(title: title, detail: detail, fraction: progress, clicked: clicked)
        gestureGuide.update(active: rightClicked ? .rightClick : activeGesture(clicked: clicked),
                            scrollingEnabled: guideScrollingEnabled,
                            selectionEnabled: selectionAvailable)
        let announcement: String? = clicked
            ? (practicing ? (rightClicked ? "Practice right click" : "Practice click") : (rightClicked ? "Right click sent" : "Click sent"))
            : (["Looking for your hand", "Tracking interrupted", "Tracking delayed", "Enable Accessibility", "Paused"].contains(title) ? title : nil)
        if let announcement, lastAnnouncement != announcement {
            let now = ProcessInfo.processInfo.systemUptime
            // A click or explicit pause must not disappear behind the camera-status throttle.
            if clicked || announcement == "Paused" || now - lastAnnouncementTime > 0.4 {
                NSAccessibility.post(element: feedback, notification: .announcementRequested,
                    userInfo: [.announcement: announcement, .priority: NSAccessibilityPriorityLevel.low.rawValue])
                lastAnnouncementTime = now
                lastAnnouncement = announcement
            }
        } else if announcement == nil {
            lastAnnouncement = nil
        }
    }

    private func activeGesture(clicked: Bool) -> GestureAction? {
        guard running else { return nil }
        if engine.settings.allowClicks && engine.settings.allowDragging {
            switch engine.drag.phase {
            case .confirming, .dragging: return .select
            case .idle, .needsRelease: break
            }
        }
        if engine.scroll.phase != .idle { return .scroll }
        if engine.settings.allowClicks && (engine.rightGestureActive || (clicked && lastClickWasRight)) { return .rightClick }
        if engine.settings.allowClicks && engine.pointHold.shouldFreeze { return .click }
        if engine.settings.allowClicks && (clicked || engine.tap.shouldFreeze || engine.fingersTogether) { return .click }
        return cameraReady && engine.settings.pointerEnabled && engine.acquisition.active ? .move : nil
    }

    private var selectionAvailable: Bool {
        practicing ? practice.currentTask == .select
            : allowDragging.state == .on && allowClicks.state == .on
    }

    private var guideScrollingEnabled: Bool {
        practicing ? practice.currentTask == .scroll : allowScrolling.state == .on
    }

    private var practiceGesture: GestureAction {
        switch practice.currentTask {
        case .click: return .click
        case .scroll: return .scroll
        case .select: return .select
        }
    }

    private func clearClickFeedback() {
        cursorFeedback.hide(); clickedUntil = 0; lastClickLocation = nil; lastClickWasRight = false
    }

    private func readyFeedback() {
        clearClickFeedback()
        if practicing {
            showFeedback("Practice only · No system input", practiceInstruction)
        } else if !running {
            showFeedback(startingPoseTitle, startingPoseDetail)
        } else if control.state != .on {
            showFeedback("Preview only", "Pointer and clicks off.")
        } else if allowClicks.state != .on {
            showFeedback("Clicks off", "Move your hand to aim.")
        } else if clickMode == .pointAndHold {
            showFeedback("Move to aim · Raise two to click", "Show an open hand to aim. Raise index and middle, curl the other fingers, and hold for one second. Open your hand to prepare another click.")
        } else {
            showFeedback(clickMode == .forward ? "Point forward to click" : "Two-finger tap to click",
                         clickMode == .forward ? "Aim normally, point toward the camera, then hold. Pull back to cancel." : "Bend index + middle together, then lift to click.")
        }
    }

    /// Practice and the system cursor use the same observed detector progress.
    /// Only the system path supplies a location for the nonactivating overlay.
    private func showPointHoldFeedback(at location: CGPoint? = nil, practiceOnly: Bool = false) {
        let prefix = practiceOnly ? "Practice · " : ""
        if engine.rightGestureActive {
            let held = engine.rightPinch.phase == .held
            let confirming = engine.rightPinch.phase == .confirming
            let title = held ? "Open your hand" : (confirming ? "Hold five tips together" : "Open your hand to prepare")
            let detail = held
                ? "One right-click was completed. Open your hand to move."
                : (confirming ? "Keep all five fingertips together and visible. Hold briefly to right-click once."
                    : "Open your hand with all five fingertips visible, then bring the fingertips together to right-click.")
            showFeedback(prefix + title, detail)
            if let location {
                cursorFeedback.show(at: location, displayID: targetDisplay, progress: 0, remaining: 0,
                    clicked: false, caption: held ? "Open your hand" : "Five tips together")
            }
            return
        }
        switch engine.pointHold.phase {
        case .needsMove:
            showFeedback(prefix + (latestPointingPose == nil ? latestPointingHint : "Open hand to prepare click"),
                         "Open your hand briefly, then raise index and middle and hold for one second.")
            cursorFeedback.hide()
        case .ready:
            showFeedback(prefix + (latestPointingPose == nil ? latestPointingHint : "Raise two fingers to click"),
                         "Raise index and middle with the other fingers curled. Hold still while the ring fills for one second.")
            cursorFeedback.hide()
        case .holding:
            let remaining = engine.pointHold.remainingSeconds
            showFeedback(prefix + String(format: "Click in %.1f s", max(0.1, remaining)),
                "Keep index + middle raised and still. Lower the middle finger to cancel. One click when the ring fills.",
                progress: engine.pointHold.progress)
            if let location {
                cursorFeedback.show(at: location, displayID: targetDisplay, progress: engine.pointHold.progress,
                    remaining: remaining, clicked: false)
            }
        case .clicked:
            showFeedback(prefix + "Lower middle to move", "One click was completed. Lower your middle finger to aim and prepare the next click.")
            if let location {
                cursorFeedback.show(at: location, displayID: targetDisplay, progress: 1, remaining: 0,
                    clicked: false, caption: "Lower middle to move")
            }
        }
    }

    private func refreshClickChrome() {
        allowScrolling.isEnabled = !practicing
        allowScrolling.toolTip = "Pinch thumb + index + middle and move your hand vertically. Release to resume aiming."
        let clicksOn = allowClicks.state == .on
        configureInteraction()
        clickModeControl.isEnabled = !practicing
        clickModeLabel.textColor = .secondaryLabelColor
        // There is one click gesture, so it does not need a mode picker.
        clickModeControl.superview?.isHidden = clickMode == .pointAndHold || clickMode == .twoFingerTap
        sensitivity.superview?.isHidden = clickMode == .pointAndHold || clickMode == .twoFingerTap
        sensitivity.isEnabled = clickMode == .pinch
        pinchFeelLabel.isHidden = clickMode != .pinch
        sensitivity.isHidden = clickMode != .pinch
        pinchFeelLabel.textColor = sensitivity.isEnabled ? .secondaryLabelColor : .tertiaryLabelColor
        dwellDuration.isHidden = clickMode != .forward
        dwellDurationLabel.isHidden = clickMode != .forward
        let learning = practicing
        allowPinchDragging.isHidden = clickMode != .pinch
        allowPinchDragging.title = learning ? "Try pinch dragging" : "Pinch to drag (experimental)"
        allowDragging.title = "Select text"
        allowScrolling.title = "Scroll"
        precisionMode.title = "Precision"
        clickTest.isEnabled = clicksOn && !learning
        allowClicks.isEnabled = !learning
        control.isEnabled = !learning
        precisionMode.isEnabled = !learning
        allowDragging.isEnabled = !learning
        gestureGuide.update(active: activeGesture(clicked: false),
                            scrollingEnabled: guideScrollingEnabled,
                            selectionEnabled: selectionAvailable)
        updatePractice(); updateDisplayStatus()
    }

    private func updatePractice() {
        guard forwardControls != nil else { return }
        forwardControls.isHidden = clickMode != .forward && !practicing
        practice.isHidden = !practicing
        preview.isHidden = practicing
        practiceButton.title = practicing ? "Finish practice" : "Practice"
        refreshDiagnosticControls()
        forwardInstructions.stringValue = practicing
            ? "Practice only · Complete the task, then choose Next."
            : "Point forward to click · No pose setup needed · Experimental"
    }

    private var practiceInstruction: String {
        switch practice.currentTask {
        case .click: return "Aim at Send. Raise middle + index and hold for one second."
        case .scroll: return "Pinch thumb + index + middle, then move your hand vertically."
        case .select: return "Make an L with both hands, move the original hand across the sentence, then open either hand."
        }
    }

    private func practiceTaskChanged(_ task: PracticeTask) {
        guard practicing else { return }
        stopDiagnosticRecording(.taskChanged)
        practiceCursor = nil
        practiceMessageUntil = 0
        resetInteraction()
        configureInteraction()
        clearClickFeedback()
        gestureGuide.select(practiceGesture)
        refreshClickChrome()
        showFeedback("Practice only · No system input", practiceInstruction)
    }

    @objc private func startPractice() {
        if diagnosticsPresented { closeDiagnostics(); return }
        if practicing { finishPractice(); return }
        enterPractice()
    }

    private func enterPractice(startCamera: Bool = true) {
        guard activation.canResume else { return }
        // Practice changes this session's output, not the user's saved preferences.
        allowClicks.state = .off
        disableScrolling(persist: false); disablePinchDragging(persist: false)
        allowDragging.state = .off
        practicing = true
        resetInteraction(); practice.reset(task: .click); practiceCursor = nil; clearClickFeedback(); practiceMessageUntil = 0
        gestureGuide.select(.click)
        optionsToggle.state = .off; toggleOptions()
        if startCamera && !running { toggleCamera() }
        refreshClickChrome()
        if !diagnosticsPresented { revealInWorkspace(practice) }
    }

    private func finishPractice() {
        stopDiagnosticRecording(.practiceFinished)
        practicing = false
        resetInteraction(); clearClickFeedback(); practice.reset(task: .click); practiceCursor = nil
        disableScrolling(persist: false); disablePinchDragging(persist: false)
        allowDragging.state = .off
        allowClicks.state = .off
        refreshClickChrome()
        showFeedback("Practice finished", "Clicks, scrolling, and dragging are off. Enable them when you want to control other apps.")
    }

    private func disableScrolling(persist: Bool = true) {
        allowScrolling.state = .off
        if persist { UserDefaults.standard.set(false, forKey: "allowScrolling") }
    }

    private var pinchDragInstruction: String {
        switch engine.pinchDrag.phase {
        case .waitingForOpen: return "Raise index + middle before the next tap."
        case .ready: return "Pinch + release to click. Hold + move hand to drag."
        case .confirming: return "Hold pinch briefly."
        case .pressed: return "Move hand to drag · Release to click"
        case .dragging: return "Release to finish."
        }
    }

    @objc private func openDiagnostics() {
        guard FeatureFlags.diagnostics, !diagnosticsPresented, activation.canResume, let diagnostics else { return }
        diagnosticsPresented = true
        let reviewing = diagnosticRecorder.session != nil
        if reviewing && running { pause() }
        if !practicing { enterPractice(startCamera: !reviewing) }
        else if practice.currentTask != .click { practice.select(.click) }
        diagnostics.setAdvanced(false)
        diagnosticRenderedAt = -.infinity
        refreshDiagnosticControls()
    }

    private func closeDiagnostics() {
        guard FeatureFlags.diagnostics, diagnosticsPresented else { return }
        diagnosticsPresented = false
        pause()
        refreshDiagnosticControls()
    }

    private var canRecordDiagnostics: Bool {
        FeatureFlags.diagnostics && diagnosticsPresented && activation.canResume
    }

    private func refreshDiagnosticControls() {
        guard FeatureFlags.diagnostics, let diagnostics else { return }
        (window?.contentView as? LaunchContentView)?.setDiagnosticsPresented(diagnosticsPresented)
        diagnostics.updateRecorder(diagnosticRecorder, canRecord: canRecordDiagnostics, cameraRunning: running,
            exporting: exportingDiagnostics, hasSavedFile: diagnosticSavedURL != nil)
        diagnostics.showNotice(diagnosticExportMessage)
        let canToggleCamera = CameraTestPolicy.allowsCameraToggle(presented: diagnosticsPresented,
            running: running, hasRecording: diagnosticRecorder.session != nil)
        toggle.isEnabled = canToggleCamera
        cameraMenuItem?.isEnabled = canToggleCamera
    }

    private func stopDiagnosticRecording(_ reason: DiagnosticStopReason) {
        guard FeatureFlags.diagnostics else { return }
        diagnosticRecorder.stop(reason)
        refreshDiagnosticControls()
    }

    private func confirmDiagnosticReplacement(_ action: @escaping () -> Void) {
        guard FeatureFlags.diagnostics else { return }
        guard diagnosticRecorder.sampleCount > 0 else { action(); return }
        let alert = NSAlert()
        alert.messageText = "Start a new recording?"
        alert.informativeText = "Save results first if you want to keep this attempt. Starting again replaces the in-memory recording, but does not change any saved file."
        alert.addButton(withTitle: "Start new recording")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn { action() }
        }
    }

    private func toggleDiagnosticRecording() {
        guard FeatureFlags.diagnostics, diagnosticsPresented else { return }
        if diagnosticRecorder.isRecording {
            stopDiagnosticRecording(.manual)
            pause()
            return
        }
        guard canRecordDiagnostics, !exportingDiagnostics else { return }
        confirmDiagnosticReplacement { [weak self] in
            guard let self, self.canRecordDiagnostics, let diagnostics = self.diagnostics else { return }
            if !self.practicing { self.enterPractice(startCamera: false) }
            self.practice.reset(task: .click)
            self.practiceTaskChanged(.click)
            if !self.running { self.toggleCamera() }
            let bounds = CGDisplayBounds(self.targetDisplay)
            self.diagnosticRecorder.start(width: bounds.width, height: bounds.height,
                settings: self.engine.settings, now: ProcessInfo.processInfo.systemUptime,
                intent: diagnostics.selectedIntent)
            self.diagnosticExportMessage = nil
            self.diagnosticSavedURL = nil
            diagnostics.setAdvanced(false)
            self.refreshDiagnosticControls()
        }
    }

    private func exportDiagnosticRecording() {
        guard FeatureFlags.diagnostics, diagnosticsPresented, !diagnosticRecorder.isRecording, !exportingDiagnostics,
              let session = diagnosticRecorder.session, !session.entries.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "hand-mouse-diagnostics.json"
        panel.message = "Save a diagnostic JSON file on this Mac. Share it only if you choose. It contains numbers and timing, not camera video or audio."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            self.exportingDiagnostics = true
            self.refreshDiagnosticControls()
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let result = Result { try session.encoded().write(to: url, options: .atomic) }
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.exportingDiagnostics = false
                    switch result {
                    case .success:
                        self.diagnosticSavedURL = url
                        self.diagnosticExportMessage = "Saved \(url.lastPathComponent) on this Mac. Nothing was uploaded."
                    case .failure(let error):
                        self.diagnosticExportMessage = "Could not save. Your results are still in memory; try another location."
                        let alert = NSAlert()
                        alert.messageText = "Could not save results"
                        alert.informativeText = error.localizedDescription
                        alert.beginSheetModal(for: self.window)
                    }
                    self.refreshDiagnosticControls()
                }
            }
        }
    }

    private func observePractice(_ frame: HandFrame, now: Double, step: InteractionStep, movement: Double?) {
        guard FeatureFlags.diagnostics, diagnosticsPresented, let diagnostics, let diagnosticPreview,
              practice.currentTask == .click else { return }
        let input = PracticeDiagnosticInput(timestamp: frame.timestamp, now: now, aspect: Double(frame.aspect),
            landmarks: frame.pointingObservation?.landmarks ?? [:], handSide: frame.handSide,
            fiveFingerPinchRatio: frame.fiveFingerPinchRatio, threeFingerPinchRatio: frame.threeFingerPinchRatio)
        let interval = diagnosticLastFrame.map { frame.timestamp - $0 }
        diagnosticLastFrame = frame.timestamp
        diagnosticInterrupted = false
        let outcome = PracticeDiagnosticOutcome(engine: engine, step: step, pose: frame.pointingPose)
        diagnosticRecorder.record(input, outcome: outcome, frameInterval: interval, movement: movement, destination: .practice)
        if now - diagnosticRenderedAt >= 0.1 || step.click || step.rightClick {
            diagnosticRenderedAt = now
            diagnosticPreview.showPlaceholder(nil)
            diagnosticPreview.update(step.blocked == .staleFrame ? nil : frame, phase: previewPhase,
                clicked: step.click || step.rightClick)
            diagnostics.update(input: input, outcome: outcome, frameInterval: interval, movement: movement)
            refreshDiagnosticControls()
        }
    }

    private func observeDiagnosticInterruption(now: Double) {
        guard FeatureFlags.diagnostics, diagnosticsPresented, let diagnostics, let diagnosticPreview,
              practice.currentTask == .click, !diagnosticInterrupted else { return }
        diagnosticInterrupted = true
        let outcome = PracticeDiagnosticOutcome(engine: engine,
            step: InteractionStep(blocked: .staleFrame, destination: .practice), pose: nil)
        diagnosticRecorder.interrupt(at: now, outcome: outcome)
        diagnosticPreview.update(nil)
        diagnostics.update(input: nil, outcome: outcome)
        refreshDiagnosticControls()
    }

    private func handlePractice(_ frame: HandFrame, now: Double) {
        let movement = FeatureFlags.diagnostics ? engine.pointHold.movement(from: frame.points[.indexTip]) : nil
        guard frame.timestamp.isFinite, frame.timestamp <= now, now - frame.timestamp < 0.20 else {
            interruptInteraction(); cursorFeedback.hide()
            observePractice(frame, now: now, step: InteractionStep(blocked: .staleFrame, destination: .practice), movement: movement)
            showFeedback("Tracking delayed", "Task paused. Hold still briefly to reacquire your hand.")
            return
        }
        lastFrameTime = now; cameraReady = true; preview.showPlaceholder(nil); preview.update(frame)
        cameraStatus.stringValue = "Practice only"
        cursorFeedback.hide()
        // This branch ends before OS dispatch. Simulation also exposes no system output.
        let screen = CGDisplayBounds(targetDisplay)
        let step = engine.process(index: frame.points[.indexTip], pinchRatio: engine.settings.allowPinchDragging ? frame.dragPinchRatio : frame.pinchRatio,
            forwardPose: frame.forwardPose, timestamp: frame.timestamp, now: now,
            bounds: screen, running: running, trusted: false, destination: .practice,
            cursorPosition: practiceCursor ?? CGPoint(x: screen.midX, y: screen.midY),
            handSide: frame.handSide, scrollPoint: frame.scrollPoint,
            primaryL: frame.isL, companionPresent: frame.companionPresent, companionL: frame.companionL,
            primaryReleased: frame.lReleased, companionReleased: frame.companionReleased, palm: frame.palm, tapPose: frame.tapPose, fingerSeparationRatio: frame.fingerSeparationRatio, scrollPinchRatio: frame.dragPinchRatio,
            pointingPose: frame.pointingPose, fiveFingerPinchRatio: frame.fiveFingerPinchRatio,
            threeFingerPinchRatio: frame.threeFingerPinchRatio)
        preview.controlRegion = engine.pointerControlRegion
        diagnosticPreview?.controlRegion = engine.pointerControlRegion
        observePractice(frame, now: now, step: step, movement: movement)
        if let location = step.location { practiceCursor = location }
        if diagnosticsPresented { return }
        let simulatedPoint = step.location.map {
            practice.point(forNormalizedInput: CGPoint(x: ($0.x - screen.minX) / screen.width,
                                                       y: ($0.y - screen.minY) / screen.height))
        }
        if step.blocked != nil || simulatedPoint == nil {
            _ = practice.update(point: nil, progress: 0, clicked: false, interrupted: true)
            let message = step.blocked == .differentHand
                ? "Use the same hand, or finish and restart practice to switch hands."
                : "Show your hand. Move to aim."
            showFeedback("Practice paused", message)
            return
        }
        let completed = practice.update(point: simulatedPoint, progress: engine.pointHold.progress, clicked: step.click,
                                        rightClicked: step.rightClick, holding: engine.pointHold.phase == .holding,
                                        scrollY: step.scrollY, dragging: step.dragging)
        if completed {
            practiceMessage = practice.currentTask == .select
                ? "Sentence highlighted ✓ · Choose Retry or another task."
                : "Task complete ✓ · Choose Next when you are ready."
            practiceMessageUntil = .infinity
            showFeedback("Task complete ✓", practiceMessage)
            return
        }
        if practice.state.completed {
            showFeedback("Task complete ✓", practiceMessage)
            return
        }
        switch practice.currentTask {
        case .click:
            if step.rightClick {
                showFeedback("Practice · Right click ✓", "Open your hand to reset. Right clicks do not complete the Send task.", clicked: true, rightClicked: true)
            } else { showPointHoldFeedback(practiceOnly: true) }
        case .scroll:
            showFeedback(engine.scroll.phase == .scrolling ? "Practice · Scrolling" : "Practice · Find Quarterly review",
                         engine.scroll.phase == .scrolling
                            ? "Move your pinched hand vertically, then release when the row is visible."
                            : practiceInstruction)
        case .select:
            let detail = engine.drag.phase == .needsRelease
                ? "Open either hand briefly, then make both L poses again."
                : (step.dragging ? "Move across the sentence, then open either hand to release."
                                 : practiceInstruction)
            showFeedback(step.dragging ? "Practice · Highlighting" : "Practice · Select the sentence", detail)
        }
    }

    @objc private func showWindow() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }

    @objc private func checkForUpdates() {
        guard !checkingForUpdate else { return }
        showWindow()
        guard let checkout = SourceUpdate.checkoutURL() else {
            showUpdateAlert(title: "Updates aren’t configured",
                detail: "Install Hand Mouse from its GitHub source checkout once. The installer will connect this menu to that checkout.")
            return
        }
        checkingForUpdate = true
        updateMenuItem.isEnabled = false
        updateMenuItem.title = "Checking for Updates…"
        let installedCommit = Bundle.main.object(forInfoDictionaryKey: "HandMouseSourceCommit") as? String
        let installedVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try SourceUpdate.check(checkout: checkout,
                installedCommit: installedCommit, installedVersion: installedVersion) }
            DispatchQueue.main.async { self?.finishUpdateCheck(result, checkout: checkout) }
        }
    }

    private func finishUpdateCheck(_ result: Result<UpdateCheck, Error>, checkout: URL) {
        checkingForUpdate = false
        updateMenuItem.isEnabled = true
        updateMenuItem.title = "Check for Updates…"
        switch result {
        case .failure(let error):
            showUpdateAlert(title: "Couldn’t check for updates", detail: error.localizedDescription)
        case .success(let check):
            switch check.comparison {
            case .current:
                let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "current"
                showUpdateAlert(title: "Hand Mouse is up to date", detail: "Version \(version) matches the latest version on GitHub.")
            case .unsafe(let reason):
                showUpdateAlert(title: "Update stopped safely", detail: reason + " Your files and installed app were not changed.")
            case .available:
                let alert = NSAlert()
                alert.alertStyle = .informational
                alert.messageText = "A Hand Mouse update is available"
                alert.informativeText = "Update to version \(check.remoteVersion ?? "the latest version") from GitHub? Hand Mouse will pause, update the source checkout, rebuild with its existing signing identity, and reopen."
                alert.addButton(withTitle: "Update and Restart")
                alert.addButton(withTitle: "Cancel")
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                beginUpdate(checkout: checkout, expectedCommit: check.remoteCommit)
            }
        }
    }

    private func beginUpdate(checkout: URL, expectedCommit: String) {
        guard let helper = Bundle.main.url(forResource: "update-and-relaunch", withExtension: "sh"),
              let stateDirectory = SourceUpdate.stateDirectory() else {
            showUpdateAlert(title: "Update helper unavailable", detail: "Reinstall Hand Mouse from the source checkout to repair the updater.")
            return
        }
        if running { pause() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [helper.path, checkout.path, Bundle.main.bundleURL.path,
                             String(ProcessInfo.processInfo.processIdentifier), expectedCommit, stateDirectory.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            NSApp.terminate(nil)
        } catch {
            showUpdateAlert(title: "Update couldn’t start", detail: error.localizedDescription)
        }
    }

    private func showCompletedUpdate() {
        guard let result = SourceUpdate.takeResult() else { return }
        showUpdateAlert(title: result.success ? "Hand Mouse updated" : "Update didn’t finish", detail: result.detail)
    }

    private func showUpdateAlert(title: String, detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func toggleCamera() {
        if running { pause(); return }
        guard activation.canResume else { return }
        running = true; cameraReady = false
        ownership.reset()
        resetInteraction(); clearClickFeedback()
        lastFrameTime = ProcessInfo.processInfo.systemUptime
        // Lock to the display containing this window for the duration of this session.
        if let number = window.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            targetDisplay = CGDirectDisplayID(number.uint32Value)
        }
        configureInteraction(); updateDisplayStatus()
        toggle.title = "Pause"
        toggle.setAccessibilityLabel("Pause camera tracking")
        statusItem.button?.image = NSImage(systemSymbolName: "hand.point.up.left.fill", accessibilityDescription: "Hand Mouse camera on")
        toggle.image = NSImage(systemSymbolName: "pause.fill", accessibilityDescription: nil)
        cameraMenuItem.title = "Pause camera"
        cameraStatus.stringValue = "Starting camera…"
        preview.showPlaceholder("Allow camera access.")
        showFeedback("Starting camera", startingPoseDetail)
        revealInWorkspace(feedback)
        camera.start()
    }
    @objc private func pause() {
        stopDiagnosticRecording(.paused)
        running = false; camera.stop(); resetInteraction(); clickedUntil = 0; preview.update(nil)
        diagnosticPreview?.update(nil); diagnosticPreview?.showPlaceholder("")
        clearClickFeedback(); cameraReady = false
        cameraStatus.stringValue = "Camera off"
        preview.showPlaceholder("")
        toggle.title = "Start"
        toggle.setAccessibilityLabel("Start camera tracking")
        statusItem.button?.image = NSImage(systemSymbolName: "hand.point.up.left", accessibilityDescription: "Hand Mouse paused")
        toggle.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: nil)
        cameraMenuItem.title = "Start camera"
        showFeedback("Paused", "Use your mouse normally. Start the camera when you are ready.")
        updateDisplayStatus()
        if practicing && !diagnosticsPresented { finishPractice() }
        refreshDiagnosticControls()
    }
    @objc private func controlChanged() { configureInteraction(); resetInteraction(); readyFeedback() }
    @objc private func allowClicksChanged() {
        UserDefaults.standard.set(allowClicks.state == .on, forKey: "allowClicks")
        resetInteraction(); clickedUntil = 0
        refreshClickChrome(); readyFeedback(); refresh()
    }
    @objc private func clickModeChanged() {
        if practicing { practice.reset(); practiceCursor = nil; practiceMessageUntil = 0 }
        clickMode = .pointAndHold
        if clickMode != .pinch { disablePinchDragging() }
        UserDefaults.standard.set(clickMode.rawValue, forKey: "clickMode")
        resetInteraction(); clickedUntil = 0
        refreshClickChrome(); readyFeedback(); refresh()
    }
    @objc private func sensitivityChanged() {
        let selected = min(2, max(0, sensitivity.selectedSegment))
        UserDefaults.standard.set(selected, forKey: "clickSensitivity")
        configureInteraction(); resetInteraction(); readyFeedback()
    }
    @objc private func dwellDurationChanged() {
        UserDefaults.standard.set(min(2, max(0, dwellDuration.selectedSegment)), forKey: "dwellDurationPreset")
        configureInteraction(); resetInteraction(); clearClickFeedback()
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
        if FeatureFlags.diagnostics && diagnosticRecorder.isRecording {
            diagnosticRecorder.expire(at: ProcessInfo.processInfo.systemUptime)
            if !diagnosticRecorder.isRecording { refreshDiagnosticControls() }
        }
        if CameraTestPolicy.shouldStopCamera(presented: diagnosticsPresented, running: running,
            hasRecording: diagnosticRecorder.session != nil, recording: diagnosticRecorder.isRecording) {
            pause()
            return
        }
        let trusted = AXIsProcessTrusted()
        if previouslyTrusted == true && !trusted {
            setupToggle.state = .on; toggleSetup()
            resetInteraction(); clearClickFeedback()
        }
        previouslyTrusted = trusted
        refreshSetupSteps(trusted: trusted)
        if running && practicing {
            permissionStatus.stringValue = "Practice only · All system input off"
            // Optional practice needs no Accessibility access and has no OS output path.
            if cameraReady && ProcessInfo.processInfo.systemUptime - lastFrameTime > GestureTuning.trackingGraceSeconds {
                interruptInteraction(); clearClickFeedback(); practiceMessageUntil = 0
                observeDiagnosticInterruption(now: ProcessInfo.processInfo.systemUptime)
                _ = practice.update(point: nil, progress: 0, clicked: false)
                showFeedback("Practice · Tracking interrupted", startingPoseDetail + " No click is pending.")
            }
            return
        }
        let cameraAuthorization = AVCaptureDevice.authorizationStatus(for: .video)
        if cameraAuthorization == .denied || cameraAuthorization == .restricted {
            permissionStatus.stringValue = "Camera access needed."
        } else if trusted {
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
            interruptInteraction(); clearClickFeedback(); preview.update(nil)
            cameraStatus.stringValue = "Tracking interrupted"
            showFeedback("Tracking interrupted", "Show your hand again. Restart the camera if tracking does not resume.")
            return
        }
        if !trusted || control.state != .on {
            resetInteraction(); clearClickFeedback()
            showFeedback(trusted ? "Preview only" : "Enable Accessibility",
                         trusted ? "Pointer and clicks off." : "Open Permissions to enable control.")
            return
        }
        if allowClicks.state != .on && engine.scroll.phase == .idle {
            clearClickFeedback()
        }
    }
    private func handle(_ capture: HandCapture) {
        var frame = HandFrame(points: [:], pinchRatio: nil, timestamp: capture.timestamp, aspect: capture.aspect)
        frame.source = capture.source
        if let selected = ownership.primaryIndex(in: capture.hands.map { $0.handSide }) {
            frame = capture.hands[selected]
            let others = capture.hands.indices.filter { $0 != selected }
            frame.companionPresent = !others.isEmpty
            if others.count == 1, let other = others.first {
                let companion = capture.hands[other]
                let oppositeSide = companion.handSide != nil && companion.handSide != frame.handSide
                frame.companionL = oppositeSide && companion.isL
                frame.companionReleased = oppositeSide && companion.lReleased
            }
        }
        defer { ownership.lock(engine.acquisition.owner) }

        guard running else { return }
        lastForwardIssue = frame.forwardIssue
        latestPointingPose = frame.pointingPose
        latestPointingHint = frame.pointingHint
        let now = ProcessInfo.processInfo.systemUptime
        if frame.timestamp.isFinite, frame.timestamp <= now, now - frame.timestamp < 0.20 {
            let sourceChanged = lastCameraSource != nil && lastCameraSource != frame.source
            lastCameraSource = frame.source
            if sourceChanged {
                stopDiagnosticRecording(.cameraChanged)
                resetInteraction(); clearClickFeedback()
                showFeedback("Camera changed", startingPoseDetail + " The pointer stays where you left it.")
                return
            }
        }
        if CameraTestPolicy.usesPracticeOutput(practicing: practicing, presented: diagnosticsPresented) {
            handlePractice(frame, now: now); return
        }
        guard CGDisplayIsActive(targetDisplay) != 0 else {
            pause(); showFeedback("Display disconnected", "Choose a connected display and start the camera again.")
            return
        }
        let step = engine.process(index: frame.points[.indexTip], pinchRatio: engine.settings.allowPinchDragging ? frame.dragPinchRatio : frame.pinchRatio, forwardPose: frame.forwardPose,
                                  timestamp: frame.timestamp, now: now, bounds: CGDisplayBounds(targetDisplay),
                                  running: running, trusted: AXIsProcessTrusted(), cursorPosition: CGEvent(source: nil)?.location,
                                  handSide: frame.handSide, scrollPoint: frame.scrollPoint,
            primaryL: frame.isL, companionPresent: frame.companionPresent, companionL: frame.companionL,
            primaryReleased: frame.lReleased, companionReleased: frame.companionReleased, palm: frame.palm, tapPose: frame.tapPose, fingerSeparationRatio: frame.fingerSeparationRatio, scrollPinchRatio: frame.dragPinchRatio,
            pointingPose: frame.pointingPose, fiveFingerPinchRatio: frame.fiveFingerPinchRatio,
            threeFingerPinchRatio: frame.threeFingerPinchRatio)
        preview.controlRegion = engine.pointerControlRegion
        guard dragOutput.dispatch(step, post: postDragEvents) else { interruptInteraction(); return }
        if let blocked = step.blocked {
            clearClickFeedback()
            switch blocked {
            case .staleFrame:
                preview.update(nil)
                cameraStatus.stringValue = "Tracking delayed"
                showFeedback("Tracking delayed", startingPoseDetail + " No click is pending.")
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
                if ownership.side == nil && capture.hands.count > 1 {
                    showFeedback("Start with one hand", "Lower the other hand until Pointer ready. Then bring it back as the drag modifier.")
                } else {
                    showFeedback("Show your hand", "Keep your original pointer hand visible to resume moving.")
                }
            case .acquiring, .differentHand, .cursorUnavailable:
                lastFrameTime = now; cameraReady = true; preview.showPlaceholder(nil); preview.update(frame)
                cameraStatus.stringValue = "Waiting to resume"
                if blocked == .differentHand {
                    showFeedback("Use the same hand", "Pause and restart the camera to switch hands.")
                } else if blocked == .cursorUnavailable {
                    showFeedback("Pointer outside target display", "Move your mouse onto the chosen display, or move this window to another display and restart the camera.")
                } else {
                    showFeedback(startingPoseTitle, startingPoseDetail + " The pointer stays where you left it.")
                }
            case .paused: break
            }
            return
        }
        guard let location = step.systemLocation else { return }
        lastFrameTime = now; cameraReady = true; preview.showPlaceholder(nil)
        cameraStatus.stringValue = "Hand tracked"
        if !step.systemButtonHeld {
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: location, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
        if step.systemScrollY != 0,
           let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                               wheel1: step.systemScrollY, wheel2: 0, wheel3: 0) {
            event.location = location
            event.post(tap: .cghidEventTap)
        }
        let clicksAllowed = engine.settings.allowClicks
        if step.systemClick || step.systemRightClick {
            let right = step.systemRightClick
            let button: CGMouseButton = right ? .right : .left
            let downType: CGEventType = right ? .rightMouseDown : .leftMouseDown
            let upType: CGEventType = right ? .rightMouseUp : .leftMouseUp
            guard let down = CGEvent(mouseEventSource: nil, mouseType: downType, mouseCursorPosition: location, mouseButton: button),
                  let up = CGEvent(mouseEventSource: nil, mouseType: upType, mouseCursorPosition: location, mouseButton: button) else {
                interruptInteraction()
                clearClickFeedback()
                showFeedback("Click unavailable", "No click was sent. Open your hand to prepare another gesture.")
                return
            }
            down.setIntegerValueField(.mouseEventClickState, value: 1)
            up.setIntegerValueField(.mouseEventClickState, value: 1)
            down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
            clickedUntil = now + 0.35
            lastClickLocation = location
            lastClickWasRight = right
        }
        if engine.pinchDrag.releasedClick {
            clickedUntil = now + 0.35; lastClickLocation = location; lastClickWasRight = false
        }
        let clicked = now < clickedUntil
        preview.update(frame, phase: previewPhase, clicked: clicked)
        if engine.settings.allowPinchDragging && clicksAllowed && engine.scroll.phase == .idle {
            let title = clicked ? "Clicked ✓" : (step.dragging ? "Dragging" : (step.buttonHeld ? "Pressed" : "Two-finger tap to click"))
            showFeedback(title, pinchDragInstruction, clicked: clicked)
            if engine.pinchDrag.engaged || clicked {
                cursorFeedback.show(at: location, displayID: targetDisplay, progress: 0, remaining: 0, clicked: clicked, caption: title)
            } else { cursorFeedback.hide() }
        } else if engine.settings.allowDragging && (frame.companionPresent || engine.drag.phase != .idle) {
            let title = engine.drag.phase == .needsRelease ? "Open either hand to reset dragging" : (step.dragging ? "Dragging / selecting" : (engine.drag.phase == .confirming ? "Hold both L poses briefly"
                : (!frame.isL ? "Make an L with your pointer hand" : "Make an L with your second hand")))
            let detail = engine.drag.phase == .needsRelease
                ? "Open either hand briefly, then form both L poses again."
                : "Make an L with each thumb + index; fold the other fingers. Move your original hand to drag. Open either hand to release."
            showFeedback(clicksAllowed ? title : "Dragging off", clicksAllowed ? detail : "Enable Allow clicks to use two-hand dragging.")
            let confirming = engine.drag.phase == .confirming
            let caption = !clicksAllowed ? "Dragging off" : (engine.drag.phase == .needsRelease ? "Open hand to reset"
                : (step.dragging ? "Dragging" : (confirming ? "Starting drag" : "Both hands: L")))
            cursorFeedback.show(at: location, displayID: targetDisplay,
                progress: confirming ? engine.drag.progress : 0,
                remaining: confirming ? 0.25 * (1 - engine.drag.progress) : 0, clicked: false, caption: caption)
        } else if engine.scroll.phase != .idle {
            let active = engine.scroll.phase == .scrolling
            showFeedback(active ? "Scrolling ↑↓" : "Hold pinch briefly",
                "Keep thumb + index + middle pinched together and move your hand up/down. Release to resume aiming.")
            cursorFeedback.show(at: location, displayID: targetDisplay, progress: 0, remaining: 0, clicked: false,
                caption: active ? "Scrolling ↑↓" : "Pinch…")
        } else if !clicksAllowed {
            cursorFeedback.hide()
            showFeedback("Clicks off", "Move your hand to aim.")
        } else if clickMode == .pointAndHold {
            if clicked && engine.pointHold.phase != .holding && engine.rightPinch.phase != .confirming {
                let title = lastClickWasRight ? "Right clicked ✓" : "Clicked ✓"
                let detail = lastClickWasRight ? "Open your hand, then point with your index to move."
                    : "Lower your middle finger to move and prepare the next click."
                showFeedback(title, detail, clicked: true, rightClicked: lastClickWasRight)
                cursorFeedback.show(at: lastClickLocation ?? location, displayID: targetDisplay,
                    progress: 1, remaining: 0, clicked: true,
                    caption: lastClickWasRight ? "Right clicked ✓" : nil)
            } else {
                showPointHoldFeedback(at: location)
            }
        } else if clicked && !(clickMode == .twoFingerTap && (engine.tap.shouldFreeze || engine.tap.cancellation != nil)) {
            showFeedback("Clicked ✓", clickMode == .forward ? "Return to your movement pose before pointing forward again." : "Raise index + middle before the next tap.", clicked: true)
            cursorFeedback.show(at: lastClickLocation ?? location, displayID: targetDisplay, progress: 1, remaining: 0, clicked: true)
        } else if clickMode == .twoFingerTap {
            let guidance = TapGuidance(tap: engine.tap, locked: engine.fingersTogether)
            showFeedback(guidance.title, guidance.detail)
            if let caption = guidance.caption {
                cursorFeedback.show(at: location, displayID: targetDisplay, progress: 0, remaining: 0, clicked: false, caption: caption)
            } else { cursorFeedback.hide() }
        } else if clickMode == .forward && frame.forwardPose == nil {
            cursorFeedback.hide()
            let hint = ForwardClickHint.current(pose: nil, profile: engine.forwardProfile)
            showFeedback(frame.forwardIssue?.title ?? hint.title,
                (frame.forwardIssue?.detail ?? hint.detail) + " No click is pending. Try Pinch if this is uncomfortable.")
        } else if clickMode == .forward {
            switch engine.forward.phase {
            case .ready:
                cursorFeedback.hide()
                showFeedback("Move to aim", "Point toward the camera when you want to click. Staying still does nothing.")
            case .needsNeutral:
                cursorFeedback.hide()
                let hint = ForwardClickHint.current(pose: frame.forwardPose, profile: engine.forwardProfile)
                showFeedback(hint.title, hint.detail)
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
                case .held: showFeedback("Release your pinch", "Raise index + middle before the next tap.")
                }
            }
        }
    }

    private func resetInteraction() {
        stopDiagnosticRecording(.interactionReset)
        diagnosticLastFrame = nil; diagnosticRenderedAt = -.infinity; diagnosticInterrupted = false
        lastForwardIssue = nil
        releaseDrag()
        engine.reset()
        if practicing { practice.interrupt() }
        preview.controlRegion = engine.pointerControlRegion
    }

    private func interruptInteraction() {
        releaseDrag()
        engine.trackingInterrupted()
        if practicing { practice.interrupt() }
    }

    private func releaseDrag() { _ = postDragEvents(dragOutput.release()) }

    @discardableResult private func postDragEvents(_ events: [DragEvent]) -> Bool {
        for action in events {
            if action.kind == .up {
                // Allocate the release before mouse-down, so cleanup does not need
                // to allocate an event after a later failure or permission change.
                dragReleaseEvent?.location = action.location
                dragReleaseEvent?.post(tap: .cghidEventTap)
                dragReleaseEvent = nil
                continue
            }
            let type: CGEventType
            switch action.kind {
            case .down: type = .leftMouseDown
            case .moved: type = .leftMouseDragged
            case .up: type = .leftMouseUp
            }
            guard let event = CGEvent(mouseEventSource: nil, mouseType: type,
                                      mouseCursorPosition: action.location, mouseButton: .left) else { return false }
            if action.kind == .down {
                guard let release = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                    mouseCursorPosition: action.location, mouseButton: .left) else { return false }
                release.setIntegerValueField(.mouseEventClickState, value: 1)
                dragReleaseEvent = release
            }
            event.setIntegerValueField(.mouseEventClickState, value: 1)
            event.post(tap: .cghidEventTap)
        }
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { pause(); return true }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func applicationWillTerminate(_ notification: Notification) {
        releaseDrag(); cursorFeedback.hide(); camera.stop(); timer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        if let globalKey { NSEvent.removeMonitor(globalKey) }
        if let localKey { NSEvent.removeMonitor(localKey) }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
