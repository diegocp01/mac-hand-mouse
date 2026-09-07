import AppKit

/// A quiet instrument-panel palette. All status information also has text labels.
enum StartupStyle {
    static let background = NSColor(srgbRed: 0.035, green: 0.055, blue: 0.08, alpha: 1)
    static let surface = NSColor(srgbRed: 0.065, green: 0.09, blue: 0.12, alpha: 1)
    static let raisedSurface = NSColor(srgbRed: 0.085, green: 0.12, blue: 0.15, alpha: 1)
    static let accent = NSColor(srgbRed: 0.35, green: 0.88, blue: 0.96, alpha: 1)
    static let mint = NSColor(srgbRed: 0.38, green: 0.94, blue: 0.76, alpha: 1)
    static let text = NSColor(srgbRed: 0.93, green: 0.97, blue: 0.98, alpha: 1)
    static let muted = NSColor(srgbRed: 0.66, green: 0.74, blue: 0.80, alpha: 1)

    static func column(_ views: [NSView], spacing: CGFloat = 10) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        return stack
    }
}

/// The four actions presented by the visual gesture guide.
enum GestureAction: CaseIterable {
    case move
    case click
    case scroll
    case select

    fileprivate var title: String {
        switch self {
        case .move: return "Move"
        case .click: return "Click"
        case .scroll: return "Scroll"
        case .select: return "Select text"
        }
    }

    fileprivate var instruction: String {
        switch self {
        case .move: return "Point & move"
        case .click: return "Bend · lift"
        case .scroll: return "Pinch · move"
        case .select: return "Two L hands · move"
        }
    }

    fileprivate var accessibilityDescription: String {
        switch self {
        case .move:
            return "Hold one palm toward the camera with the index and middle fingers extended, then move the index fingertip."
        case .click:
            return "Begin with the index and middle fingers raised. Bend both fingers together, then raise both again to click. Touching the two fingertips together does not click."
        case .scroll:
            return "Pinch the thumb and index fingertip, hold briefly, then move the hand vertically to scroll."
        case .select:
            return "First acquire the primary hand. Add a second hand with both thumbs and index fingers forming L shapes and the other fingers folded. Move only the primary hand. Open either L shape to release."
        }
    }
}

/// A keyboard-accessible, camera-free guide to the app's gesture vocabulary.
/// The diagrams use static sequence frames so their meaning remains complete with
/// Reduce Motion enabled and while the view is offscreen.
final class GestureGuideView: NSView {
    var onSelect: ((GestureAction) -> Void)?

    private var selectedAction: GestureAction = .move
    private var cards: [GestureAction: GestureCardButton] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Gesture guide")

        for action in GestureAction.allCases {
            let card = GestureCardButton(action: action)
            card.onActivate = { [weak self] selected in
                self?.select(selected)
                self?.onSelect?(selected)
            }
            cards[action] = card
        }

        let topRow = guideRow([.move, .click])
        let bottomRow = guideRow([.scroll, .select])
        let grid = NSStackView(views: [topRow, bottomRow])
        grid.orientation = .vertical
        grid.alignment = .leading
        grid.distribution = .fillEqually
        grid.spacing = 12
        grid.translatesAutoresizingMaskIntoConstraints = false
        addSubview(grid)

        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            grid.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            grid.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            grid.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            topRow.widthAnchor.constraint(equalTo: grid.widthAnchor),
            bottomRow.widthAnchor.constraint(equalTo: grid.widthAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 340),
            heightAnchor.constraint(lessThanOrEqualToConstant: 390)
        ])

        select(.move)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Selects the card shown as the current learning topic. This does not claim
    /// that a gesture is live; live state is supplied independently by `update`.
    func select(_ action: GestureAction) {
        selectedAction = action
        for (cardAction, card) in cards {
            card.isLearningSelection = cardAction == action
        }
    }

    /// Updates live tracking and feature availability without changing the card
    /// the person selected for learning.
    func update(active: GestureAction?, scrollingEnabled: Bool, selectionEnabled: Bool) {
        for (action, card) in cards {
            switch action {
            case .scroll: card.featureEnabled = scrollingEnabled
            case .select: card.featureEnabled = selectionEnabled
            case .move, .click: card.featureEnabled = true
            }
            card.isLive = active == action && card.featureEnabled
        }
    }

    private func guideRow(_ actions: [GestureAction]) -> NSStackView {
        let row = NSStackView(views: actions.compactMap { cards[$0] })
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fillEqually
        row.spacing = 12
        for action in actions {
            cards[action]?.heightAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        }
        return row
    }
}

