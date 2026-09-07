import AppKit

/// A quiet instrument-panel palette. All status information also has text labels.
enum StartupStyle {
    static let background = NSColor(srgbRed: 0.035, green: 0.055, blue: 0.08, alpha: 1)
    static let surface = NSColor(srgbRed: 0.065, green: 0.09, blue: 0.12, alpha: 1)
    static let accent = NSColor(srgbRed: 0.35, green: 0.88, blue: 0.96, alpha: 1)
    static let muted = NSColor(srgbRed: 0.66, green: 0.74, blue: 0.80, alpha: 1)

    static func caption(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        label.textColor = accent
        return label
    }

    static func column(_ views: [NSView], spacing: CGFloat = 10) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        return stack
    }
}

/// Live setup milestones, derived from permission/capture state rather than a saved onboarding flag.
final class SetupStepView: NSView {
    private let number: String
    private var presentation = ""
    private let badge = NSTextField(labelWithString: "")
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(wrappingLabelWithString: "")

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
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = StartupStyle.muted
        let heading = NSStackView(views: [badge, self.title])
        heading.spacing = 8
        let text = StartupStyle.column([heading, detail], spacing: 6)
        text.translatesAutoresizingMaskIntoConstraints = false
        addSubview(text)
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            text.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            text.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            text.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            detail.widthAnchor.constraint(equalTo: text.widthAnchor)
        ])
        update(complete: false, active: false, detail: "")
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(complete: Bool, active: Bool, detail: String) {
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let nextPresentation = "\(complete)|\(active)|\(contrast)|\(detail)"
        guard presentation != nextPresentation else { return }
        presentation = nextPresentation
        let badgeText = complete ? "✓" : number
        if badge.stringValue != badgeText { badge.stringValue = badgeText }
        if self.detail.stringValue != detail { self.detail.stringValue = detail }
        badge.textColor = complete || active ? StartupStyle.accent : StartupStyle.muted
        layer?.backgroundColor = StartupStyle.surface.cgColor
        layer?.borderColor = (active || contrast ? StartupStyle.accent : StartupStyle.muted.withAlphaComponent(0.22)).cgColor
        setAccessibilityElement(true)
        setAccessibilityLabel("Step \(number), \(title.stringValue). \(complete ? "Complete. " : "")\(detail)")
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
