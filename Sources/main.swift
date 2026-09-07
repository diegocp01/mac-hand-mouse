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
    private let placeholder = NSTextField(wrappingLabelWithString: "Camera paused\nStart camera to see your hand here.")

    init(session: AVCaptureSession) {
        preview = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
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
        placeholder.font = .systemFont(ofSize: 18, weight: .medium)
        placeholder.alignment = .center
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.centerXAnchor.constraint(equalTo: centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: centerYAnchor),
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
        guide.path = CGPath(roundedRect: rect.insetBy(dx: rect.width * GestureTuning.softInset, dy: rect.height * GestureTuning.softInset),
                            cornerWidth: 10, cornerHeight: 10, transform: nil)
        CATransaction.commit()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let camera = HandCamera()
    private var window: NSWindow!
    private var preview: PreviewView!
    private let titleLabel = NSTextField(labelWithString: "Your hand. Your cursor.")
    private let subtitle = NSTextField(wrappingLabelWithString: "1) Enable Accessibility  2) Start camera  3) Point with your index  4) Turn on Allow clicks when ready")
    private let feedback = ClickFeedbackView(frame: .zero)
    private let cursorFeedback = CursorFeedback()
    private let cameraStatus = NSTextField(labelWithString: "Camera off")
    private var setupRows: NSStackView!
    private let setupToggle = NSButton(title: "", target: nil, action: nil)
    private var lastFrameTime = 0.0
    private var cameraReady = false
    private var previouslyTrusted: Bool?
    private var movedUntil = 0.0
    private var cameraMenuItem: NSMenuItem!
    private let permissionStatus = NSTextField(wrappingLabelWithString: "")
    private let toggle = NSButton(title: "Start camera", target: nil, action: nil)
    private let control = NSButton(checkboxWithTitle: "Move the system pointer with my index finger", target: nil, action: nil)
    private let allowClicks = NSButton(checkboxWithTitle: "Allow clicks", target: nil, action: nil)
    private let clickModeControl = NSSegmentedControl(labels: ["Pinch", "Dwell"], trackingMode: .selectOne, target: nil, action: nil)
    private let sensitivity = NSSegmentedControl(labels: ["Precise", "Balanced", "Easy"], trackingMode: .selectOne, target: nil, action: nil)
    private let clickTest = NSButton(title: "Test click: 0", target: nil, action: nil)
    private let pinchFeelLabel = NSTextField(labelWithString: "Pinch feel")
    private let clickModeLabel = NSTextField(labelWithString: "How to click")
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
        if clickMode == .dwell {
            switch engine.dwell.phase {
            case .arming: return .confirming
            case .needMove: return .held
            case .idle: return .waitingForOpen
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
        if let url = Bundle.main.url(forResource: "HandMouse", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) { NSApp.applicationIconImage = icon }
        let appMenu = NSMenu()
        let root = NSMenuItem(); appMenu.addItem(root)
        let submenu = NSMenu(); root.submenu = submenu
        submenu.addItem(withTitle: "Quit Hand Mouse", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        NSApp.mainMenu = appMenu

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 800),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Hand Mouse"
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 620, height: 540)
        window.center()
        let content = NSView(); window.contentView = content

        titleLabel.font = .systemFont(ofSize: 26, weight: .bold)
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor
        subtitle.maximumNumberOfLines = 2
        preview = PreviewView(session: camera.session)
        preview.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            preview.heightAnchor.constraint(equalTo: preview.widthAnchor, multiplier: 0.60)
        ])
        cameraStatus.font = .systemFont(ofSize: 12, weight: .semibold)
        cameraStatus.textColor = .secondaryLabelColor
        permissionStatus.font = .systemFont(ofSize: 11)
        permissionStatus.textColor = .secondaryLabelColor

        toggle.target = self; toggle.action = #selector(toggleCamera)
        toggle.bezelStyle = .rounded
        if #available(macOS 11.0, *) { toggle.controlSize = .large }
        toggle.keyEquivalent = "\r"

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
        dwellDuration.setAccessibilityLabel("Dwell hold duration")
        dwellDuration.toolTip = "How long to hold still before a click. Changing this cancels the current countdown."
        sensitivityChanged()
        let savedMode = defaults.string(forKey: "clickMode") ?? ClickMode.pinch.rawValue
        clickMode = ClickMode(rawValue: savedMode) ?? .pinch
        clickModeControl.selectedSegment = clickMode == .dwell ? 1 : 0
        clickModeControl.target = self; clickModeControl.action = #selector(clickModeChanged)
        clickTest.target = self; clickTest.action = #selector(testClick)
        clickTest.bezelStyle = .rounded
        for label in [pinchFeelLabel, clickModeLabel, dwellDurationLabel] {
            label.font = .systemFont(ofSize: 12, weight: .medium)
            label.textColor = .secondaryLabelColor
        }

        let setupRow = NSStackView(views: [permissions, cameraSettings, reveal])
        setupRow.spacing = 10
        setupRows = NSStackView(views: [permissionStatus, setupRow])
        setupRows.orientation = .vertical; setupRows.alignment = .leading; setupRows.spacing = 8
        setupToggle.setButtonType(.pushOnPushOff)
        setupToggle.bezelStyle = .disclosure
        setupToggle.setAccessibilityLabel("Permissions and setup")
        setupToggle.target = self; setupToggle.action = #selector(toggleSetup)
        setupToggle.state = AXIsProcessTrusted() ? .off : .on
        toggleSetup()
        let setupLabel = NSTextField(labelWithString: "Permissions & setup")
        setupLabel.setAccessibilityElement(false)
        let setupDisclosure = NSStackView(views: [setupToggle, setupLabel])
        setupDisclosure.spacing = 6
        let spacer = NSView()
        let primaryRow = NSStackView(views: [cameraStatus, spacer, toggle])
        primaryRow.spacing = 12
        let modeRow = NSStackView(views: [allowClicks, clickModeLabel, clickModeControl, clickTest])
        modeRow.spacing = 12
        let tuningRow = NSStackView(views: [pinchFeelLabel, sensitivity, dwellDurationLabel, dwellDuration])
        tuningRow.spacing = 10
        let hint = NSTextField(wrappingLabelWithString: "Esc pauses at any time · Camera frames stay on this Mac")
        hint.font = .systemFont(ofSize: 11); hint.textColor = .secondaryLabelColor
        displayStatus.font = .systemFont(ofSize: 11)
        displayStatus.textColor = .secondaryLabelColor
        let header = NSStackView(views: [titleLabel, subtitle, primaryRow, displayStatus])
        header.orientation = .vertical; header.alignment = .leading; header.spacing = 10
        header.translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView(views: [
            preview, feedback,
            control, modeRow, tuningRow, setupDisclosure, setupRows, hint
        ])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        // A scrollable document keeps controls reachable on smaller laptop displays.
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let document = TopAlignedDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        content.addSubview(header); content.addSubview(scroll); document.addSubview(stack)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            header.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            header.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 0),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -20),
            preview.widthAnchor.constraint(equalTo: stack.widthAnchor),
            feedback.widthAnchor.constraint(equalTo: stack.widthAnchor),
            primaryRow.widthAnchor.constraint(equalTo: header.widthAnchor),
            subtitle.widthAnchor.constraint(equalTo: header.widthAnchor),
            permissionStatus.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])

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
            self.cameraStatus.stringValue = "Camera on · Looking for hand"
            self.preview.showPlaceholder(nil)
            self.showFeedback("Show one hand", "Keep your index finger and palm inside the dashed guide.")
        }
        camera.onError = { [weak self] message in
            guard let self, self.running else { return }
            self.pause(); self.showFeedback("Camera unavailable", message)
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

    private func configureInteraction() {
        engine.configure(InteractionSettings(mode: clickMode, allowClicks: allowClicks.state == .on,
            pointerEnabled: control.state == .on,
            pinchThreshold: [0.34, 0.42, 0.50][min(2, max(0, sensitivity.selectedSegment))],
            dwellSeconds: [0.65, 1.0, 1.5][min(2, max(0, dwellDuration.selectedSegment))]))
    }

    private func updateDisplayStatus() {
        guard let window else { return }
        let screen = running ? NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == targetDisplay
        } : window.screen
        displayStatus.stringValue = (running ? "Controlling: " : "Target display: ") + (screen?.localizedName ?? "Unavailable")
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
        cursorFeedback.hide(); clickedUntil = 0; movedUntil = 0; lastClickLocation = nil
    }

    private func readyFeedback() {
        clearClickFeedback()
        if !running {
            showFeedback("Ready when you are", "Start the camera, then show one hand with your palm visible.")
        } else if control.state != .on {
            showFeedback("Preview only", "Pointer movement and clicks are off.")
        } else if allowClicks.state != .on {
            showFeedback("Pointing only · Clicks off", "Move your index finger. Enable Allow clicks when you are ready.")
        } else {
            showFeedback(clickMode == .dwell ? "Hold still to click" : "Pinch to click",
                         clickMode == .dwell ? "A ring fills beside the pointer. Move your hand to cancel." : "Touch thumb + index, then separate for the next click.")
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
        dwellDuration.isHidden = clickMode != .dwell
        dwellDurationLabel.isHidden = clickMode != .dwell
        clickTest.isEnabled = clicksOn
        if clicksOn {
            subtitle.stringValue = clickMode == .dwell
                ? String(format: "Point, then hold still %.2g seconds to click. Move to cancel.", engine.settings.dwellSeconds)
                : "Point with your index, then pinch thumb + index to click."
        } else {
            subtitle.stringValue = "Practice pointing first. Turn on Allow clicks only when you want real mouse clicks."
        }
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
        cameraMenuItem.title = "Pause camera"
        cameraStatus.stringValue = "Starting camera…"
        preview.showPlaceholder("Starting camera…\nAllow camera access if macOS asks.")
        showFeedback("Starting camera", "Keep one hand ready, with your palm facing the camera.")
        camera.start()
    }
    @objc private func pause() {
        running = false; camera.stop(); engine.reset(); clickedUntil = 0; preview.update(nil)
        clearClickFeedback(); cameraReady = false
        cameraStatus.stringValue = "Camera off · Paused"
        preview.showPlaceholder("Camera paused\nStart camera to see your hand here.")
        toggle.title = "Start camera"
        cameraMenuItem.title = "Start camera"
        showFeedback("Paused", "Use your mouse normally. Start the camera when you are ready.")
        updateDisplayStatus()
    }
    @objc private func controlChanged() { configureInteraction(); engine.reset(); readyFeedback() }
    @objc private func allowClicksChanged() {
        UserDefaults.standard.set(allowClicks.state == .on, forKey: "allowClicks")
        engine.reset(); clickedUntil = 0
        refreshClickChrome(); readyFeedback(); refresh()
    }
    @objc private func clickModeChanged() {
        clickMode = clickModeControl.selectedSegment == 1 ? .dwell : .pinch
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
        if trusted {
            if control.state != .on {
                permissionStatus.stringValue = "Accessibility on · Preview only · Pointer and clicks off"
            } else if allowClicks.state != .on {
                permissionStatus.stringValue = "Accessibility on · Pointer OK · Clicks off until you allow them"
            } else if clickMode == .dwell {
                permissionStatus.stringValue = "Accessibility on · Dwell: hold still to click · Move after each click"
            } else {
                permissionStatus.stringValue = "Accessibility on · Pinch: touch thumb + index, then separate"
            }
        } else {
            permissionStatus.stringValue = "Needs Accessibility: tap Enable Accessibility → turn on Hand Mouse"
        }
        guard running else { return }
        let now = ProcessInfo.processInfo.systemUptime
        // Camera health must stay accurate in preview mode and before Accessibility is enabled.
        if cameraReady && now - lastFrameTime > GestureTuning.trackingGraceSeconds {
            engine.trackingInterrupted(); clearClickFeedback(); preview.update(nil)
            cameraStatus.stringValue = "Camera on · Tracking interrupted"
            showFeedback("Tracking interrupted", "Countdown canceled. Pause and restart the camera if tracking does not resume.")
            return
        }
        if !trusted || control.state != .on {
            engine.reset(); clearClickFeedback()
            showFeedback(trusted ? "Preview only" : "Enable Accessibility",
                         trusted ? "Pointer movement and clicks are off." : "Open Permissions & setup to allow this app to move the pointer.")
            return
        }
        if allowClicks.state != .on {
            clearClickFeedback()
        }
    }
    private func handle(_ frame: HandFrame) {
        guard running else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard CGDisplayIsActive(targetDisplay) != 0 else {
            pause(); showFeedback("Display disconnected", "Choose a connected display and start the camera again.")
            return
        }
        let step = engine.process(index: frame.points[.indexTip], pinchRatio: frame.pinchRatio,
                                  timestamp: frame.timestamp, now: now, bounds: CGDisplayBounds(targetDisplay),
                                  running: running, trusted: AXIsProcessTrusted())
        if let blocked = step.blocked {
            clearClickFeedback()
            switch blocked {
            case .staleFrame:
                preview.update(nil)
                cameraStatus.stringValue = "Camera on · Tracking delayed"
                showFeedback("Tracking delayed", "Countdown canceled. Hold still briefly to reacquire your hand.")
            case .invalidDisplay:
                pause(); showFeedback("Display unavailable", "Choose a connected display, then start camera.")
            case .permission, .previewOnly:
                if frame.timestamp.isFinite, frame.timestamp <= now, now - frame.timestamp < 0.20 {
                    lastFrameTime = now; cameraReady = true; preview.showPlaceholder(nil); preview.update(frame)
                    cameraStatus.stringValue = frame.points[.indexTip] == nil
                        ? "Camera on · Looking for hand" : "Camera on · Hand tracked"
                }
                showFeedback(blocked == .permission ? "Enable Accessibility" : "Preview only",
                    blocked == .permission ? "Open Permissions & setup to allow this app to move the pointer." : "Pointer movement and clicks are off.")
            case .missingHand:
                lastFrameTime = now; cameraReady = true; preview.showPlaceholder(nil); preview.update(frame)
                cameraStatus.stringValue = "Camera on · Looking for hand"
                showFeedback("Looking for your hand", "Keep your index finger and palm visible. Any countdown is canceled.")
            case .paused: break
            }
            return
        }
        guard let location = step.location else { return }
        lastFrameTime = now; cameraReady = true; preview.showPlaceholder(nil)
        cameraStatus.stringValue = "Camera on · Hand tracked"
        if step.restartedDwell { movedUntil = now + 0.3 }
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: location, mouseButton: .left)?.post(tap: .cghidEventTap)
        let clicksAllowed = engine.settings.allowClicks
        if step.click {
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
            showFeedback("Pointing only · Clicks off", "Move your index finger. Enable Allow clicks when you are ready.")
        } else if clicked {
            showFeedback("Clicked ✓", clickMode == .dwell ? "Move to a new spot before the next countdown." : "Separate thumb + index before the next click.", clicked: true)
            cursorFeedback.show(at: lastClickLocation ?? location, displayID: targetDisplay, progress: 1, remaining: 0, clicked: true)
        } else if clickMode == .dwell {
            switch engine.dwell.phase {
            case .idle:
                cursorFeedback.hide()
                showFeedback("Move to aim", "Hold still to start a new countdown. Movement cancels the previous one.")
            case .arming:
                let remaining = engine.dwell.remainingSeconds
                let detail = now < movedUntil
                    ? "Restarted after movement · Keep still to click · Esc pauses"
                    : "Keep still to click · Move to cancel · Esc pauses"
                showFeedback(String(format: "Click in %.1f s", max(0.1, remaining)), detail, progress: engine.dwell.progress)
                cursorFeedback.show(at: location, displayID: targetDisplay, progress: engine.dwell.progress,
                                    remaining: remaining, clicked: false, restarted: now < movedUntil)
            case .needMove:
                cursorFeedback.hide()
                showFeedback("Move to click again", "The last click is complete. Move your hand to start a new countdown.")
            }
        } else {
            cursorFeedback.hide()
            if frame.pinchRatio == nil {
                showFeedback("Pointing", "Show your thumb and palm to enable a pinch click.")
            } else {
                switch engine.pinch.phase {
                case .waitingForOpen: showFeedback("Open your hand", "Separate thumb + index to get ready.")
                case .ready: showFeedback("Ready to pinch", "Aim, then touch thumb + index. Try the Test click button.")
                case .confirming: showFeedback("Pinch detected", "Hold your fingertips together briefly.")
                case .held: showFeedback("Release your pinch", "Separate thumb + index before the next click.")
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