private final class GestureCardButton: NSButton {
    let gestureAction: GestureAction
    var onActivate: ((GestureAction) -> Void)?

    var isLearningSelection = false {
        didSet {
            guard isLearningSelection != oldValue else { return }
            refreshPresentation()
        }
    }
    var isLive = false {
        didSet {
            guard isLive != oldValue else { return }
            refreshPresentation()
        }
    }
    var featureEnabled = true {
        didSet {
            guard featureEnabled != oldValue else { return }
            refreshPresentation()
        }
    }

    private let illustration: GestureIllustrationView
    private let titleLabel = NSTextField(labelWithString: "")
    private let instructionLabel = NSTextField(labelWithString: "")
    private let statusBadge = NSTextField(labelWithString: "LIVE")
    private var isHovered = false { didSet { refreshPresentation() } }
    private var trackingAreaReference: NSTrackingArea?

    init(action: GestureAction) {
        gestureAction = action
        illustration = GestureIllustrationView(action: action)
        super.init(frame: .zero)

        title = ""
        isBordered = false
        setButtonType(.momentaryChange)
        focusRingType = .exterior
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.borderWidth = 1
        layer?.masksToBounds = false
        target = self
        self.action = #selector(activateCard)

        titleLabel.stringValue = action.title
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = StartupStyle.text
        titleLabel.setAccessibilityElement(false)

        instructionLabel.stringValue = action.instruction
        instructionLabel.font = .systemFont(ofSize: 12, weight: .medium)
        instructionLabel.textColor = StartupStyle.muted
        instructionLabel.setAccessibilityElement(false)

        statusBadge.font = .monospacedSystemFont(ofSize: 8, weight: .bold)
        statusBadge.textColor = StartupStyle.background
        statusBadge.alignment = .center
        statusBadge.wantsLayer = true
        statusBadge.layer?.cornerRadius = 6
        statusBadge.layer?.backgroundColor = StartupStyle.accent.cgColor
        statusBadge.isHidden = true
        statusBadge.setAccessibilityElement(false)

        for view in [illustration, titleLabel, instructionLabel, statusBadge] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            illustration.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            illustration.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            illustration.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            illustration.heightAnchor.constraint(greaterThanOrEqualToConstant: 84),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: illustration.bottomAnchor, constant: 3),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: statusBadge.leadingAnchor, constant: -8),
            instructionLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            instructionLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            instructionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            instructionLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            statusBadge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -13),
            statusBadge.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            statusBadge.widthAnchor.constraint(equalToConstant: 34),
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
        let next = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(next)
        trackingAreaReference = next
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = superview.map { convert(point, from: $0) } ?? point
        guard !isHidden, alphaValue > 0.01, bounds.contains(localPoint) else { return nil }
        return self
    }

    override var focusRingMaskBounds: NSRect { bounds.insetBy(dx: 1, dy: 1) }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: focusRingMaskBounds, xRadius: 15, yRadius: 15).fill()
    }

    @objc private func activateCard() { onActivate?(gestureAction) }

    private func refreshPresentation() {
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let selectedColor = StartupStyle.mint
        alphaValue = 1
        let raised = isLearningSelection || isHovered || isHighlighted
        layer?.backgroundColor = (raised ? StartupStyle.raisedSurface : StartupStyle.surface).cgColor
        let border = isLearningSelection
            ? selectedColor.withAlphaComponent(contrast ? 1 : 0.74)
            : StartupStyle.muted.withAlphaComponent(isHovered ? 0.38 : (contrast ? 0.46 : 0.18))
        layer?.borderColor = border.cgColor
        layer?.borderWidth = isLearningSelection ? 2 : 1
        layer?.shadowOpacity = 0
        illustration.isLearningSelection = isLearningSelection
        illustration.isLive = isLive
        illustration.featureEnabled = featureEnabled
        statusBadge.stringValue = isLive ? "LIVE" : "OFF"
        statusBadge.textColor = isLive ? StartupStyle.background : StartupStyle.muted
        statusBadge.layer?.backgroundColor = (isLive
            ? StartupStyle.accent
            : StartupStyle.muted.withAlphaComponent(0.12)).cgColor
        statusBadge.isHidden = featureEnabled && !isLive
        let availability = featureEnabled ? "" : " Unavailable until enabled."
        let state = isLive ? " Active now." : (isLearningSelection ? " Selected for learning." : "")
        setAccessibilityValue(actionValue() + state + availability)
        setAccessibilityHelp(gestureAction.accessibilityDescription)
    }

    private func actionValue() -> String { gestureAction.instruction }
}

