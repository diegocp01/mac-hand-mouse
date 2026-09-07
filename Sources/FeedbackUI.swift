import AppKit

final class TopAlignedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

/// A determinate ring: values come from observed gesture frames, never a UI timer.
final class DwellRingView: NSView {
    var progress: Double = 0 { didSet { needsDisplay = true } }
    var clicked = false { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) / 2 - 5
        let track = NSBezierPath(ovalIn: CGRect(x: center.x - radius, y: center.y - radius,
                                               width: radius * 2, height: radius * 2))
        // Dark outline stays legible over a bright camera frame or another app.
        NSColor.black.withAlphaComponent(0.8).setStroke()
        track.lineWidth = 8; track.stroke()
        NSColor.white.withAlphaComponent(0.55).setStroke()
        track.lineWidth = 4; track.stroke()
        let fraction = clicked ? 1 : min(1, max(0, progress))
        // Avoid relying on AppKit's equal-angle arc behavior for zero progress.
        if fraction > 0 {
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: radius, startAngle: 90,
                          endAngle: 90 - CGFloat(fraction) * 360, clockwise: true)
            (clicked ? NSColor.white : NSColor.systemMint).setStroke()
            arc.lineWidth = 4; arc.lineCapStyle = .round; arc.stroke()
        }
        if clicked {
            let check = NSBezierPath()
            check.move(to: CGPoint(x: center.x - 7, y: center.y))
            check.line(to: CGPoint(x: center.x - 2, y: center.y - 5))
            check.line(to: CGPoint(x: center.x + 8, y: center.y + 6))
            NSColor.white.setStroke(); check.lineWidth = 3; check.stroke()
        }
    }
}

final class ClickFeedbackView: NSView {
    let title = NSTextField(labelWithString: "Ready when you are")
    let detail = NSTextField(wrappingLabelWithString: "Start the camera, then show one hand with your palm visible.")
    private let progress = NSProgressIndicator()
    private let ring = DwellRingView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.borderWidth = 1
        updateColors()
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        detail.maximumNumberOfLines = 2
        progress.isIndeterminate = false
        progress.minValue = 0; progress.maxValue = 1
        progress.style = .bar
        progress.setAccessibilityLabel("Time held toward dwell click")
        let text = NSStackView(views: [title, detail, progress])
        text.orientation = .vertical; text.alignment = .leading; text.spacing = 5
        for view in [ring, text] { view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view) }
        NSLayoutConstraint.activate([
            ring.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            ring.centerYAnchor.constraint(equalTo: centerYAnchor),
            ring.widthAnchor.constraint(equalToConstant: 48), ring.heightAnchor.constraint(equalToConstant: 48),
            text.leadingAnchor.constraint(equalTo: ring.trailingAnchor, constant: 12),
            text.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            text.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            text.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            progress.widthAnchor.constraint(equalTo: text.widthAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 92)
        ])
        update(title: "Ready when you are", detail: detail.stringValue)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }
    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            layer?.borderColor = NSColor.separatorColor.cgColor
        }
    }

    func update(title: String, detail: String, fraction: Double? = nil, clicked: Bool = false) {
        self.title.stringValue = title
        self.detail.stringValue = detail
        let clamped = fraction.map { min(1, max(0, $0)) }
        ring.progress = clamped ?? 0; ring.clicked = clicked
        progress.doubleValue = clamped ?? 0
        progress.isHidden = fraction == nil
        progress.setAccessibilityValueDescription(clamped.map { "\(Int(($0 * 100).rounded())) percent" })
        ring.isHidden = fraction == nil && !clicked
        setAccessibilityLabel(title + ". " + detail)
    }
}

/// The cursor indicator must never become an input target or activate Hand Mouse.
private final class CursorFeedbackPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Nonactivating and click-through; it never intercepts the click it previews.
final class CursorFeedback {
    private let panel: CursorFeedbackPanel
    private let ring = DwellRingView(frame: CGRect(x: 50, y: 30, width: 50, height: 50))
    private let label = NSTextField(labelWithString: "")

    init() {
        panel = CursorFeedbackPanel(contentRect: CGRect(x: 0, y: 0, width: 150, height: 110),
                                    styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = false; panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .ignoresCycle]
        let content = NSView(frame: panel.frame)
        content.setAccessibilityElement(false)
        content.setAccessibilityChildren([])
        content.addSubview(ring)
        label.frame = CGRect(x: 0, y: 3, width: 150, height: 22)
        label.alignment = .center; label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        label.textColor = .white; label.backgroundColor = NSColor.black.withAlphaComponent(0.85)
        label.drawsBackground = true
        content.addSubview(label); panel.contentView = content
    }

    func show(at point: CGPoint, displayID: CGDirectDisplayID, progress: Double, remaining: Double,
              clicked: Bool, restarted: Bool = false) {
        guard let primary = NSScreen.screens.first,
              let screen = NSScreen.screens.first(where: {
                  ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
              }) else { hide(); return }
        // CG mouse coordinates start at the primary display's top-left; AppKit starts bottom-left.
        let center = CursorFeedbackLayout.appKitPoint(point, primaryTop: primary.frame.maxY)
        // Use the locked target display, including its exact upper/right boundary.
        let layout = CursorFeedbackLayout(center: center, screen: screen.frame)
        panel.setFrameOrigin(layout.origin)
        ring.setFrameOrigin(layout.ringOrigin)
        label.setFrameOrigin(layout.labelOrigin)
        ring.progress = progress; ring.clicked = clicked
        label.stringValue = clicked ? "Clicked ✓"
            : String(format: restarted ? "Restarted · %.1f s" : "Click in %.1f s", max(0.1, remaining))
        if !panel.isVisible { panel.orderFrontRegardless() }
    }
    func hide() { panel.orderOut(nil) }
}
