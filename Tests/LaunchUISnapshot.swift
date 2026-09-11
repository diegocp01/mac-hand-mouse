import AppKit

/// Renders the production launch layout with inert controls and a camera-free
/// preview. This executable never requests camera access or posts system input.
@main
enum LaunchUISnapshot {
    private enum State: String { case ready, settings, practice, permissions }
    private static let actionTarget = InertActionTarget()

    private struct Fixture {
        let content: LaunchContentView
        let guide: GestureGuideView
        let start: NSButton
        let settings: NSButton
        let practice: PracticeView
        let setup: NSView
        let settingsRows: NSView
    }

    static func main() throws {
        _ = NSApplication.shared
        verifyMaterialPreferences()
        verifyWindowChrome()
        let destination = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/private/tmp")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        for useNativeGlass in [false, true] {
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                for size in [NSSize(width: 920, height: 720), NSSize(width: 720, height: 650), NSSize(width: 720, height: 628)] {
                    for state in [State.ready, .settings, .practice, .permissions] {
                        try render(size: size, appearance: appearance, state: state,
                            destination: destination, useNativeGlass: useNativeGlass)
                    }
                }
            }
        }
        print("Launch layout: 48 material, size, appearance, and disclosure states passed.")
    }

    private static func verifyMaterialPreferences() {
        let normal = SurfacePreferences()
        precondition(normal.allowsTransparency && normal.panelOpacity < 1 && normal.raisedPanelOpacity < 1,
            "Standard panels should be translucent without fading their content")
        precondition(normal.transitionDuration > 0 && SurfacePreferences(reduceMotion: true).transitionDuration == 0,
            "Reduce Motion must disable cosmetic transitions")
        let backdrop = WindowBackdropView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
        let effect = backdrop.subviews.compactMap { $0 as? NSVisualEffectView }.first!
        for preferences in [normal, SurfacePreferences(reduceTransparency: true), SurfacePreferences(increaseContrast: true)] {
            backdrop.setPreferencesForRendering(preferences)
            precondition(effect.isHidden == !preferences.allowsTransparency, "Accessibility preferences must disable background blur")
            precondition(backdrop.isOpaque == !preferences.allowsTransparency, "The material fallback must be opaque")
            precondition(backdrop.hitTest(NSPoint(x: 10, y: 10)) == nil, "The backdrop cannot intercept input")
            precondition(backdrop.alphaValue == 1, "Only materials, not the entire view, may be translucent")
            if !preferences.allowsTransparency {
                precondition(preferences.panelOpacity == 1 && preferences.raisedPanelOpacity == 1,
                    "Reduced transparency and high contrast need solid panels")
                precondition(backdrop.layer?.backgroundColor?.alpha == 1, "The opaque fallback must fill the window")
            }
        }
        precondition(effect.blendingMode == .behindWindow && effect.state == .followsWindowActiveState,
            "Native material should follow window activation")
    }

    private static func verifyWindowChrome() {
        let fixture = makeFixture(state: .ready)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 720),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.contentView = fixture.content
        fixture.content.layoutSubtreeIfNeeded()
        fixture.content.layoutSubtreeIfNeeded()
        let content = fixture.content
        precondition(content.safeAreaInsets.top > 0, "Window controls need a protected titlebar safe area")
        precondition(content.bounds.height > window.contentLayoutRect.height, "The backdrop must extend underneath the titlebar")
        let settings = fixture.settings.convert(fixture.settings.bounds, to: content)
        precondition(settings.maxY <= content.bounds.maxY - content.safeAreaInsets.top,
            "Custom header controls cannot overlap the titlebar")
        let backdrop = content.subviews.compactMap { $0 as? WindowBackdropView }.first!
        precondition(backdrop.frame == content.bounds, "Frosted material must cover the titlebar as well as the content")
        window.close()
    }

    private static func makeFixture(state: State, useNativeGlass: Bool = true) -> Fixture {
        let title = NSTextField(labelWithString: "Hand Mouse")
        let cameraStatus = NSTextField(labelWithString: state == .practice ? "Practice only" : "Camera off")
        cameraStatus.font = .systemFont(ofSize: 11, weight: .medium)
        cameraStatus.textColor = StartupStyle.muted
        let start = NSButton(title: state == .practice ? "Pause" : "Start", target: nil, action: nil)
        start.bezelStyle = .rounded
        start.controlSize = .large
        start.image = NSImage(systemSymbolName: state == .practice ? "pause.fill" : "play.fill", accessibilityDescription: nil)
        start.imagePosition = .imageLeading
        start.keyEquivalent = "\r"
        start.setAccessibilityLabel(state == .practice ? "Pause camera tracking" : "Start camera tracking")
        let practiceButton = NSButton(title: state == .practice ? "Finish practice" : "Practice", target: nil, action: nil)
        practiceButton.bezelStyle = .rounded
        practiceButton.font = .systemFont(ofSize: 13, weight: .medium)
        practiceButton.keyEquivalent = "t"
        practiceButton.keyEquivalentModifierMask = [.command, .shift]
        let settings = NSButton(title: "Settings", target: nil, action: nil)
        settings.setButtonType(.pushOnPushOff)
        settings.bezelStyle = .rounded
        settings.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: nil)
        settings.imagePosition = .imageLeading
        settings.setAccessibilityLabel("Settings")
        settings.state = state == .settings ? .on : .off

        let guide = GestureGuideView(frame: .zero)
        guide.select(.move)
        guide.setDemoTimeForRendering(0)
        guide.update(active: nil, scrollingEnabled: state != .practice, selectionEnabled: false)
        let feedback = ClickFeedbackView(frame: .zero)
        let practice = PracticeView(frame: .zero)
        practice.isHidden = state != .practice
        if state == .practice {
            feedback.update(title: "Practice only · No system input", detail: "Aim at Send. Raise middle + index and hold for one second.")
        }

        func checkbox(_ title: String, enabled: Bool = true) -> NSButton {
            let button = NSButton(checkboxWithTitle: title, target: nil, action: nil)
            button.state = enabled ? .on : .off
            return button
        }
        let pointerControls = NSStackView(views: [checkbox("Move pointer"), checkbox("Click"), checkbox("Scroll")])
        let extraControls = NSStackView(views: [checkbox("Steady aim"), checkbox("Precision", enabled: false), checkbox("Select text", enabled: false)])
        for row in [pointerControls, extraControls] { row.alignment = .centerY; row.spacing = 20 }
        let testClick = NSButton(title: "Test click", target: nil, action: nil)
        testClick.bezelStyle = .rounded
        let display = NSTextField(labelWithString: "Pointer display follows the app window when you start.")
        display.font = .systemFont(ofSize: 11)
        display.textColor = StartupStyle.muted
        let settingsRows = StartupStyle.column([pointerControls, extraControls, testClick, display], spacing: 12)
        for row in [pointerControls, extraControls] {
            row.translatesAutoresizingMaskIntoConstraints = false
            row.distribution = .fillEqually
            row.widthAnchor.constraint(equalTo: settingsRows.widthAnchor).isActive = true
        }
        settingsRows.isHidden = state != .settings

        let disclosure = NSButton(title: "", target: nil, action: nil)
        disclosure.bezelStyle = .disclosure
        disclosure.setButtonType(.pushOnPushOff)
        disclosure.state = state == .permissions ? .on : .off
        disclosure.setAccessibilityLabel("Permissions and app setup")
        let permissions = NSTextField(labelWithString: state == .permissions ? "Permissions · Action needed" : "Permissions")
        permissions.font = .systemFont(ofSize: 12, weight: .medium)
        let setupDisclosure = NSStackView(views: [disclosure, permissions])
        setupDisclosure.spacing = 6
        let permissionStatus = NSTextField(wrappingLabelWithString: "Enable Hand Mouse in Accessibility.")
        permissionStatus.font = .systemFont(ofSize: 11)
        permissionStatus.textColor = .secondaryLabelColor
        let permissionButtons = ["Enable Accessibility", "Camera Settings", "Show in Finder"].map { title in
            let button = NSButton(title: title, target: nil, action: nil)
            button.bezelStyle = .rounded
            return button
        }
        let setupActions = NSStackView(views: permissionButtons)
        setupActions.spacing = 10
        let shortcut = NSPopUpButton(frame: .zero, pullsDown: false)
        shortcut.addItems(withTitles: ["⌃⌥⌘H", "⌃⌥⌘M", "Off"])
        shortcut.setAccessibilityLabel("Global camera pause and resume shortcut")
        let shortcutRow = NSStackView(views: [NSTextField(labelWithString: "Pause / resume anywhere"), shortcut])
        shortcutRow.spacing = 8
        let shortcutStatus = NSTextField(wrappingLabelWithString: "Use the shortcut to pause or resume camera tracking.")
        shortcutStatus.font = .systemFont(ofSize: 11)
        shortcutStatus.textColor = .secondaryLabelColor
        let setupRows = StartupStyle.column([permissionStatus, setupActions, shortcutRow, shortcutStatus], spacing: 8)
        for row in [setupActions, shortcutRow] {
            row.translatesAutoresizingMaskIntoConstraints = false
            row.widthAnchor.constraint(equalTo: setupRows.widthAnchor).isActive = true
        }
        setupActions.distribution = .fillEqually
        permissionStatus.widthAnchor.constraint(equalTo: setupRows.widthAnchor).isActive = true
        shortcutStatus.widthAnchor.constraint(equalTo: setupRows.widthAnchor).isActive = true
        setupRows.isHidden = state != .permissions
        let preview = InertPreviewView(frame: .zero)
        preview.isHidden = state == .practice

        let content = LaunchContentView(title: title, cameraStatus: cameraStatus, start: start,
            practiceButton: practiceButton, settingsButton: settings, guide: guide,
            preview: preview, feedback: feedback, practice: practice,
            setupDisclosure: setupDisclosure, setupRows: setupRows, settingsRows: settingsRows, useNativeGlass: useNativeGlass)
        for button in UIRenderSupport.descendants(of: content).compactMap({ $0 as? NSButton }) where button.action == nil {
            button.target = actionTarget
            button.action = #selector(InertActionTarget.activate(_:))
        }
        return Fixture(content: content, guide: guide, start: start, settings: settings,
                       practice: practice, setup: setupRows, settingsRows: settingsRows)
    }

    private static func render(size: NSSize, appearance: NSAppearance.Name,
                               state: State, destination: URL, useNativeGlass: Bool) throws {
        let fixture = makeFixture(state: state, useNativeGlass: useNativeGlass)
        let content = fixture.content
        content.appearance = NSAppearance(named: appearance)
        // A nonvisible host supplies normal AppKit window/appearance context. It
        // never becomes key, orders onscreen, or owns camera/input controllers.
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = content
        try UIRenderSupport.prepare(content, size: size)
        content.layoutSubtreeIfNeeded() // Settle the guide's width-dependent row arrangement.

        let theme = appearance == .darkAqua ? "dark" : "light"
        let dimensions = (useNativeGlass ? "" : "legacy-") + (size.width == 920 ? "default" : (size.height == 628 ? "minimum-window" : "minimum"))
        let context = "\(dimensions) / \(theme) / \(state.rawValue)"
        precondition(content.bounds.size == size, "Launch content changed the requested window size in \(context)")
        let ambiguous = UIRenderSupport.ambiguousViews(in: content).filter(isVisible)
        precondition(ambiguous.isEmpty, "Ambiguous layout in \(context): \(ambiguous.map { "\(type(of: $0)): frame \($0.frame), fitting \($0.fittingSize)" })")
        let clipped = UIRenderSupport.fullyClippedControls(in: content).filter(isVisible)
        precondition(clipped.isEmpty, "Fully clipped controls in \(context)")
        let backdrop = content.subviews.compactMap { $0 as? WindowBackdropView }.first!
        precondition(backdrop.frame == content.bounds, "The frosted backdrop must cover the content in \(context)")
        precondition(content.layer?.backgroundColor?.alpha == 0 && content.alphaValue == 1 && fixture.start.alphaValue == 1,
            "Window materials must not fade controls or be covered by an opaque root layer")
#if compiler(>=6.2)
        if #available(macOS 26.0, *), useNativeGlass {
            let glass = UIRenderSupport.descendants(of: content).compactMap { $0 as? NSGlassEffectView }.first!
            let preferences = SurfacePreferences.current
            precondition(glass.style == (preferences.allowsTransparency ? .clear : .regular),
                "Native glass style must follow transparency preferences")
#if compiler(>=6.4)
            if #available(macOS 27.0, *) {
                precondition(glass.effectIsInteractive == (preferences.allowsTransparency && !preferences.reduceMotion),
                    "Interactive glass must respect Reduce Motion")
            }
