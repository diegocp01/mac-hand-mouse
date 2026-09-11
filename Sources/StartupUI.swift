import AppKit
import QuartzCore

struct SurfacePreferences {
    var reduceTransparency = false
    var increaseContrast = false
    var reduceMotion = false

    var allowsTransparency: Bool { !reduceTransparency && !increaseContrast }
    var panelOpacity: CGFloat { allowsTransparency ? 0.62 : 1 }
    var raisedPanelOpacity: CGFloat { allowsTransparency ? 0.84 : 1 }
    var transitionDuration: TimeInterval { reduceMotion ? 0 : 0.18 }

    static var current: Self {
        let workspace = NSWorkspace.shared
        return Self(reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
                    increaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast,
                    reduceMotion: workspace.accessibilityDisplayShouldReduceMotion)
    }
}

/// Neutral surfaces follow the Mac's appearance; color is reserved for state.
enum StartupStyle {
    static let background = NSColor.windowBackgroundColor
    static let surface = NSColor(name: nil) { appearance in
        NSColor(white: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? 0.17 : 0.985,
                alpha: SurfacePreferences.current.panelOpacity)
    }
    static let raisedSurface = NSColor(name: nil) { appearance in
        NSColor(white: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? 0.24 : 1,
                alpha: SurfacePreferences.current.raisedPanelOpacity)
    }
    static let accent = NSColor.controlAccentColor
    // Kept as an alias for existing live-state consumers.
    static let mint = NSColor.controlAccentColor
    static let text = NSColor.labelColor
    static let muted = NSColor.secondaryLabelColor
    static let border = NSColor(name: nil) { _ in
        SurfacePreferences.current.increaseContrast
            ? NSColor.labelColor.withAlphaComponent(0.65) : NSColor.separatorColor
    }

    static func transitionBackground(of view: NSView, to color: NSColor, animated: Bool) {
        guard let layer = view.layer else { return }
        let previous = layer.presentation()?.backgroundColor ?? layer.backgroundColor
        let next = color.cgColor
        layer.removeAnimation(forKey: "surfaceHighlight")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.backgroundColor = next
        CATransaction.commit()
        let duration = SurfacePreferences.current.transitionDuration
        guard animated, view.window?.isVisible == true, duration > 0, let previous, previous != next else { return }
        let animation = CABasicAnimation(keyPath: "backgroundColor")
        animation.fromValue = previous; animation.toValue = next
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: "surfaceHighlight")
    }

    static func reveal(_ view: NSView, preferences: SurfacePreferences = .current) {
        view.window?.contentView?.layoutSubtreeIfNeeded()
        guard preferences.transitionDuration > 0, view.window?.isVisible == true,
              let scroll = view.enclosingScrollView else {
            view.scrollToVisible(view.bounds); return
        }
        let clip = scroll.contentView
        let origin = clip.bounds.origin
        view.scrollToVisible(view.bounds)
        let destination = clip.bounds.origin
        guard origin != destination else { return }
        clip.setBoundsOrigin(origin)
        scroll.reflectScrolledClipView(clip)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = preferences.transitionDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            clip.animator().setBoundsOrigin(destination)
        } completionHandler: { [weak scroll] in
            if let scroll { scroll.reflectScrolledClipView(scroll.contentView) }
        }
    }

    static func column(_ views: [NSView], spacing: CGFloat = 10) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        return stack
    }
}

final class WindowBackdropView: NSView {
    private let effect = NSVisualEffectView(frame: .zero)
    private var displayObserver: NSObjectProtocol?
    private var forcedPreferences: SurfacePreferences?
    private var preferences: SurfacePreferences { forcedPreferences ?? .current }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setAccessibilityElement(false)
        effect.material = .underWindowBackground
        effect.blendingMode = .behindWindow
        effect.state = .followsWindowActiveState
        effect.setAccessibilityElement(false)
        effect.translatesAutoresizingMaskIntoConstraints = false
        addSubview(effect)
        NSLayoutConstraint.activate([
            effect.leadingAnchor.constraint(equalTo: leadingAnchor),
            effect.trailingAnchor.constraint(equalTo: trailingAnchor),
            effect.topAnchor.constraint(equalTo: topAnchor),
            effect.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        displayObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refreshAppearance() }
        refreshAppearance()
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isOpaque: Bool { !preferences.allowsTransparency }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    deinit {
        if let displayObserver { NSWorkspace.shared.notificationCenter.removeObserver(displayObserver) }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    func setPreferencesForRendering(_ preferences: SurfacePreferences?) {
        forcedPreferences = preferences
        refreshAppearance()
    }

    private func refreshAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            effect.isHidden = !preferences.allowsTransparency
            layer?.backgroundColor = (preferences.allowsTransparency ? NSColor.clear : StartupStyle.background).cgColor
        }
    }
}

/// One glass surface for the primary controls. Native materials adapt to the
/// system's appearance and transparency preferences, including on older Macs.
final class GlassControlSurface: NSView {
    private var displayObserver: NSObjectProtocol?
    private var material: NSView?

    init(content: NSView, cornerRadius: CGFloat = 24) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.borderWidth = 1

        let material = Self.makeMaterial(content: content, cornerRadius: cornerRadius)
        self.material = material
        material.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(material)
        NSLayoutConstraint.activate([
            material.leadingAnchor.constraint(equalTo: leadingAnchor),
            material.trailingAnchor.constraint(equalTo: trailingAnchor),
            material.topAnchor.constraint(equalTo: topAnchor),
            material.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.leadingAnchor.constraint(equalTo: material.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: material.trailingAnchor),
            content.topAnchor.constraint(equalTo: material.topAnchor),
            content.bottomAnchor.constraint(equalTo: material.bottomAnchor)
        ])
        displayObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.refreshAppearance() }
        refreshAppearance()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let displayObserver { NSWorkspace.shared.notificationCenter.removeObserver(displayObserver) }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    private static func makeMaterial(content: NSView, cornerRadius: CGFloat) -> NSView {
        // Xcode versions before 26 do not declare NSGlassEffectView. A runtime
        // availability check alone would still fail to compile with their SDKs.
#if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: .zero)
            glass.style = .regular
            glass.cornerRadius = cornerRadius
            glass.contentView = content
            return glass
        }
#endif
        let frost = NSVisualEffectView(frame: .zero)
        frost.material = .sidebar
        frost.blendingMode = .behindWindow
        frost.state = .followsWindowActiveState
        frost.wantsLayer = true
        frost.layer?.cornerRadius = cornerRadius
        frost.layer?.masksToBounds = true
        frost.addSubview(content)
        return frost
    }

    private func refreshAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let preferences = SurfacePreferences.current
            layer?.backgroundColor = (preferences.allowsTransparency ? NSColor.clear : .controlBackgroundColor).cgColor
            layer?.borderColor = StartupStyle.border.cgColor
            layer?.borderWidth = preferences.increaseContrast ? 1.5 : 0.5
#if compiler(>=6.2)
            if #available(macOS 26.0, *), let glass = material as? NSGlassEffectView {
                glass.style = preferences.allowsTransparency ? .clear : .regular
