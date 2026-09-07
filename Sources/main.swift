import AppKit
import AVFoundation
import Vision
import ApplicationServices

final class PreviewView: NSView {
    let preview: AVCaptureVideoPreviewLayer
    private let skeleton = CAShapeLayer()
    private let guide = CAShapeLayer()
    private var points: [VNHumanHandPoseObservation.JointName: CGPoint] = [:]

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
    func update(_ frame: HandFrame?) {
        if let connection = preview.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        points = frame?.points ?? [:]
        skeleton.strokeColor = (frame?.pinchRatio ?? 1) < GestureTuning.pinchCloseRatio ? NSColor.systemYellow.cgColor : NSColor.systemMint.cgColor
        drawHand()
    }
    private func drawHand() {
        // Capture is 4:3, matching this view; use an aspect-fit rect for resizing.
        let width = min(bounds.width, bounds.height * 4 / 3)
        let rect = CGRect(x: (bounds.width - width) / 2, y: (bounds.height - width * 3 / 4) / 2,
                          width: width, height: width * 3 / 4)
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
        guide.path = CGPath(roundedRect: rect.insetBy(dx: rect.width * 0.15, dy: rect.height * 0.15),
                            cornerWidth: 10, cornerHeight: 10, transform: nil)
        CATransaction.commit()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let camera = HandCamera()
    private var window: NSWindow!
    private var preview: PreviewView!
    private let status = NSTextField(wrappingLabelWithString: "Ready when you are. Start the camera to begin.")
    private let permissionStatus = NSTextField(labelWithString: "")
    private let toggle = NSButton(title: "Start camera", target: nil, action: nil)
    private let control = NSButton(checkboxWithTitle: "Control mouse pointer", target: nil, action: nil)
    private var statusItem: NSStatusItem!
    private var running = false
    private var detector = PinchDetector()
    private var filter = PointerFilter()
    private var lastHand = 0.0
    private var clickedUntil = 0.0
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

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 760),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Hand Mouse"
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.center()
        let content = NSView(); window.contentView = content
        let title = NSTextField(labelWithString: "Your hand. Your cursor.")
        title.font = .systemFont(ofSize: 28, weight: .bold)
        let subtitle = NSTextField(labelWithString: "Point to move. Touch thumb + index finger to click.")
        subtitle.textColor = .secondaryLabelColor
        preview = PreviewView(session: camera.session)
        preview.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([preview.widthAnchor.constraint(equalToConstant: 640), preview.heightAnchor.constraint(equalToConstant: 480)])
        status.font = .systemFont(ofSize: 14, weight: .medium)
        status.maximumNumberOfLines = 2
        permissionStatus.font = .systemFont(ofSize: 11)
        permissionStatus.textColor = .secondaryLabelColor
        toggle.target = self; toggle.action = #selector(toggleCamera)
        toggle.bezelStyle = .rounded
        control.state = .on; control.target = self; control.action = #selector(controlChanged)
        let permissions = NSButton(title: "Enable Accessibility", target: self, action: #selector(enableAccessibility))
        permissions.bezelStyle = .rounded
        let cameraSettings = NSButton(title: "Camera Settings", target: self, action: #selector(openCameraSettings))
        cameraSettings.bezelStyle = .rounded
        let buttons = NSStackView(views: [toggle, control, permissions, cameraSettings])
        buttons.spacing = 10
        let hint = NSTextField(labelWithString: "Keep your hand inside the dashed box • Esc pauses • Video stays on this Mac")
        hint.font = .systemFont(ofSize: 11); hint.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [title, subtitle, preview, status, permissionStatus, buttons, hint])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 30),
                                     stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
                                     stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -30)])
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
        localKey = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.pause(); return nil }; return event
        }
        globalKey = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.pause() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.refresh() }
        refresh(); showWindow()
    }

    @objc private func showWindow() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc private func toggleCamera() {
        if running { pause(); return }
        running = true; detector.reset(); filter.reset(); lastHand = ProcessInfo.processInfo.systemUptime
        // Lock to the display containing this window for the duration of this session.
        if let number = window.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            targetDisplay = CGDirectDisplayID(number.uint32Value)
        }
        toggle.title = "Pause camera"
        status.stringValue = "Starting camera…"
        camera.start()
    }
    @objc private func pause() {
        running = false; camera.stop(); detector.reset(); filter.reset(); preview.update(nil)
        toggle.title = "Start camera"; status.stringValue = "Paused. Use your mouse normally, or start again."
    }
    @objc private func controlChanged() { detector.reset(); filter.reset() }
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
        permissionStatus.stringValue = trusted ? "Accessibility enabled • Pinch once, then separate your fingers before the next click."
            : "Mouse control needs permission: Enable Accessibility → turn on Hand Mouse."
        if running && ProcessInfo.processInfo.systemUptime - lastHand > 2 {
            detector.reset(); filter.reset(); preview.update(nil)
        }
    }
    private func handle(_ frame: HandFrame?) {
        guard running else { return }
        // Never replay a delayed frame after the UI has been blocked.
        guard frame == nil || ProcessInfo.processInfo.systemUptime - frame!.timestamp < 0.25 else {
            detector.reset(); filter.reset(); return
        }
        preview.update(frame)
        guard let frame, let index = frame.points[.indexTip] else {
            detector.reset(); filter.reset()
            status.stringValue = "Looking for your hand… Show your palm and separate your fingers."
            return
        }
        lastHand = frame.timestamp
        guard control.state == .on && AXIsProcessTrusted() else {
            detector.reset(); filter.reset()
            status.stringValue = "Hand detected. \(control.state == .on ? "Enable Accessibility to move the pointer." : "Preview only — mouse control is off.")"
            return
        }
        let click = detector.update(ratio: frame.pinchRatio, time: frame.timestamp)
        let location = filter.update(point: index, bounds: CGDisplayBounds(targetDisplay),
                                     time: frame.timestamp, freeze: frame.pinchRatio < GestureTuning.pointerFreezeRatio)
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: location, mouseButton: .left)?.post(tap: .cghidEventTap)
        if click {
            // Always pair down/up; holding a pinch never leaves a mouse button held.
            let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: location, mouseButton: .left)
            let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: location, mouseButton: .left)
            down?.setIntegerValueField(.mouseEventClickState, value: 1)
            up?.setIntegerValueField(.mouseEventClickState, value: 1)
            down?.post(tap: .cghidEventTap); up?.post(tap: .cghidEventTap)
            clickedUntil = frame.timestamp + 0.4
        }
        status.stringValue = frame.timestamp < clickedUntil ? "Click! Separate your fingers to click again."
            : "Tracking • Move your index finger. Pinch thumb + index to click."
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
