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

    init(content: NSView, cornerRadius: CGFloat = 24, useNativeGlass: Bool = true) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.borderWidth = 1

        let material = Self.makeMaterial(content: content, cornerRadius: cornerRadius, useNativeGlass: useNativeGlass)
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

    private static func makeMaterial(content: NSView, cornerRadius: CGFloat, useNativeGlass: Bool) -> NSView {
        // Xcode versions before 26 do not declare NSGlassEffectView. A runtime
        // availability check alone would still fail to compile with their SDKs.
#if compiler(>=6.2)
        if #available(macOS 26.0, *), useNativeGlass {
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