#if compiler(>=6.4)
                if #available(macOS 27.0, *) {
                    glass.effectIsInteractive = preferences.allowsTransparency && !preferences.reduceMotion
                }
#endif
            }
#endif
        }
    }
}

/// The four actions presented by the visual gesture guide.
enum GestureAction: CaseIterable {
    case move
    case click
    case rightClick
    case scroll
    case select

    fileprivate var title: String {
        switch self {
        case .move: return "Move"
        case .click: return "Click"
        case .rightClick: return "Right click"
        case .scroll: return "Scroll"
        case .select: return "Select text"
        }
    }

    fileprivate var instruction: String {
        switch self {
        case .move: return "Show hand · Move"
        case .click: return "Raise two · Hold 1 s"
        case .rightClick: return "Five tips together"
        case .scroll: return "Three tips · Move"
        case .select: return "Two L hands · move"
        }
    }

    fileprivate var accessibilityDescription: String {
        switch self {
        case .move:
            return "Show your hand and move to aim. The pointer follows your index fingertip; no special pose is needed."
        case .click:
            return "Open your hand to aim, then raise index and middle with the other fingers curled. Hold for one second while the ring fills. Open your hand before another click."
        case .rightClick:
            return "Bring all five fingertips together in a pinch, keeping them visible to the camera. Hold briefly to right-click once. Open the hand before the next right-click."
        case .scroll:
            return "Bring the thumb, index, and middle fingertips together, hold briefly, then move the hand vertically to scroll. Release the three-finger pinch to stop."
        case .select:
            return "First acquire the primary hand. Add a second hand with both thumbs and index fingers forming L shapes and the other fingers folded. Move only the primary hand. Open either L shape to release."
        }
    }
}

/// A single deterministic frame from the five-second tutorial loop. Keeping the
/// result state in this camera-free model lets review tools sample meaningful
/// phases without starting capture or waiting on wall-clock animation.
struct GestureDemoSample {
    enum HandPose { case point, raised, allPinch, threePinch, lShape, open }
    let primaryPose: HandPose
    let secondaryPose: HandPose?
    let primaryX: CGFloat
    let primaryY: CGFloat
    let resultProgress: CGFloat
    let gestureHeld: Bool
    let resultActivated: Bool
    let stage: String
}

enum GestureDemoTimeline {
    static let duration: TimeInterval = 5
    static let clickHoldStart: TimeInterval = 1.50
    static let clickTime: TimeInterval = 2.50

    static func sample(action: GestureAction, seconds: TimeInterval) -> GestureDemoSample {
        let raw = seconds.truncatingRemainder(dividingBy: duration)
        let t = CGFloat((raw < 0 ? raw + duration : raw) / duration)
        func ramp(_ start: CGFloat, _ end: CGFloat) -> CGFloat {
            let value = max(0, min(1, (t - start) / (end - start)))
            return value * value * (3 - 2 * value)
        }
        switch action {
        case .move:
            let travel = t < 0.72 ? ramp(0.16, 0.64) : 1 - ramp(0.76, 0.98)
            return GestureDemoSample(primaryPose: .point, secondaryPose: nil,
                                     primaryX: travel, primaryY: 0.5,
                                     resultProgress: travel, gestureHeld: false,
                                     resultActivated: false,
                                     stage: t < 0.16 ? "Show your hand" : "Move to aim")
        case .click:
            let elapsed = secondsInLoop(seconds)
            let held = elapsed >= clickHoldStart && elapsed < 3.5
            let activated = elapsed >= clickTime && elapsed < 3.5
            return GestureDemoSample(primaryPose: held ? .raised : .point,
                secondaryPose: nil, primaryX: 0.46, primaryY: 0.5,
                resultProgress: held ? min(1, CGFloat(elapsed - clickHoldStart)) : 0,
                gestureHeld: held, resultActivated: activated,
                stage: activated ? "Clicked · lower middle" : (held ? "Hold two fingers · 1 second" : "Aim with index only"))
        case .rightClick:
            let held = t >= 0.30 && t < 0.70
            let activated = t >= 0.34 && t < 0.70
            return GestureDemoSample(primaryPose: held ? .allPinch : .open,
                secondaryPose: nil, primaryX: 0.46, primaryY: 0.5,
                resultProgress: activated ? 1 : 0, gestureHeld: held, resultActivated: activated,
                stage: held ? "Five tips together · right click" : "Open to prepare")
        case .scroll:
            let held = t >= 0.20 && t < 0.72
            let travel = t < 0.20 ? 0 : (t < 0.64 ? ramp(0.24, 0.64) : 1)
            return GestureDemoSample(primaryPose: held ? .threePinch : .open,
                                     secondaryPose: nil, primaryX: 0.48,
                                     primaryY: 0.24 + travel * 0.52,
                                     resultProgress: travel, gestureHeld: held,
                                     resultActivated: false,
                                     stage: t < 0.20 ? "Pinch to hold" : (held ? "Move vertically" : "Open to stop"))
        case .select:
            let paired = t >= 0.22 && t < 0.76
            let travel = t < 0.34 ? 0 : (t < 0.68 ? ramp(0.34, 0.68) : 1)
            return GestureDemoSample(primaryPose: paired ? .lShape : (t < 0.22 ? .point : .open),
                                     secondaryPose: paired ? .lShape : (t >= 0.76 ? .open : nil),
                                     primaryX: travel, primaryY: 0.5,
                                     resultProgress: travel, gestureHeld: paired,
                                     resultActivated: false,
                                     stage: t < 0.22 ? "Acquire one hand" : (paired ? "Move your first hand" : "Open either hand"))
        }
    }

    private static func secondsInLoop(_ seconds: TimeInterval) -> TimeInterval {
        let raw = seconds.truncatingRemainder(dividingBy: duration)
        return raw < 0 ? raw + duration : raw
    }
}

/// Keyboard-accessible selectors stay independent from the large tutorial. Live
/// badges describe camera state only in the selector strip; the canvas is always
/// clearly a demonstration and never produces system input.
final class GestureGuideView: NSView {
    var onSelect: ((GestureAction) -> Void)?

    private var selectedAction: GestureAction = .move
    private var cards: [GestureAction: GestureSelectorButton] = [:]
    private let demo = GestureDemoCanvas()
    private let playback = NSButton(title: "Ⅱ", target: nil, action: nil)
    private var timer: Timer?
    private var loopStart = ProcessInfo.processInfo.systemUptime
    private var pausedAt: TimeInterval = 0
    private var isPaused = false
    private var forcedDemoTime: TimeInterval?
    private var forcedReduceMotion: Bool?
    private var notificationTokens: [NSObjectProtocol] = []
    private var hostNotificationTokens: [NSObjectProtocol] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Gesture tutorial")

        for action in GestureAction.allCases {
            let card = GestureSelectorButton(action: action)
            card.onActivate = { [weak self] selected in
                self?.select(selected)
                self?.onSelect?(selected)
            }
            cards[action] = card
        }