#endif
        }
#endif

        if !useNativeGlass {
            let surface = UIRenderSupport.descendants(of: content).compactMap { $0 as? GlassControlSurface }.first!
            precondition(surface.subviews.contains { $0 is NSVisualEffectView }, "Legacy coverage must use the actual visual-effect fallback")
        }

        let gestureLabels = Set(["Move", "Click", "Right click", "Scroll", "Select text"])
        let cards = UIRenderSupport.descendants(of: fixture.guide).compactMap { $0 as? NSButton }.filter { gestureLabels.contains($0.accessibilityLabel() ?? "") }
        precondition(cards.count == GestureAction.allCases.count, "Missing gesture cards in \(context)")
        let labels = Set(cards.compactMap { $0.accessibilityLabel() })
        precondition(labels == gestureLabels, "Incomplete gesture accessibility labels in \(context)")
        for card in cards {
            let rect = card.convert(card.bounds, to: fixture.guide)
            precondition(isVisible(card) && rect.width > 100 && rect.height >= 60 && fixture.guide.bounds.contains(rect),
                         "Gesture card clipped inside its guide in \(context)")
            precondition(card.acceptsFirstResponder && !(card.accessibilityHelp() ?? "").isEmpty,
                         "Gesture instruction or keyboard access missing in \(context)")
        }
        precondition(abs(fixture.guide.bounds.height - 280) < 1,
                     "Guide did not adapt to available width in \(context)")
        precondition(fixture.start.keyEquivalent == "\r", "Start must retain its Return shortcut")
        precondition(fixture.start.accessibilityLabel() == (state == .practice ? "Pause camera tracking" : "Start camera tracking"), "Start must remain accessible")
        let startRect = fixture.start.convert(fixture.start.bounds, to: content)
        precondition(content.bounds.contains(startRect), "Start outside the launch window in \(context)")
        precondition(content.bounds.contains(fixture.settings.convert(fixture.settings.bounds, to: content)),
                     "Settings outside the launch window in \(context)")

        // Selecting a learning card exercises only the guide callback. Disabled
        // optional gestures remain discoverable without enabling system input.
        var selected: GestureAction?
        fixture.guide.onSelect = { selected = $0 }
        let scrollCard = cards.first { $0.accessibilityLabel() == "Scroll" }!
        scrollCard.performClick(nil)
        precondition(selected == .scroll, "Gesture card activation failed in \(context)")
        fixture.guide.select(.move)

        // The app reveals the requested section after toggling it. Mirror that
        // camera-free view operation so snapshots show the actual entry state.
        let revealed: NSView?
        switch state {
        case .ready: revealed = nil
        case .settings: revealed = fixture.settingsRows
        case .practice: revealed = fixture.practice
        case .permissions: revealed = fixture.setup
        }
        if let revealed, let scroll = revealed.enclosingScrollView, let document = scroll.documentView {
            StartupStyle.reveal(revealed, preferences: SurfacePreferences(reduceMotion: true))
            content.layoutSubtreeIfNeeded()
            let target = revealed.convert(revealed.bounds, to: document)
            precondition(scroll.contentView.documentVisibleRect.contains(target),
                         "Requested section is not visible in \(context)")
            precondition(fixture.start.convert(fixture.start.bounds, to: content) == startRect,
                         "Start moved when revealing a section in \(context)")
        }

        let output = destination.appendingPathComponent("launch-\(dimensions)-\(theme)-\(state.rawValue).png")
        try UIRenderSupport.writePNG(of: content, size: size, to: output)
        print(output.path)

        if let scroll = UIRenderSupport.descendants(of: content).compactMap({ $0 as? NSScrollView }).first,
           let document = scroll.documentView, document.bounds.height > scroll.contentView.bounds.height {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: document.bounds.height - scroll.contentView.bounds.height))
            scroll.reflectScrolledClipView(scroll.contentView)
            content.layoutSubtreeIfNeeded()
            precondition(fixture.start.convert(fixture.start.bounds, to: content) == startRect,
                         "Start moved with overflowing content in \(context)")
            if state == .practice {
                precondition(scroll.contentView.documentVisibleRect.intersects(fixture.practice.convert(fixture.practice.bounds, to: document)),
                             "Practice cannot be reached by scrolling in \(context)")
            }
            if state == .permissions {
                precondition(scroll.contentView.documentVisibleRect.intersects(fixture.setup.convert(fixture.setup.bounds, to: document)),
                             "Permissions cannot be reached by scrolling in \(context)")
            }
        }
        if state == .ready && size.width == 920 {
            for resized in [NSSize(width: 1200, height: 720), NSSize(width: 720, height: 628)] {
                window.setContentSize(resized)
                content.layoutSubtreeIfNeeded()
                content.layoutSubtreeIfNeeded()
                precondition(content.bounds.size == resized, "Launch content shrank while resizing to \(resized)")
                precondition(abs(fixture.guide.bounds.height - 280) < 1,
                             "Gesture guide did not reflow after resizing to \(resized)")
                precondition(content.bounds.contains(fixture.start.convert(fixture.start.bounds, to: content)),
                             "Start left the viewport after resizing to \(resized)")
            }
        }
        window.close()
    }

    private static func isVisible(_ view: NSView) -> Bool {
        var candidate: NSView? = view
        while let current = candidate {
            if current.isHidden || current.alphaValue == 0 { return false }
            candidate = current.superview
        }
        return true
    }
}

private final class InertPreviewView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 18
        layer?.borderWidth = 1
        let hand = StandbyReticleView(frame: .zero)
        hand.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hand)
        NSLayoutConstraint.activate([
            hand.centerXAnchor.constraint(equalTo: centerXAnchor),
            hand.centerYAnchor.constraint(equalTo: centerYAnchor),
            hand.widthAnchor.constraint(equalToConstant: 82),
            hand.heightAnchor.constraint(equalToConstant: 82)
        ])
        setAccessibilityElement(false)
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
}

private final class InertActionTarget: NSObject {
    @objc func activate(_ sender: Any?) {}
}