private final class GestureIllustrationView: NSView {
    enum HandPose { case raised, bent, pinch, lShape, open }

    let gestureAction: GestureAction
    var isLearningSelection = false {
        didSet { if isLearningSelection != oldValue { needsDisplay = true } }
    }
    var isLive = false {
        didSet { if isLive != oldValue { needsDisplay = true } }
    }
    var featureEnabled = true {
        didSet { if featureEnabled != oldValue { needsDisplay = true } }
    }

    init(action: GestureAction) {
        gestureAction = action
        super.init(frame: .zero)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard bounds.width > 8, bounds.height > 8 else { return }
        let scale = min(bounds.width / 260, bounds.height / 92)
        let drawingWidth: CGFloat = 260 * scale
        let origin = CGPoint(x: bounds.midX - drawingWidth / 2, y: bounds.midY - 46 * scale)
        let ink = StartupStyle.text.withAlphaComponent(0.82)
        let accent = isLive ? StartupStyle.accent : (isLearningSelection ? StartupStyle.mint : StartupStyle.accent.withAlphaComponent(0.74))

        switch gestureAction {
        case .move:
            drawStep("1", at: point(14, 14, origin, scale), accent: accent, scale: scale)
            drawHand(at: point(91, 84, origin, scale), scale: 0.88 * scale, pose: .raised,
                     mirrored: false, primary: true, ink: ink, accent: accent)
            drawMoveArrow(from: point(150, 46, origin, scale), to: point(228, 46, origin, scale),
                          color: accent, scale: scale)
            drawPointer(at: point(225, 47, origin, scale), color: accent, scale: scale)
        case .click:
            drawStep("1", at: point(5, 14, origin, scale), accent: accent, scale: scale)
            drawHand(at: point(50, 82, origin, scale), scale: 0.62 * scale, pose: .raised,
                     mirrored: false, primary: true, ink: ink, accent: accent)
            drawArrow(from: point(76, 43, origin, scale), to: point(101, 43, origin, scale), color: accent, scale: scale)
            drawStep("2", at: point(91, 14, origin, scale), accent: accent, scale: scale)
            drawHand(at: point(137, 82, origin, scale), scale: 0.62 * scale, pose: .bent,
                     mirrored: false, primary: true, ink: ink, accent: accent)
            drawArrow(from: point(164, 43, origin, scale), to: point(189, 43, origin, scale), color: accent, scale: scale)
            drawStep("3", at: point(179, 14, origin, scale), accent: accent, scale: scale)
            drawHand(at: point(225, 82, origin, scale), scale: 0.62 * scale, pose: .raised,
                     mirrored: false, primary: true, ink: ink, accent: accent)
        case .scroll:
            drawStep("1", at: point(14, 14, origin, scale), accent: accent, scale: scale)
            drawHand(at: point(105, 82, origin, scale), scale: 0.88 * scale, pose: .pinch,
                     mirrored: false, primary: true, ink: ink, accent: accent)
            drawContact(at: point(107, 30, origin, scale), color: accent, scale: scale)
            drawStep("2", at: point(151, 14, origin, scale), accent: accent, scale: scale)
            drawVerticalTravel(x: origin.x + 204 * scale, y: origin.y + 18 * scale,
                               height: 58 * scale, color: accent, scale: scale)
        case .select:
            drawStep("1", at: point(2, 14, origin, scale), accent: accent, scale: scale)
            drawHand(at: point(43, 81, origin, scale), scale: 0.55 * scale, pose: .raised,
                     mirrored: false, primary: true, ink: ink, accent: accent)
            drawArrow(from: point(65, 43, origin, scale), to: point(83, 43, origin, scale), color: accent, scale: scale)
            drawStep("2", at: point(77, 14, origin, scale), accent: accent, scale: scale)
            drawHand(at: point(122, 81, origin, scale), scale: 0.53 * scale, pose: .lShape,
                     mirrored: true, primary: true, ink: ink, accent: accent)
            drawHand(at: point(165, 81, origin, scale), scale: 0.53 * scale, pose: .lShape,
                     mirrored: false, primary: false, ink: ink, accent: accent)
            drawMoveArrow(from: point(101, 88, origin, scale), to: point(137, 88, origin, scale),
                          color: accent, scale: scale)
            drawStep("3", at: point(181, 14, origin, scale), accent: accent, scale: scale)
            drawHand(at: point(223, 78, origin, scale), scale: 0.48 * scale, pose: .open,
                     mirrored: false, primary: true, ink: ink, accent: accent)
            drawReleaseRays(at: point(229, 28, origin, scale), color: accent, scale: scale)
        }
    }

