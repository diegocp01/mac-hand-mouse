import AppKit

/// A quiet instrument-panel palette. All status information also has text labels.
enum StartupStyle {
    static let background = NSColor(srgbRed: 0.035, green: 0.055, blue: 0.08, alpha: 1)
    static let surface = NSColor(srgbRed: 0.065, green: 0.09, blue: 0.12, alpha: 1)
    static let accent = NSColor(srgbRed: 0.35, green: 0.88, blue: 0.96, alpha: 1)
    static let muted = NSColor(srgbRed: 0.66, green: 0.74, blue: 0.80, alpha: 1)

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
