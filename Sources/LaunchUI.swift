import AppKit

/// The launch workspace is composed separately from camera and input ownership so
/// its layout can also be reviewed without starting capture or posting events.
final class LaunchContentView: NSView {
    private var workspaceWidth: NSLayoutConstraint!
    private let backdrop = WindowBackdropView(frame: .zero)
    init(title: NSTextField, cameraStatus: NSTextField, start: NSButton,
         practiceButton: NSButton, settingsButton: NSButton, guide: GestureGuideView,
         preview: NSView, feedback: NSView, practice: NSView,
         setupDisclosure: NSView, setupRows: NSView, settingsRows: NSView, diagnostics: NSView? = nil) {
        super.init(frame: .zero)
        wantsLayer = true
        updateColors()
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backdrop)
        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        practiceButton.contentTintColor = StartupStyle.text
        practiceButton.controlSize = .large
        settingsButton.contentTintColor = StartupStyle.text
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.textColor = StartupStyle.text
        let icon = NSImageView(image: NSImage(systemSymbolName: "hand.point.up.left",
                                             accessibilityDescription: nil) ?? NSImage())
        icon.symbolConfiguration = .init(pointSize: 19, weight: .medium)
        icon.contentTintColor = StartupStyle.text
        icon.setAccessibilityElement(false)
        let brand = NSStackView(views: [icon, title])
        brand.spacing = 8
        let header = NSStackView(views: [brand, NSView(), settingsButton])
        header.alignment = .centerY

        let headline = NSTextField(labelWithString: "Your Mac, by hand.")
        headline.font = .systemFont(ofSize: 32, weight: .medium)
        headline.textColor = StartupStyle.text
        headline.alignment = .center
        let subtitle = NSTextField(wrappingLabelWithString:
            "Show your hand. Move to aim.")
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = StartupStyle.muted
        subtitle.alignment = .center

        let divider = NSBox()
        divider.boxType = .separator
        let buttons = NSStackView(views: [start, divider, practiceButton])
        buttons.alignment = .centerY
        buttons.spacing = 12
        buttons.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        let actionSurface = GlassControlSurface(content: buttons, cornerRadius: 26)
        let hero = NSStackView(views: [headline, subtitle, actionSurface])
        hero.orientation = .vertical
        hero.alignment = .centerX
        hero.spacing = 10
        hero.setCustomSpacing(20, after: subtitle)

        let liveText = StartupStyle.column([cameraStatus, feedback], spacing: 5)
        // Keep this column at its content height when centered beside the preview.
        liveText.setHuggingPriority(.required, for: .vertical)
        let live = NSStackView(views: [preview, liveText])
        live.alignment = .centerY
        live.spacing = 22
        let privacyIcon = NSImageView(image: NSImage(systemSymbolName: "lock.shield",
                                                    accessibilityDescription: nil) ?? NSImage())
        privacyIcon.contentTintColor = StartupStyle.muted
        privacyIcon.setAccessibilityElement(false)
        let privacy = NSTextField(labelWithString: "Camera stays on this Mac")
        privacy.font = .systemFont(ofSize: 11)
        privacy.textColor = StartupStyle.muted
        let escape = NSTextField(labelWithString: "Esc to pause")
        escape.font = .systemFont(ofSize: 11)
        escape.textColor = StartupStyle.muted
        let footer = NSStackView(views: [privacyIcon, privacy, NSView(), escape])
        footer.spacing = 6
        footer.alignment = .centerY

        let details = StartupStyle.column([setupDisclosure, setupRows], spacing: 12)
        let diagnosticViews = diagnostics.map { [$0] } ?? []
        let body = StartupStyle.column([settingsRows, guide, live, practice] + diagnosticViews + [details], spacing: 24)
        body.setCustomSpacing(18, after: practice)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false
        let document = TopAlignedDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        document.addSubview(body)
        for view in [header, hero, scroll, footer] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        for view in [body, guide, live, liveText, feedback, practice, details,
                     setupDisclosure, setupRows, settingsRows, subtitle, buttons, actionSurface, divider] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        workspaceWidth = body.widthAnchor.constraint(equalToConstant: 840)
        let feedbackHeight = feedback.heightAnchor.constraint(equalToConstant: 48)
        feedbackHeight.priority = .defaultHigh
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28),
            header.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 16),
            header.heightAnchor.constraint(equalToConstant: 30),
            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 24),
            hero.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 25),
            hero.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32),
            hero.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -32),
            subtitle.widthAnchor.constraint(equalTo: hero.widthAnchor),
            actionSurface.heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
            start.widthAnchor.constraint(greaterThanOrEqualToConstant: 92),
            divider.widthAnchor.constraint(equalToConstant: 1),
            divider.heightAnchor.constraint(equalToConstant: 20),
            scroll.topAnchor.constraint(equalTo: hero.bottomAnchor, constant: 32),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -14),
            footer.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            privacyIcon.widthAnchor.constraint(equalToConstant: 13),
            privacyIcon.heightAnchor.constraint(equalToConstant: 14),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            body.centerXAnchor.constraint(equalTo: document.centerXAnchor),
            workspaceWidth,
            feedbackHeight,
            liveText.trailingAnchor.constraint(equalTo: live.trailingAnchor),
            liveText.centerYAnchor.constraint(equalTo: live.centerYAnchor),
            cameraStatus.widthAnchor.constraint(equalTo: liveText.widthAnchor),
            body.topAnchor.constraint(equalTo: document.topAnchor, constant: 4),
            body.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -16),
            preview.widthAnchor.constraint(equalToConstant: 224),
            preview.heightAnchor.constraint(equalToConstant: 126),
            feedback.widthAnchor.constraint(equalTo: liveText.widthAnchor),
            practice.heightAnchor.constraint(equalToConstant: 260),
            guide.heightAnchor.constraint(equalToConstant: 280)
        ])
        for view in [guide, live, practice, details, setupDisclosure, setupRows, settingsRows] + diagnosticViews {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        workspaceWidth.constant = min(840, max(0, bounds.width - 64))
        super.layout()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }
}