    private func point(_ x: CGFloat, _ y: CGFloat, _ origin: CGPoint, _ scale: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
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
        case .raised:
            drawFinger(rect(-13, 31, 10, 42), radius: 5, fill: fill, stroke: stroke, scale: scale, rect: rect)
            drawFinger(rect(1, 32, 10, 38), radius: 5, fill: fill, stroke: stroke, scale: scale, rect: rect)
            drawFoldedFingers(anchor: anchor, scale: scale, mirrored: mirrored, fill: fill, ink: stroke)
            drawThumb(anchor: anchor, scale: scale, mirrored: mirrored, extended: true, fill: fill, stroke: stroke)
            drawPalmAndWrist()
            drawTip(at: CGPoint(x: px(-8), y: py(72)), color: accent, scale: scale)
            drawTip(at: CGPoint(x: px(6), y: py(68)), color: accent, scale: scale)
        case .bent:
            drawBentFinger(points: [(-8, 34), (-10, 51), (-1, 55)], anchor: anchor, scale: scale, mirrored: mirrored, fill: fill, stroke: stroke)
            drawBentFinger(points: [(6, 34), (5, 49), (15, 51)], anchor: anchor, scale: scale, mirrored: mirrored, fill: fill, stroke: stroke)
            drawFoldedFingers(anchor: anchor, scale: scale, mirrored: mirrored, fill: fill, ink: stroke)
            drawThumb(anchor: anchor, scale: scale, mirrored: mirrored, extended: true, fill: fill, stroke: stroke)
            drawPalmAndWrist()
            drawTip(at: CGPoint(x: px(-1), y: py(55)), color: accent, scale: scale)
            drawTip(at: CGPoint(x: px(15), y: py(51)), color: accent, scale: scale)
        case .pinch:
            drawBentFinger(points: [(-8, 34), (-9, 57), (2, 64), (12, 57)], anchor: anchor, scale: scale, mirrored: mirrored, fill: fill, stroke: stroke)
            drawFoldedFingers(anchor: anchor, scale: scale, mirrored: mirrored, fill: fill, ink: stroke)
            drawPinchingThumb(anchor: anchor, scale: scale, mirrored: mirrored, fill: fill, stroke: stroke)
            drawPalmAndWrist()
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
                                   fill: NSColor, ink: NSColor) {
        for index in 0..<3 {
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

    private func drawContact(at center: CGPoint, color: NSColor, scale: CGFloat) {
        color.withAlphaComponent(0.16).setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - 10 * scale, y: center.y - 10 * scale,
                                    width: 20 * scale, height: 20 * scale)).fill()
        color.setStroke()
        let ring = NSBezierPath(ovalIn: NSRect(x: center.x - 5 * scale, y: center.y - 5 * scale,
                                               width: 10 * scale, height: 10 * scale))
        ring.lineWidth = max(1, 1.5 * scale); ring.stroke()
    }

