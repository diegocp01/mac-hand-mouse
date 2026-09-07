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
    private let status = NSTextField(wrappingLabelWithString: "Ready when you are. Start the camera to begin.")
    private let permissionStatus = NSTextField(labelWithString: "")
    private let toggle = NSButton(title: "Start camera", target: nil, action: nil)
    private let control = NSButton(checkboxWithTitle: "Move the system pointer with my index finger", target: nil, action: nil)
    private let allowClicks = NSButton(checkboxWithTitle: "Allow clicks (off until you turn this on)", target: nil, action: nil)
    private let clickModeControl = NSSegmentedControl(labels: ["Pinch", "Dwell"], trackingMode: .selectOne, target: nil, action: nil)
    private let sensitivity = NSSegmentedControl(labels: ["Precise", "Balanced", "Easy"], trackingMode: .selectOne, target: nil, action: nil)
    private let clickTest = NSButton(title: "Test click: 0", target: nil, action: nil)
    private let pinchFeelLabel = NSTextField(labelWithString: "Pinch feel")
    private let clickModeLabel = NSTextField(labelWithString: "How to click")
    private var statusItem: NSStatusItem!
    private var running = false
    private var detector = PinchDetector()
    private var dwell = DwellDetector()
    private var clickMode: ClickMode = .pinch
    private var previewPhase: PinchPhase {
        if clickMode == .dwell {
            switch dwell.phase {
            case .arming: return .confirming
            case .needMove: return .held
            case .idle: return .waitingForOpen
            }
        }
        return detector.phase
    }
    private var filter = PointerFilter()
    private var lastHand = 0.0
    private var clickedUntil = 0.0
    private var testClicks = 0
    private var targetDisplay = CGMainDisplayID()
    private var timer: Timer?
    private var globalKey: Any?
    private var localKey: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let appMenu = NSMenu()
        let root = NSMenuItem(); appMenu.addItem(root)
        let submenu = NSMenu(); root.submenu = submenu
        submenu.addItem(withTitle: "Quit Hand Mouse", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        NSApp.mainMenu = appMenu

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 920),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Hand Mouse"
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.center()
        let content = NSView(); window.contentView = content

        titleLabel.font = .systemFont(ofSize: 26, weight: .bold)
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor
        subtitle.maximumNumberOfLines = 2
        preview = PreviewView(session: camera.session)
        preview.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            preview.widthAnchor.constraint(equalToConstant: 640),
            preview.heightAnchor.constraint(equalToConstant: 420)
        ])
        status.font = .systemFont(ofSize: 14, weight: .semibold)
        status.maximumNumberOfLines = 2
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
        sensitivityChanged()
        let savedMode = defaults.string(forKey: "clickMode") ?? ClickMode.pinch.rawValue
        clickMode = ClickMode(rawValue: savedMode) ?? .pinch
        clickModeControl.selectedSegment = clickMode == .dwell ? 1 : 0
        clickModeControl.target = self; clickModeControl.action = #selector(clickModeChanged)
        clickTest.target = self; clickTest.action = #selector(testClick)
        clickTest.bezelStyle = .rounded
        for label in [pinchFeelLabel, clickModeLabel] {
            label.font = .systemFont(ofSize: 12, weight: .medium)
            label.textColor = .secondaryLabelColor
        }

        let setupRow = NSStackView(views: [permissions, cameraSettings, reveal])
        setupRow.spacing = 10
        let primaryRow = NSStackView(views: [toggle])
        let modeRow = NSStackView(views: [clickModeLabel, clickModeControl, pinchFeelLabel, sensitivity, clickTest])
        modeRow.spacing = 10
        modeRow.alignment = .centerY

        let hint = NSTextField(wrappingLabelWithString: "Green = tracking · Blue = armed · White flash = click sent · Esc pauses · Clicks stay off until you allow them")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.maximumNumberOfLines = 2

        let stack = NSStackView(views: [
            titleLabel,
            subtitle,
            preview,
            status,
            permissionStatus,
            section("Camera"),
            primaryRow,
            section("Setup"),
            setupRow,
            section("Pointing"),
            control,
            section("Clicking"),
            allowClicks,
            modeRow,
            hint
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20)
        ])

        refreshClickChrome()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "hand.point.up.left", accessibilityDescription: "Hand Mouse")
        let menu = NSMenu()
        menu.addItem(withTitle: "Show Hand Mouse", action: #selector(showWindow), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Pause camera", action: #selector(pause), keyEquivalent: "").target = self
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        camera.onFrame = { [weak self] frame in self?.handle(frame) }
        camera.onStatus = { [weak self] message in guard let self, self.running else { return }; self.status.stringValue = message }
        camera.onError = { [weak self] message in
            guard let self, self.running else { return }
            self.pause(); self.status.stringValue = message
        }
        localKey = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.pause(); return nil }; return event
        }
        globalKey = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.pause() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.refresh() }
        refresh(); showWindow()
    }

    private func section(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title.uppercased())
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .tertiaryLabelColor
        return label
    }

    private func refreshClickChrome() {
        let clicksOn = allowClicks.state == .on
        clickModeControl.isEnabled = clicksOn
        clickModeLabel.textColor = clicksOn ? .secondaryLabelColor : .tertiaryLabelColor
        sensitivity.isEnabled = clicksOn && clickMode == .pinch
        pinchFeelLabel.isHidden = clickMode != .pinch
        sensitivity.isHidden = clickMode != .pinch
        pinchFeelLabel.textColor = sensitivity.isEnabled ? .secondaryLabelColor : .tertiaryLabelColor
        clickTest.isEnabled = clicksOn
        if clicksOn {
            subtitle.stringValue = clickMode == .dwell
                ? "Point with your index, then hold still ~0.65s to click. Move to cancel."
                : "Point with your index, then pinch thumb + index to click."
        } else {
            subtitle.stringValue = "Practice pointing first. Turn on Allow clicks only when you want real mouse clicks."
        }
    }

    @objc private func showWindow() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc private func toggleCamera() {
        if running { pause(); return }
        running = true; detector.reset(); dwell.reset(); filter.reset(); clickedUntil = 0
        lastHand = ProcessInfo.processInfo.systemUptime
        // Lock to the display containing this window for the duration of this session.
        if let number = window.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            targetDisplay = CGDirectDisplayID(number.uint32Value)
        }
        toggle.title = "Pause camera"
        status.stringValue = "Starting camera…"
        camera.start()
    }
    @objc private func pause() {
        running = false; camera.stop(); detector.reset(); dwell.reset(); filter.reset(); clickedUntil = 0; preview.update(nil)
        toggle.title = "Start camera"; status.stringValue = "Paused. Use your mouse normally, or start again."
    }
    @objc private func controlChanged() { detector.reset(); dwell.reset(); filter.reset(); clickedUntil = 0 }
    @objc private func allowClicksChanged() {
        UserDefaults.standard.set(allowClicks.state == .on, forKey: "allowClicks")
        detector.reset(); dwell.reset(); filter.reset(); clickedUntil = 0
        refreshClickChrome(); refresh()
    }
    @objc private func clickModeChanged() {
        clickMode = clickModeControl.selectedSegment == 1 ? .dwell : .pinch
        UserDefaults.standard.set(clickMode.rawValue, forKey: "clickMode")
        detector.reset(); dwell.reset(); filter.reset(); clickedUntil = 0
        refreshClickChrome(); refresh()
    }
    @objc private func sensitivityChanged() {
        let selected = min(2, max(0, sensitivity.selectedSegment))
        detector.settings.closeRatio = [0.34, 0.42, 0.50][selected]
        UserDefaults.standard.set(selected, forKey: "clickSensitivity")
        detector.reset(); dwell.reset(); clickedUntil = 0
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
        if trusted {
            if allowClicks.state != .on {
                permissionStatus.stringValue = "Accessibility on · Pointer OK · Clicks off until you allow them"
            } else if clickMode == .dwell {
                permissionStatus.stringValue = "Accessibility on · Dwell: hold still to click · Move after each click"
            } else {
                permissionStatus.stringValue = "Accessibility on · Pinch: touch thumb + index, then separate"
            }
        } else {
            permissionStatus.stringValue = "Needs Accessibility: tap Enable Accessibility → turn on Hand Mouse"
        }
        if running && ProcessInfo.processInfo.systemUptime - lastHand > 2 {
            detector.reset(); dwell.reset(); filter.reset(); preview.update(nil)
        }
    }
    private func handle(_ frame: HandFrame) {
        guard running else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - frame.timestamp < 0.20 else {
            detector.reset(); dwell.reset(); filter.reset(); preview.update(nil)
            status.stringValue = "Tracking delayed. Hold still briefly to reacquire your hand."
            return
        }
        let trusted = AXIsProcessTrusted()
        guard control.state == .on && trusted else {
            detector.reset(); dwell.reset(); filter.reset(); preview.update(frame)
            status.stringValue = control.state == .on ? "Enable permission for this copy of Hand Mouse. Use Show in Finder."
                : "Preview only — pointer control is off."
            return
        }
        guard let index = frame.points[.indexTip] else {
            if clickMode == .pinch {
                _ = detector.update(ratio: nil, time: frame.timestamp)
            } else {
                _ = dwell.update(point: .zero, time: frame.timestamp, tracking: false)
            }
            if frame.timestamp - lastHand > GestureTuning.trackingGraceSeconds { filter.reset() }
            preview.update(frame, phase: previewPhase)
            status.stringValue = "Looking for your index finger… Keep your hand visible."
            return
        }
        lastHand = frame.timestamp
        let freeze = clickMode == .dwell ? dwell.shouldFreeze : detector.shouldFreeze
        let location = filter.update(point: index, bounds: CGDisplayBounds(targetDisplay),
                                     time: frame.timestamp, freeze: freeze)
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: location, mouseButton: .left)?.post(tap: .cghidEventTap)
        let gestureFired: Bool
        if clickMode == .dwell {
            gestureFired = dwell.update(point: location, time: frame.timestamp, tracking: true)
        } else {
            gestureFired = detector.update(ratio: frame.pinchRatio, time: frame.timestamp)
        }
        let inject = SafetyPolicy.shouldInjectClick(
            gestureFired: gestureFired,
            allowClicks: allowClicks.state == .on,
            axTrusted: trusted,
            pointerControlEnabled: control.state == .on)
        if inject {
            // Create both events before posting either, so every press has a release.
            guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: location, mouseButton: .left),
                  let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: location, mouseButton: .left) else {
                status.stringValue = "Could not create a mouse click. Try again."
                return
            }
            down.setIntegerValueField(.mouseEventClickState, value: 1)
            up.setIntegerValueField(.mouseEventClickState, value: 1)
            down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
            clickedUntil = frame.timestamp + 0.35
        }
        preview.update(frame, phase: previewPhase, clicked: frame.timestamp < clickedUntil)
        if frame.timestamp < clickedUntil {
            status.stringValue = clickMode == .dwell
                ? "Click! Move slightly before the next dwell."
                : "Click! Separate thumb + index before the next click."
        } else if gestureFired && allowClicks.state != .on {
            status.stringValue = "Gesture recognized · Turn on Allow clicks to send a real click."
        } else if clickMode == .dwell {
            switch dwell.phase {
            case .idle: status.stringValue = "Dwell · Hold the pointer still to click."
            case .arming: status.stringValue = "Dwelling… Keep still. Move to cancel."
            case .needMove: status.stringValue = "Move a little, then hold still to click again."
            }
        } else if frame.pinchRatio == nil {
            status.stringValue = "Pointing · Show your thumb and palm to enable a pinch."
        } else {
            switch detector.phase {
            case .waitingForOpen: status.stringValue = "Separate thumb + index to get ready."
            case .ready: status.stringValue = "Ready · Aim, then pinch. Try Test click."
            case .confirming: status.stringValue = "Pinch detected… Hold briefly."
            case .held: status.stringValue = "Release the pinch to click again."
            }
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { pause(); return true }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func applicationWillTerminate(_ notification: Notification) {
        camera.stop(); timer?.invalidate()
        if let globalKey { NSEvent.removeMonitor(globalKey) }
        if let localKey { NSEvent.removeMonitor(localKey) }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