        let selectorRow = NSStackView(views: GestureAction.allCases.compactMap { cards[$0] })
        selectorRow.orientation = .horizontal
        selectorRow.alignment = .centerY
        selectorRow.distribution = .fillEqually
        selectorRow.spacing = 8
        cards.values.forEach { $0.heightAnchor.constraint(equalTo: selectorRow.heightAnchor).isActive = true }

        playback.isBordered = false
        playback.font = .systemFont(ofSize: 13, weight: .semibold)
        playback.contentTintColor = StartupStyle.text
        playback.wantsLayer = true
        playback.layer?.cornerRadius = 8
        playback.layer?.backgroundColor = StartupStyle.muted.withAlphaComponent(0.12).cgColor
        playback.focusRingType = .exterior
        playback.target = self
        playback.action = #selector(togglePlayback)
        playback.setAccessibilityLabel("Pause gesture demonstration")

        for view in [selectorRow, demo, playback] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            selectorRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            selectorRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            selectorRow.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            selectorRow.heightAnchor.constraint(equalToConstant: 64),
            demo.leadingAnchor.constraint(equalTo: selectorRow.leadingAnchor),
            demo.trailingAnchor.constraint(equalTo: selectorRow.trailingAnchor),
            demo.topAnchor.constraint(equalTo: selectorRow.bottomAnchor, constant: 8),
            demo.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            playback.trailingAnchor.constraint(equalTo: demo.trailingAnchor, constant: -12),
            playback.topAnchor.constraint(equalTo: demo.topAnchor, constant: 10),
            playback.widthAnchor.constraint(equalToConstant: 30),
            playback.heightAnchor.constraint(equalToConstant: 28),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 280),
            heightAnchor.constraint(lessThanOrEqualToConstant: 390)
        ])

        let center = NotificationCenter.default
        notificationTokens = [
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.updateAnimationLifecycle() },
            center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.stopTimer() }
        ]
        notificationTokens.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.updateAnimationLifecycle()
            self?.cards.values.forEach { $0.refreshPresentation() }
            self?.demo.refreshAppearance()
        })
        select(.move)
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        stopTimer()
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
        if let workspaceToken = notificationTokens.last {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceToken)
        }
        hostNotificationTokens.forEach(NotificationCenter.default.removeObserver)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshHostObservers()
        updateAnimationLifecycle()
    }

    override func viewDidHide() {
        super.viewDidHide()
        stopTimer()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        updateAnimationLifecycle()
    }

    func select(_ action: GestureAction) {
        selectedAction = action
        cards.forEach { $0.value.isLearningSelection = $0.key == action }
        demo.action = action
        resetLoop()
    }

    func update(active: GestureAction?, scrollingEnabled: Bool, selectionEnabled: Bool) {
        for (action, card) in cards {
            card.featureEnabled = action == .scroll ? scrollingEnabled : (action == .select ? selectionEnabled : true)
            card.isLive = active == action && card.featureEnabled
        }
    }

    /// Deterministic render injection used by camera-free screenshots. Passing nil
    /// returns the view to normal lifecycle-managed playback.
    func setDemoTimeForRendering(_ seconds: TimeInterval?) {
        forcedDemoTime = seconds
        if let seconds {
            stopTimer()
            demo.sample = GestureDemoTimeline.sample(action: selectedAction, seconds: seconds)
        } else {
            resetLoop()
            updateAnimationLifecycle()
        }
    }

    func setReduceMotionForRendering(_ enabled: Bool?) {
        forcedReduceMotion = enabled
        updateAnimationLifecycle()
    }

    @objc private func togglePlayback() {
        let frameTime = currentTime()
        if isPaused {
            isPaused = false
            loopStart = ProcessInfo.processInfo.systemUptime - pausedAt
            updateAnimationLifecycle()
        } else {
            isPaused = true
            pausedAt = frameTime
            stopTimer()
        }
        refreshPlaybackButton()
    }

    private func resetLoop() {
        loopStart = ProcessInfo.processInfo.systemUptime
        pausedAt = 0
        renderFrame()
    }

    private func currentTime() -> TimeInterval {
        forcedDemoTime ?? (isPaused ? pausedAt : ProcessInfo.processInfo.systemUptime - loopStart)
    }

    private func renderFrame() {
        guard canAnimate || forcedDemoTime != nil || isPaused else {
            stopTimer()
            return
        }
        demo.sample = GestureDemoTimeline.sample(action: selectedAction, seconds: currentTime())
    }

    private func updateAnimationLifecycle() {
        refreshPlaybackButton()
        guard canAnimate else {
            stopTimer()
            renderFrame()
            return
        }
        guard timer == nil else { return }
        let next = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.renderFrame() }
        RunLoop.main.add(next, forMode: .common)
        timer = next
    }

    private var canAnimate: Bool {
        guard forcedDemoTime == nil, !isPaused,
              !reduceMotionEnabled,
              let window, window.isVisible, !window.isMiniaturized,
              window.occlusionState.contains(.visible),
              !isHiddenOrHasHiddenAncestor, !visibleRect.isEmpty,
              NSApp.isActive else { return false }
        return true
    }

    private func refreshHostObservers() {
        hostNotificationTokens.forEach(NotificationCenter.default.removeObserver)
        hostNotificationTokens.removeAll()
        guard let window else { return }
        let center = NotificationCenter.default
        for name in [NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
                     NSWindow.didChangeOcclusionStateNotification, NSWindow.willCloseNotification] {
            hostNotificationTokens.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] note in
                if note.name == NSWindow.willCloseNotification { self?.stopTimer() }
                else { self?.updateAnimationLifecycle() }
            })
        }
        if let clip = enclosingScrollView?.contentView {
            clip.postsBoundsChangedNotifications = true
            hostNotificationTokens.append(center.addObserver(forName: NSView.boundsDidChangeNotification,
                                                               object: clip, queue: .main) { [weak self] _ in
                self?.updateAnimationLifecycle()
            })
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func refreshPlaybackButton() {
        let reduced = reduceMotionEnabled
        playback.isHidden = reduced
        playback.title = isPaused ? "▶" : "Ⅱ"
        playback.setAccessibilityLabel(isPaused ? "Play gesture demonstration" : "Pause gesture demonstration")
        demo.showsStaticSequence = reduced
    }

    private var reduceMotionEnabled: Bool {
        forcedReduceMotion ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

private final class GestureSelectorButton: NSButton {
    let gestureAction: GestureAction
    var onActivate: ((GestureAction) -> Void)?
    var isLearningSelection = false { didSet { if oldValue != isLearningSelection { refreshPresentation(animated: true) } } }
    var isLive = false { didSet { if oldValue != isLive { refreshPresentation() } } }
    var featureEnabled = true { didSet { if oldValue != featureEnabled { refreshPresentation() } } }
    private let titleLabel = NSTextField(labelWithString: "")
    private let instructionLabel = NSTextField(labelWithString: "")
    private let statusBadge = NSTextField(labelWithString: "LIVE")
    private var isHovered = false { didSet { if oldValue != isHovered { refreshPresentation(animated: true) } } }
    private var trackingAreaReference: NSTrackingArea?

    init(action: GestureAction) {
        gestureAction = action
        super.init(frame: .zero)
        title = ""
        isBordered = false
        setButtonType(.momentaryChange)
        focusRingType = .exterior
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.borderWidth = 0.5
        target = self
        self.action = #selector(activateCard)

        titleLabel.stringValue = action.title
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = StartupStyle.text
        instructionLabel.stringValue = action.instruction
        instructionLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        instructionLabel.textColor = StartupStyle.muted
        statusBadge.font = .monospacedSystemFont(ofSize: 8, weight: .bold)
        statusBadge.alignment = .center
        statusBadge.wantsLayer = true
        statusBadge.layer?.cornerRadius = 5
        for view in [titleLabel, instructionLabel, statusBadge] {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.setAccessibilityElement(false)
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            instructionLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            instructionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            instructionLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            statusBadge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            statusBadge.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
            statusBadge.widthAnchor.constraint(equalToConstant: 32),
            statusBadge.heightAnchor.constraint(equalToConstant: 14)
        ])
        setAccessibilityRole(.button)
        setAccessibilityLabel(action.title)
        setAccessibilityHelp(action.accessibilityDescription)
        refreshPresentation()
    }

    required init?(coder: NSCoder) { fatalError() }
    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        if let trackingAreaReference { removeTrackingArea(trackingAreaReference) }
        let next = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(next)
        trackingAreaReference = next
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override var focusRingMaskBounds: NSRect { bounds.insetBy(dx: 1, dy: 1) }
    override func drawFocusRingMask() { NSBezierPath(roundedRect: focusRingMaskBounds, xRadius: 13, yRadius: 13).fill() }
    @objc private func activateCard() { onActivate?(gestureAction) }

    fileprivate func refreshPresentation(animated: Bool = false) {
        guard layer != nil else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
        let contrast = SurfacePreferences.current.increaseContrast
        let raised = isLearningSelection || isHovered || isHighlighted
        StartupStyle.transitionBackground(of: self, to: raised ? StartupStyle.raisedSurface : StartupStyle.surface, animated: animated)
        layer?.borderColor = (isLearningSelection ? StartupStyle.mint.withAlphaComponent(contrast ? 1 : 0.72)
            : (contrast ? NSColor.labelColor.withAlphaComponent(0.65) : StartupStyle.muted.withAlphaComponent(isHovered ? 0.30 : 0.14))).cgColor
        layer?.borderWidth = contrast ? 2 : (isLearningSelection ? 1.5 : 0.5)
        layer?.shadowOpacity = 0
        statusBadge.stringValue = isLive ? "LIVE" : "OFF"
        statusBadge.textColor = isLive ? StartupStyle.background : StartupStyle.muted
        statusBadge.layer?.backgroundColor = (isLive ? StartupStyle.accent : StartupStyle.muted.withAlphaComponent(0.12)).cgColor
        statusBadge.isHidden = featureEnabled && !isLive
        let availability = featureEnabled ? "" : " Feature is off; tutorial remains available."
        let state = isLive ? " Active now." : (isLearningSelection ? " Selected tutorial." : "")
        setAccessibilityValue(gestureAction.instruction + state + availability)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshPresentation()
    }
}

private final class GestureDemoCanvas: NSView {
    typealias HandPose = GestureDemoSample.HandPose
    var action: GestureAction = .move { didSet { needsDisplay = true; refreshAccessibility() } }
    var sample = GestureDemoTimeline.sample(action: .move, seconds: 0) { didSet { needsDisplay = true; refreshAccessibility() } }
    var showsStaticSequence = false { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 20
        refreshAppearance()
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        refreshAccessibility()
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    fileprivate func refreshAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = StartupStyle.surface.cgColor
            layer?.borderColor = StartupStyle.border.cgColor
            layer?.borderWidth = SurfacePreferences.current.increaseContrast ? 1.5 : 0.5
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard bounds.width > 80, bounds.height > 80 else { return }
        drawLabel("DEMO  ·  \(action.title.uppercased())", at: CGPoint(x: 16, y: 13), size: 10, color: StartupStyle.mint, weight: .bold)
        drawLabel(showsStaticSequence ? "Motion reduced · key steps" : sample.stage,
                  at: CGPoint(x: 16, y: 30), size: 12, color: StartupStyle.muted, weight: .medium)
        let sceneRect = NSRect(x: 14, y: 52, width: max(1, bounds.width - 28),
                               height: max(1, bounds.height - 64))
        if showsStaticSequence {
            let times: [TimeInterval]
            switch action {
            case .move: times = [0.65, 2.45, 3.35]
            case .click: times = [0.65, 2.0, 2.60]
            case .rightClick: times = [0.65, 1.6, 3.80]
            case .scroll: times = [0.65, 2.45, 3.80]
            case .select: times = [0.65, 2.55, 3.90]
            }
            let stepLabels: [String]
            switch action {
            case .move: stepLabels = ["Raise", "Move", "Return"]
            case .click: stepLabels = ["Aim", "Hold 1 s", "Click"]
            case .rightClick: stepLabels = ["Open", "Five tips", "Release"]
            case .scroll: stepLabels = ["Pinch", "Move down", "Open"]
            case .select: stepLabels = ["Acquire", "Two L hands", "Open"]
            }
            for index in 0..<3 {
                let width = sceneRect.width / 3
                let frame = NSRect(x: sceneRect.minX + CGFloat(index) * width + 4,
                                   y: sceneRect.minY, width: width - 8, height: sceneRect.height)
                drawLabel("\(index + 1)  \(stepLabels[index])", at: CGPoint(x: frame.minX + 7, y: frame.minY + 6),
                          size: 9, color: StartupStyle.mint, weight: .bold)
                drawScene(in: frame, sample: GestureDemoTimeline.sample(action: action, seconds: times[index]), compact: true)
            }
        } else {
            drawScene(in: sceneRect, sample: sample, compact: false)
        }
    }

    private func drawScene(in rect: NSRect, sample: GestureDemoSample, compact: Bool) {
        let gap: CGFloat = compact ? 5 : 16
        let handArea: NSRect
        let resultArea: NSRect
        StartupStyle.background.withAlphaComponent(0.42).setFill()
        if compact {
            NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
            let handHeight = rect.height * 0.62
            handArea = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: handHeight)
            resultArea = NSRect(x: rect.minX, y: handArea.maxY + gap,
                                width: rect.width, height: rect.height - handHeight - gap)
        } else {
            let leftWidth = rect.width * 0.45
            handArea = NSRect(x: rect.minX, y: rect.minY, width: leftWidth, height: rect.height)
            resultArea = NSRect(x: handArea.maxX + gap, y: rect.minY,
                                width: rect.width - leftWidth - gap, height: rect.height)
            NSBezierPath(roundedRect: handArea, xRadius: 12, yRadius: 12).fill()
            NSBezierPath(roundedRect: resultArea, xRadius: 12, yRadius: 12).fill()
        }

        let handScale = min(handArea.width / (action == .select ? 180 : 120), handArea.height / 125)
        let travel = (sample.primaryX - 0.5) * handArea.width * (action == .select ? 0.24 : 0.34)
        let vertical = (sample.primaryY - 0.5) * handArea.height * 0.58
        let primaryAnchor = CGPoint(x: handArea.midX + travel + (action == .select ? handArea.width * 0.12 : 0),
                                    y: handArea.maxY - 24 * handScale + vertical)
        if let secondary = sample.secondaryPose {
            let companion = CGPoint(x: handArea.minX + handArea.width * 0.30,
                                    y: handArea.maxY - 24 * handScale)
            drawHand(at: companion, scale: handScale * 0.78, pose: secondary,
                     mirrored: true, primary: false, ink: StartupStyle.text, accent: StartupStyle.accent)
        }
        drawHand(at: primaryAnchor, scale: handScale, pose: sample.primaryPose,
                 mirrored: false, primary: true, ink: StartupStyle.text, accent: StartupStyle.mint)
        switch action {
        case .move: drawMoveResult(in: resultArea, progress: sample.resultProgress, compact: compact)
        case .click: drawClickResult(in: resultArea, pressed: sample.gestureHeld, activated: sample.resultActivated, compact: compact)
        case .rightClick:
            if sample.resultActivated {
                drawContextMenu(at: CGPoint(x: resultArea.midX - 28, y: resultArea.midY - 24), color: StartupStyle.mint, scale: 1)
            } else {
                drawCentered("Right click", in: resultArea, size: 12, color: StartupStyle.muted, weight: .medium)
            }
        case .scroll: drawScrollResult(in: resultArea, progress: sample.resultProgress, held: sample.gestureHeld, compact: compact)
        case .select: drawSelectResult(in: resultArea, progress: sample.resultProgress, held: sample.gestureHeld, compact: compact)
        }
    }

    private func drawMoveResult(in rect: NSRect, progress: CGFloat, compact: Bool) {
        let desktop = rect.insetBy(dx: 14, dy: 16)
        StartupStyle.raisedSurface.setFill()
        NSBezierPath(roundedRect: desktop, xRadius: 10, yRadius: 10).fill()
        for index in 0..<3 {
            StartupStyle.muted.withAlphaComponent(0.13).setFill()
            NSBezierPath(roundedRect: NSRect(x: desktop.minX + 14, y: desktop.minY + 18 + CGFloat(index) * 24,
                                             width: desktop.width * (0.50 + CGFloat(index) * 0.09), height: 8),
                         xRadius: 4, yRadius: 4).fill()
        }
        let x = desktop.minX + 24 + progress * max(1, desktop.width - 58)
        let y = desktop.midY + sin(progress * .pi) * 28
        drawPointer(at: CGPoint(x: x, y: y), color: StartupStyle.mint, scale: 1.05)
        if !compact {
            drawLabel("Index fingertip → cursor", at: CGPoint(x: desktop.minX + 14, y: desktop.maxY - 28), size: 10, color: StartupStyle.muted, weight: .medium)
        }
    }

    private func drawClickResult(in rect: NSRect, pressed: Bool, activated: Bool, compact: Bool) {
        let button = NSRect(x: rect.midX - min(92, rect.width * 0.34), y: rect.midY - 25,
                            width: min(184, rect.width * 0.68), height: 50)
        (activated ? StartupStyle.mint : StartupStyle.raisedSurface).setFill()
        NSBezierPath(roundedRect: button.offsetBy(dx: 0, dy: pressed ? 3 : 0), xRadius: 12, yRadius: 12).fill()
        (activated ? StartupStyle.background : StartupStyle.text).setStroke()
        let border = NSBezierPath(roundedRect: button.offsetBy(dx: 0, dy: pressed ? 3 : 0), xRadius: 12, yRadius: 12)
        border.lineWidth = 1.3; border.stroke()
        drawCentered(activated ? "CLICKED" : "OPEN", in: button.offsetBy(dx: 0, dy: pressed ? 3 : 0), size: 12,
                     color: activated ? StartupStyle.background : StartupStyle.text, weight: .bold)
        if !compact {
            drawCentered("Hold two fingers for 1 second", in: NSRect(x: rect.minX, y: button.maxY + 14, width: rect.width, height: 18),
                         size: 10, color: StartupStyle.muted, weight: .medium)
        }
    }

    private func drawScrollResult(in rect: NSRect, progress: CGFloat, held: Bool, compact: Bool) {
        let list = rect.insetBy(dx: 18, dy: 13)
        StartupStyle.raisedSurface.setFill()
        NSBezierPath(roundedRect: list, xRadius: 10, yRadius: 10).fill()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: list.insetBy(dx: 7, dy: 7), xRadius: 7, yRadius: 7).addClip()
        let offset = progress * 54
        for index in 0..<7 {
            let y = list.minY + 16 + CGFloat(index) * 29 - offset
            StartupStyle.muted.withAlphaComponent(index % 2 == 0 ? 0.20 : 0.12).setFill()
            NSBezierPath(roundedRect: NSRect(x: list.minX + 13, y: y, width: list.width - 26, height: 18), xRadius: 5, yRadius: 5).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        if !compact {
            drawLabel(held ? "PINCH HELD" : "RELEASED", at: CGPoint(x: list.minX + 12, y: list.maxY - 24),
                      size: 9, color: held ? StartupStyle.mint : StartupStyle.muted, weight: .bold)
        }
    }

    private func drawSelectResult(in rect: NSRect, progress: CGFloat, held: Bool, compact: Bool) {
        let page = rect.insetBy(dx: 16, dy: 18)
        StartupStyle.raisedSurface.setFill()
        NSBezierPath(roundedRect: page, xRadius: 10, yRadius: 10).fill()
        let line = NSRect(x: page.minX + 15, y: page.midY - 15, width: page.width - 30, height: 30)
        let selectedWidth = max(2, line.width * progress)
        StartupStyle.accent.withAlphaComponent(held ? 0.38 : 0.24).setFill()
        NSBezierPath(roundedRect: NSRect(x: line.minX, y: line.minY + 3, width: selectedWidth, height: 22), xRadius: 4, yRadius: 4).fill()
        drawLabel("Drag across this sentence", at: CGPoint(x: line.minX + 5, y: line.minY + 6),
                  size: min(12, max(6, line.width / 21)), color: StartupStyle.text, weight: .medium)
        let caretX = line.minX + selectedWidth
        StartupStyle.mint.setFill()
        NSBezierPath(rect: NSRect(x: caretX - 1, y: line.minY + 1, width: 2, height: 26)).fill()
        if !compact {
            drawCentered(held ? "Keep the other hand still" : "Open either hand to release",
                         in: NSRect(x: page.minX, y: page.maxY - 31, width: page.width, height: 16),
                         size: 9.5, color: StartupStyle.muted, weight: .medium)
        }
    }

    private func refreshAccessibility() {
        setAccessibilityLabel("\(action.title) demonstration")
        setAccessibilityValue("\(sample.stage). \(action.accessibilityDescription)")
    }

    private func drawHand(at anchor: CGPoint, scale: CGFloat, pose: HandPose, mirrored: Bool,
                          primary: Bool, ink: NSColor, accent: NSColor) {
        func px(_ x: CGFloat) -> CGFloat { anchor.x + (mirrored ? -x : x) * scale }
        func py(_ y: CGFloat) -> CGFloat { anchor.y - y * scale }
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
            let left = mirrored ? px(x + w) : px(x)
            return NSRect(x: left, y: py(y + h), width: w * scale, height: h * scale)
        }

        let fill = ink.withAlphaComponent(primary ? 0.34 : 0.25)
        let stroke = primary ? ink : ink.withAlphaComponent(0.66)
        func drawPalmAndWrist() {
            let palm = NSBezierPath(roundedRect: rect(-18, 0, 38, 39), xRadius: 12 * scale, yRadius: 12 * scale)
            fill.setFill(); palm.fill()
            stroke.setStroke(); palm.lineWidth = max(1, 1.45 * scale); palm.stroke()
            let wrist = NSBezierPath(roundedRect: rect(-10, -9, 21, 14), xRadius: 6 * scale, yRadius: 6 * scale)
            fill.setFill(); wrist.fill(); stroke.setStroke(); wrist.lineWidth = max(1, 1.4 * scale); wrist.stroke()
        }

        switch pose {
        case .point:
            drawFinger(rect(-13, 31, 10, 42), radius: 5, fill: fill, stroke: stroke, scale: scale, rect: rect)
            drawFoldedFingers(anchor: anchor, scale: scale, mirrored: mirrored, fill: fill, ink: stroke)
            drawThumb(anchor: anchor, scale: scale, mirrored: mirrored, extended: false, fill: fill, stroke: stroke)
            drawPalmAndWrist()
            drawTip(at: CGPoint(x: px(-8), y: py(72)), color: accent, scale: scale)
        case .raised:
            drawFinger(rect(-13, 31, 10, 42), radius: 5, fill: fill, stroke: stroke, scale: scale, rect: rect)
            drawFinger(rect(1, 32, 10, 38), radius: 5, fill: fill, stroke: stroke, scale: scale, rect: rect)
            drawFoldedFingers(anchor: anchor, scale: scale, mirrored: mirrored, fill: fill, ink: stroke)
            drawThumb(anchor: anchor, scale: scale, mirrored: mirrored, extended: true, fill: fill, stroke: stroke)
            drawPalmAndWrist()
            drawTip(at: CGPoint(x: px(-8), y: py(72)), color: accent, scale: scale)
            drawTip(at: CGPoint(x: px(6), y: py(68)), color: accent, scale: scale)
        case .allPinch:
            let fingers: [[(CGFloat, CGFloat)]] = [
                [(-13, 31), (-19, 47), (-12, 57), (-7, 60)],
                [(-3, 35), (-9, 54), (-6, 64), (-3, 66)],
                [(8, 34), (11, 53), (7, 63), (2, 66)],
                [(18, 29), (23, 45), (17, 56), (7, 61)],
                [(-17, 19), (-29, 33), (-20, 48), (-8, 55)]
            ]
            for finger in fingers {
                drawBentFinger(points: finger, anchor: anchor, scale: scale, mirrored: mirrored, fill: fill, stroke: stroke)
            }
            drawPalmAndWrist()
            for finger in fingers {
                if let tip = finger.last { drawTip(at: CGPoint(x: px(tip.0), y: py(tip.1)), color: accent, scale: scale) }
            }
        case .threePinch:
            drawBentFinger(points: [(-8, 34), (-14, 53), (-4, 65), (5, 60)], anchor: anchor, scale: scale, mirrored: mirrored, fill: fill, stroke: stroke)
            drawBentFinger(points: [(6, 34), (18, 54), (15, 66), (9, 61)], anchor: anchor, scale: scale, mirrored: mirrored, fill: fill, stroke: stroke)
            drawFoldedFingers(anchor: anchor, scale: scale, mirrored: mirrored, fill: fill, ink: stroke, count: 2)
            drawPinchingThumb(anchor: anchor, scale: scale, mirrored: mirrored, fill: fill, stroke: stroke)
            drawPalmAndWrist()
            for (x, y) in [(CGFloat(5), CGFloat(60)), (9, 61), (12, 56)] {
                drawTip(at: CGPoint(x: px(x), y: py(y)), color: accent, scale: scale)
            }
        case .lShape:
            drawFinger(rect(-12, 31, 10, 42), radius: 5, fill: fill, stroke: stroke, scale: scale, rect: rect)
            drawFoldedFingers(anchor: anchor, scale: scale, mirrored: mirrored, fill: fill, ink: stroke)
            drawThumb(anchor: anchor, scale: scale, mirrored: mirrored, extended: true, fill: fill, stroke: stroke)
            drawPalmAndWrist()
            drawTip(at: CGPoint(x: px(-7), y: py(72)), color: accent, scale: scale)
            drawTip(at: CGPoint(x: px(-35), y: py(32)), color: accent, scale: scale)
        case .open:
            let fingers: [(CGFloat, CGFloat, CGFloat)] = [(-20, 27, 38), (-9, 33, 43), (3, 34, 40), (15, 29, 33)]
            for (x, y, height) in fingers {
                drawFinger(rect(x, y, 8, height), radius: 4, fill: fill, stroke: stroke, scale: scale, rect: rect)
            }
            drawThumb(anchor: anchor, scale: scale, mirrored: mirrored, extended: true, fill: fill, stroke: stroke)
            drawPalmAndWrist()
        }
    }

    private func drawCountdown(at center: CGPoint, color: NSColor, scale: CGFloat) {
        let radius = 28 * scale
        let track = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius,
                                               width: radius * 2, height: radius * 2))
        color.withAlphaComponent(0.16).setStroke(); track.lineWidth = 5 * scale; track.stroke()
        let progress = NSBezierPath()
        progress.appendArc(withCenter: center, radius: radius, startAngle: -90, endAngle: 150, clockwise: false)
        color.setStroke(); progress.lineWidth = 5 * scale; progress.lineCapStyle = .round; progress.stroke()
        let label = NSAttributedString(string: "1 s", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 17 * scale, weight: .semibold),
            .foregroundColor: color
        ])
        let size = label.size()
        label.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))
    }

    private func drawContextMenu(at origin: CGPoint, color: NSColor, scale: CGFloat) {
        let outline = NSBezierPath(roundedRect: NSRect(x: origin.x, y: origin.y, width: 57 * scale, height: 48 * scale),
                                   xRadius: 6 * scale, yRadius: 6 * scale)
        color.withAlphaComponent(0.08).setFill(); outline.fill()
        color.withAlphaComponent(0.64).setStroke(); outline.lineWidth = max(1, 1.3 * scale); outline.stroke()
        for index in 0..<3 {
            let line = NSBezierPath()
            line.move(to: CGPoint(x: origin.x + 11 * scale, y: origin.y + CGFloat(12 + index * 12) * scale))
            line.line(to: CGPoint(x: origin.x + 44 * scale, y: origin.y + CGFloat(12 + index * 12) * scale))
            color.withAlphaComponent(index == 0 ? 1 : 0.4).setStroke()
            line.lineWidth = 3 * scale; line.lineCapStyle = .round; line.stroke()
        }
    }

    private func drawFinger(_ frame: NSRect, radius: CGFloat, fill: NSColor, stroke: NSColor,
                            scale: CGFloat, rect: (CGFloat, CGFloat, CGFloat, CGFloat) -> NSRect) {
        let path = NSBezierPath(roundedRect: frame, xRadius: radius * scale, yRadius: radius * scale)
        fill.setFill(); path.fill(); stroke.setStroke(); path.lineWidth = max(1, 1.35 * scale); path.stroke()
    }

    private func drawBentFinger(points: [(CGFloat, CGFloat)], anchor: CGPoint, scale: CGFloat,
                                mirrored: Bool, fill: NSColor, stroke: NSColor) {
        let path = NSBezierPath()
        let convert: ((CGFloat, CGFloat)) -> CGPoint = { point in
            let (x, y) = point
            return CGPoint(x: anchor.x + (mirrored ? -x : x) * scale, y: anchor.y - y * scale)
        }
        path.move(to: convert(points[0]))
        for point in points.dropFirst() { path.line(to: convert(point)) }
        stroke.withAlphaComponent(0.42).setStroke(); path.lineWidth = 11 * scale; path.lineCapStyle = .round; path.lineJoinStyle = .round; path.stroke()
        stroke.setStroke(); path.lineWidth = max(1, 1.45 * scale); path.stroke()
        fill.setFill()
    }

    private func drawFoldedFingers(anchor: CGPoint, scale: CGFloat, mirrored: Bool,
                                   fill: NSColor, ink: NSColor, count: Int = 3) {
        for index in (3 - count)..<3 {
            let x = CGFloat(7 + index * 7)
            let center = CGPoint(x: anchor.x + (mirrored ? -x : x) * scale,
                                 y: anchor.y - CGFloat(27 - index * 4) * scale)
            let path = NSBezierPath(ovalIn: NSRect(x: center.x - 5 * scale, y: center.y - 6 * scale,
                                                   width: 10 * scale, height: 12 * scale))
            fill.withAlphaComponent(0.82).setFill()
            path.fill()
            ink.withAlphaComponent(0.72).setStroke()
            path.lineWidth = max(1, 1.3 * scale)
            path.stroke()
        }
    }

    private func drawThumb(anchor: CGPoint, scale: CGFloat, mirrored: Bool, extended: Bool,
                           fill: NSColor, stroke: NSColor) {
        let direction: CGFloat = mirrored ? -1 : 1
        let path = NSBezierPath()
        path.move(to: CGPoint(x: anchor.x - 13 * direction * scale, y: anchor.y - 29 * scale))
        path.curve(to: CGPoint(x: anchor.x - 36 * direction * scale, y: anchor.y - 33 * scale),
                   controlPoint1: CGPoint(x: anchor.x - 22 * direction * scale, y: anchor.y - 31 * scale),
                   controlPoint2: CGPoint(x: anchor.x - 30 * direction * scale, y: anchor.y - 39 * scale))
        path.curve(to: CGPoint(x: anchor.x - 14 * direction * scale, y: anchor.y - 20 * scale),
                   controlPoint1: CGPoint(x: anchor.x - 39 * direction * scale, y: anchor.y - 25 * scale),
                   controlPoint2: CGPoint(x: anchor.x - 23 * direction * scale, y: anchor.y - 18 * scale))
        path.close()
        fill.setFill(); path.fill(); stroke.setStroke(); path.lineWidth = max(1, 1.4 * scale); path.stroke()
    }

    private func drawPinchingThumb(anchor: CGPoint, scale: CGFloat, mirrored: Bool,
                                   fill: NSColor, stroke: NSColor) {
        let direction: CGFloat = mirrored ? -1 : 1
        let path = NSBezierPath()
        path.move(to: CGPoint(x: anchor.x - 14 * direction * scale, y: anchor.y - 29 * scale))
        path.curve(to: CGPoint(x: anchor.x + 12 * direction * scale, y: anchor.y - 56 * scale),
                   controlPoint1: CGPoint(x: anchor.x - 4 * direction * scale, y: anchor.y - 37 * scale),
                   controlPoint2: CGPoint(x: anchor.x + 3 * direction * scale, y: anchor.y - 51 * scale))
        path.curve(to: CGPoint(x: anchor.x - 10 * direction * scale, y: anchor.y - 19 * scale),
                   controlPoint1: CGPoint(x: anchor.x + 18 * direction * scale, y: anchor.y - 49 * scale),
                   controlPoint2: CGPoint(x: anchor.x - 2 * direction * scale, y: anchor.y - 23 * scale))
        path.close()
        fill.setFill(); path.fill(); stroke.setStroke(); path.lineWidth = max(1, 1.4 * scale); path.stroke()
    }

    private func drawTip(at center: CGPoint, color: NSColor, scale: CGFloat) {
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - 2.8 * scale, y: center.y - 2.8 * scale,
                                    width: 5.6 * scale, height: 5.6 * scale)).fill()
    }

    private func drawPointer(at center: CGPoint, color: NSColor, scale: CGFloat) {
        let path = NSBezierPath()
        path.move(to: CGPoint(x: center.x - 6 * scale, y: center.y - 13 * scale))
        path.line(to: CGPoint(x: center.x + 10 * scale, y: center.y + 4 * scale))
        path.line(to: CGPoint(x: center.x + 2.5 * scale, y: center.y + 5 * scale))
        path.line(to: CGPoint(x: center.x + 7 * scale, y: center.y + 14 * scale))
        path.line(to: CGPoint(x: center.x + 2 * scale, y: center.y + 16 * scale))
        path.line(to: CGPoint(x: center.x - 2 * scale, y: center.y + 7 * scale))
        path.line(to: CGPoint(x: center.x - 8 * scale, y: center.y + 12 * scale))
        path.close()
        color.withAlphaComponent(0.20).setFill(); path.fill()
        color.setStroke(); path.lineWidth = max(1, 1.5 * scale); path.lineJoinStyle = .round; path.stroke()
    }

    private func drawLabel(_ text: String, at point: CGPoint, size: CGFloat, color: NSColor, weight: NSFont.Weight) {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color
        ]).draw(at: point)
    }

    private func drawCentered(_ text: String, in rect: NSRect, size: CGFloat, color: NSColor, weight: NSFont.Weight) {
        let string = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color
        ])
        let measured = string.size()
        string.draw(at: CGPoint(x: rect.midX - measured.width / 2, y: rect.midY - measured.height / 2))
    }
}