    private func drawStep(_ number: String, at center: CGPoint, accent: NSColor, scale: CGFloat) {
        let size = 15 * scale
        accent.withAlphaComponent(0.13).setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x, y: center.y, width: size, height: size)).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: max(7, 8 * scale), weight: .bold),
            .foregroundColor: accent
        ]
        let string = NSAttributedString(string: number, attributes: attributes)
        let textSize = string.size()
        string.draw(at: CGPoint(x: center.x + (size - textSize.width) / 2,
                                y: center.y + (size - textSize.height) / 2))
    }

    private func drawArrow(from start: CGPoint, to end: CGPoint, color: NSColor, scale: CGFloat) {
        color.withAlphaComponent(0.75).setStroke()
        let path = NSBezierPath()
        path.move(to: start); path.line(to: end)
        path.move(to: end); path.line(to: CGPoint(x: end.x - 5 * scale, y: end.y - 4 * scale))
        path.move(to: end); path.line(to: CGPoint(x: end.x - 5 * scale, y: end.y + 4 * scale))
        path.lineWidth = max(1, 1.4 * scale); path.lineCapStyle = .round; path.lineJoinStyle = .round; path.stroke()
    }

    private func drawMoveArrow(from start: CGPoint, to end: CGPoint, color: NSColor, scale: CGFloat) {
        drawArrow(from: start, to: end, color: color, scale: scale)
        let reverseEnd = CGPoint(x: start.x, y: start.y)
        let reverseStart = CGPoint(x: end.x, y: end.y)
        color.withAlphaComponent(0.75).setStroke()
        let head = NSBezierPath()
        head.move(to: reverseEnd)
        head.line(to: CGPoint(x: reverseEnd.x + 5 * scale, y: reverseEnd.y - 4 * scale))
        head.move(to: reverseEnd)
        head.line(to: CGPoint(x: reverseEnd.x + 5 * scale, y: reverseEnd.y + 4 * scale))
        head.lineWidth = max(1, 1.4 * scale); head.lineCapStyle = .round; head.stroke()
        _ = reverseStart
    }

    private func drawVerticalTravel(x: CGFloat, y: CGFloat, height: CGFloat, color: NSColor, scale: CGFloat) {
        let start = CGPoint(x: x, y: y + height)
        let end = CGPoint(x: x, y: y)
        color.setStroke()
        let path = NSBezierPath()
        path.move(to: start); path.line(to: end)
        path.move(to: end); path.line(to: CGPoint(x: x - 5 * scale, y: y + 6 * scale))
        path.move(to: end); path.line(to: CGPoint(x: x + 5 * scale, y: y + 6 * scale))
        path.move(to: start); path.line(to: CGPoint(x: x - 5 * scale, y: y + height - 6 * scale))
        path.move(to: start); path.line(to: CGPoint(x: x + 5 * scale, y: y + height - 6 * scale))
        path.lineWidth = max(1.2, 1.7 * scale); path.lineCapStyle = .round; path.lineJoinStyle = .round; path.stroke()
        for offset in [-14, 0, 14] as [CGFloat] {
            color.withAlphaComponent(offset == 0 ? 0.8 : 0.28).setFill()
            NSBezierPath(ovalIn: NSRect(x: x - 2.5 * scale, y: y + height / 2 + offset * scale - 2.5 * scale,
                                        width: 5 * scale, height: 5 * scale)).fill()
        }
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

    private func drawReleaseRays(at center: CGPoint, color: NSColor, scale: CGFloat) {
        color.setStroke()
        let rays = NSBezierPath()
        for angle in stride(from: CGFloat(-0.9), through: CGFloat(0.9), by: CGFloat(0.45)) {
            rays.move(to: CGPoint(x: center.x + cos(angle) * 7 * scale, y: center.y + sin(angle) * 7 * scale))
            rays.line(to: CGPoint(x: center.x + cos(angle) * 13 * scale, y: center.y + sin(angle) * 13 * scale))
        }
        rays.lineWidth = max(1, 1.4 * scale); rays.lineCapStyle = .round; rays.stroke()
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
