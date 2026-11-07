import AppKit

enum GestureAction: CaseIterable {
    case move
    case click
    case rightClick
    case scroll
    case select

    var title: String {
        switch self {
        case .move: return "Move"
        case .click: return "Click"
        case .rightClick: return "Right click"
        case .scroll: return "Scroll"
        case .select: return "Select text"
        }
    }

    var instruction: String {
        switch self {
        case .move: return "Show hand · Move"
        case .click: return "Hold still · 1 s"
        case .rightClick: return "Five tips together"
        case .scroll: return "Three tips · Move"
        case .select: return "Two L hands · move"
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .move:
            return "Show your hand and move to aim. The pointer follows your index fingertip; no special pose is needed."
        case .click:
            return "Point at a target and stop moving. The ring fills and clicks once after one second. Move away before the next click."
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
            return GestureDemoSample(primaryPose: .point,
                secondaryPose: nil, primaryX: 0.46, primaryY: 0.5,
                resultProgress: held ? min(1, CGFloat(elapsed - clickHoldStart)) : 0,
                gestureHeld: held, resultActivated: activated,
                stage: activated ? "Clicked · move to click again" : (held ? "Hold still · 1 second" : "Aim with index only"))
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