/// Live setup milestones, derived from permission/capture state rather than a saved onboarding flag.
final class SetupStepView: NSView {
    private let number: String
    private var presentation = ""
    private let badge = NSTextField(labelWithString: "")
    private let title = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(wrappingLabelWithString: "")

    init(number: String, title: String) {
        self.number = number
        super.init(frame: .zero)
        wantsLayer = true
        setAccessibilityRole(.group)
        layer?.cornerRadius = 12
        layer?.borderWidth = 1
        self.title.stringValue = title
        self.title.font = .systemFont(ofSize: 13, weight: .semibold)
        badge.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        let heading = NSStackView(views: [badge, self.title])
        heading.spacing = 8
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = StartupStyle.muted
        detailLabel.maximumNumberOfLines = 2
        detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let text = StartupStyle.column([heading, detailLabel], spacing: 4)
        text.translatesAutoresizingMaskIntoConstraints = false
        addSubview(text)
        NSLayoutConstraint.activate([
            detailLabel.widthAnchor.constraint(equalTo: text.widthAnchor),
            text.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            text.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            text.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            text.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        ])
        update(complete: false, active: false, detail: "")
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(complete: Bool, active: Bool, detail: String) {
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let nextPresentation = "\(complete)|\(active)|\(contrast)|\(detail)"
        guard presentation != nextPresentation else { return }
        presentation = nextPresentation
        detailLabel.stringValue = detail
        let badgeText = complete ? "✓" : number
        if badge.stringValue != badgeText { badge.stringValue = badgeText }
        badge.textColor = complete || active ? StartupStyle.accent : StartupStyle.muted
        layer?.backgroundColor = StartupStyle.surface.cgColor
        layer?.borderColor = (active || contrast ? StartupStyle.accent : StartupStyle.muted.withAlphaComponent(0.22)).cgColor
        setAccessibilityElement(true)
        setAccessibilityLabel("Step \(number), \(title.stringValue). \(complete ? "Complete. " : "")\(detail)")
    }
}

enum TapGuideStage: String {
    case aim = "Aim"
    case bend = "Bend"
    case lift = "Lift"
}

/// Always visible beside the camera controls, including when the settings scroll away.
final class PointerGuideView: NSView {
    private let heading = NSTextField(wrappingLabelWithString: "")
    private let detail = NSTextField(wrappingLabelWithString: "")
    private let hand = NSImageView()
    private let tapSteps = NSStackView()
    private var tapLabels: [(stage: TapGuideStage, label: NSTextField)] = []
    private var presentation = ""

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.backgroundColor = StartupStyle.surface.cgColor
        hand.image = NSImage(systemSymbolName: "hand.point.up", accessibilityDescription: nil)
        hand.symbolConfiguration = .init(pointSize: 30, weight: .regular)
        hand.contentTintColor = StartupStyle.accent
        hand.setAccessibilityElement(false)
        heading.font = .systemFont(ofSize: 14, weight: .semibold)
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = StartupStyle.muted
        tapSteps.orientation = .horizontal
        tapSteps.alignment = .centerY
        tapSteps.distribution = .fillEqually
        tapSteps.spacing = 6
        tapSteps.isHidden = true
        tapSteps.setAccessibilityElement(true)
        tapSteps.setAccessibilityRole(.staticText)
        for (index, stage) in [TapGuideStage.aim, .bend, .lift].enumerated() {
            let label = NSTextField(labelWithString: "\(index + 1)  \(stage.rawValue)")
            label.alignment = .center
            label.font = .systemFont(ofSize: 11, weight: .medium)
            label.setAccessibilityElement(false)
            label.setContentHuggingPriority(.required, for: .vertical)
            label.setContentCompressionResistancePriority(.required, for: .vertical)
            let step = NSView()
            step.wantsLayer = true
            step.layer?.cornerRadius = 6
            step.layer?.borderWidth = 1
            label.translatesAutoresizingMaskIntoConstraints = false
            step.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: step.leadingAnchor, constant: 8),
                label.trailingAnchor.constraint(equalTo: step.trailingAnchor, constant: -8),
                label.topAnchor.constraint(equalTo: step.topAnchor, constant: 5),
                label.bottomAnchor.constraint(equalTo: step.bottomAnchor, constant: -5)
            ])
            tapSteps.addArrangedSubview(step)
            tapLabels.append((stage, label))
        }
        let text = StartupStyle.column([heading, detail, tapSteps], spacing: 4)
        text.detachesHiddenViews = true
        text.setCustomSpacing(8, after: detail)
        for view in [hand, text] { view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view) }
        NSLayoutConstraint.activate([
            hand.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            hand.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            hand.widthAnchor.constraint(equalToConstant: 32), hand.heightAnchor.constraint(equalToConstant: 36),
            text.leadingAnchor.constraint(equalTo: hand.trailingAnchor, constant: 12),
            text.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            text.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            text.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            heading.widthAnchor.constraint(equalTo: text.widthAnchor),
            detail.widthAnchor.constraint(equalTo: text.widthAnchor),
            tapSteps.widthAnchor.constraint(equalTo: text.widthAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 90)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(title: String, detail: String, tapStage: TapGuideStage? = nil) {
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let next = title + "\n" + detail + "\n\(tapStage?.rawValue ?? "")|\(contrast)"
        guard next != presentation else { return }
        presentation = next
        heading.stringValue = title
        self.detail.stringValue = detail
        tapSteps.isHidden = tapStage == nil
        guard let tapStage else { return }
        tapSteps.setAccessibilityLabel("Tap to click: 1 Aim, 2 Bend, 3 Lift. Current step: \(tapStage.rawValue).")
        for (stage, label) in tapLabels {
            let active = stage == tapStage
            label.font = .systemFont(ofSize: 11, weight: active ? .bold : .medium)
            label.textColor = active ? StartupStyle.accent : StartupStyle.muted
            label.superview?.layer?.backgroundColor = StartupStyle.accent.withAlphaComponent(active ? 0.14 : 0.035).cgColor
            label.superview?.layer?.borderColor = (active ? StartupStyle.accent : StartupStyle.muted.withAlphaComponent(contrast ? 0.8 : 0.18)).cgColor
        }
    }
}

/// Static vector artwork: no camera access, fake telemetry, or perpetual animation.
final class StandbyReticleView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(false)
        let hand = NSImageView()
        hand.image = NSImage(systemSymbolName: "hand.point.up.left", accessibilityDescription: nil)
        hand.symbolConfiguration = .init(pointSize: 46, weight: .ultraLight)
        hand.contentTintColor = StartupStyle.accent
        hand.translatesAutoresizingMaskIntoConstraints = false
        hand.setAccessibilityElement(false)
        addSubview(hand)
        NSLayoutConstraint.activate([
            hand.centerXAnchor.constraint(equalTo: centerXAnchor),
            hand.centerYAnchor.constraint(equalTo: centerYAnchor),
            hand.widthAnchor.constraint(equalToConstant: 58),
            hand.heightAnchor.constraint(equalToConstant: 58)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) * 0.40
        let strong = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        StartupStyle.accent.withAlphaComponent(strong ? 0.7 : 0.22).setStroke()
        for scale: CGFloat in [0.74, 1] {
            let circle = NSBezierPath(ovalIn: CGRect(x: center.x - radius * scale, y: center.y - radius * scale,
                                                   width: radius * scale * 2, height: radius * scale * 2))
            circle.lineWidth = 1
            circle.stroke()
        }
        let ticks = NSBezierPath()
        for index in 0..<48 {
            let angle = CGFloat(index) * .pi / 24
            let inner = radius + (index % 4 == 0 ? 4 : 7)
            let outer = radius + 11
            ticks.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
            ticks.line(to: CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer))
        }
        ticks.stroke()
    }
}
