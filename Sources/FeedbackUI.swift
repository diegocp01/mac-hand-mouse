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
    let title = NSTextField(wrappingLabelWithString: "Show your hand to move")
    let detail = NSTextField(wrappingLabelWithString: "Keep your hand visible. Move to aim.")
    private let progress = NSProgressIndicator()
    private let ring = DwellRingView()
    private var textInset: NSLayoutConstraint!

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        updateColors()
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        title.font = .systemFont(ofSize: 15, weight: .medium)
        title.textColor = StartupStyle.text
        title.setContentCompressionResistancePriority(.required, for: .vertical)
        detail.isHidden = true
        progress.isIndeterminate = false
        progress.minValue = 0; progress.maxValue = 1
        progress.style = .bar
        progress.setAccessibilityLabel("Time held after a deliberate click gesture")
        let text = NSStackView(views: [title, progress])
        text.orientation = .vertical; text.alignment = .leading; text.spacing = 4
        for view in [ring, text] { view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view) }
        textInset = text.leadingAnchor.constraint(equalTo: leadingAnchor)
        NSLayoutConstraint.activate([
            textInset,
            ring.leadingAnchor.constraint(equalTo: leadingAnchor),
            ring.centerYAnchor.constraint(equalTo: centerYAnchor),
            ring.widthAnchor.constraint(equalToConstant: 34), ring.heightAnchor.constraint(equalToConstant: 34),
            text.trailingAnchor.constraint(equalTo: trailingAnchor),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
            text.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 4),
            text.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -4),
            title.widthAnchor.constraint(equalTo: text.widthAnchor),
            progress.widthAnchor.constraint(equalTo: text.widthAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 48)
        ])
        update(title: title.stringValue, detail: detail.stringValue)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }
    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }

    func update(title: String, detail: String, fraction: Double? = nil, clicked: Bool = false) {
        self.title.stringValue = title
        self.detail.stringValue = detail
        toolTip = detail
        self.title.toolTip = detail
        let clamped = fraction.map { min(1, max(0, $0)) }
        ring.progress = clamped ?? 0; ring.clicked = clicked
        progress.doubleValue = clamped ?? 0
        progress.isHidden = fraction == nil
        progress.setAccessibilityValueDescription(clamped.map { "\(Int(($0 * 100).rounded())) percent" })
        ring.isHidden = fraction == nil && !clicked
        textInset.constant = ring.isHidden ? 0 : 46
        setAccessibilityLabel(title + ". " + detail)
    }
}

/// Task practice is driven by `InteractionEngine` output. These controls can reset
/// or choose a task, but clicking the drawn targets with a physical mouse cannot
/// complete them and this view never posts an OS event.
final class PracticeView: NSView {
    var onTaskChange: ((PracticeTask) -> Void)?
    private(set) var state = PracticeTaskState()
    var currentTask: PracticeTask { state.task }

    private let taskPicker = NSSegmentedControl(labels: ["Click", "Scroll", "Select text"],
                                                trackingMode: .selectOne, target: nil, action: nil)
    private let instruction = NSTextField(labelWithString: "")
    private let completion = NSTextField(labelWithString: "")
    private let retryButton = NSButton(title: "Retry", target: nil, action: nil)
    private let nextButton = NSButton(title: "Next", target: nil, action: nil)
    private var pointer: CGPoint?
    private var fraction = 0.0
    private var holding = false
    private(set) var hits = 0
    private(set) var rightClicks = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.borderWidth = 1
        setAccessibilityElement(true)
        setAccessibilityRole(.group)

        taskPicker.target = self; taskPicker.action = #selector(taskPicked)
        taskPicker.selectedSegment = 0
        taskPicker.setAccessibilityLabel("Practice task")
        instruction.font = .systemFont(ofSize: 13, weight: .medium)
        instruction.textColor = StartupStyle.muted
        completion.font = .systemFont(ofSize: 13, weight: .semibold)
        completion.textColor = .systemGreen
        retryButton.target = self; retryButton.action = #selector(retry)
        retryButton.bezelStyle = .rounded
        nextButton.target = self; nextButton.action = #selector(nextTask)
        nextButton.bezelStyle = .rounded

        for view in [taskPicker, instruction, completion, retryButton, nextButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            taskPicker.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            taskPicker.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            taskPicker.widthAnchor.constraint(equalToConstant: 300),
            instruction.leadingAnchor.constraint(equalTo: taskPicker.trailingAnchor, constant: 16),
            instruction.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            instruction.centerYAnchor.constraint(equalTo: taskPicker.centerYAnchor),
            completion.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            completion.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -13),
            retryButton.trailingAnchor.constraint(equalTo: nextButton.leadingAnchor, constant: -8),
            retryButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            nextButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            nextButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
        updateColors()
        reset(task: .click)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
        needsDisplay = true
    }

    private var canvas: CGRect {
        CGRect(x: 16, y: 54, width: max(1, bounds.width - 32), height: max(1, bounds.height - 104))
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = StartupStyle.surface.cgColor
            layer?.borderColor = StartupStyle.accent.withAlphaComponent(0.20).cgColor
        }
    }

    func reset(task: PracticeTask = .click) {
        state.reset(task: task)
        pointer = nil; fraction = 0; holding = false; hits = 0; rightClicks = 0
        taskPicker.selectedSegment = PracticeTask.allCases.firstIndex(of: task) ?? 0
        refreshChrome()
    }

    func select(_ task: PracticeTask) {
        reset(task: task)
        onTaskChange?(task)
    }

    @discardableResult
    func update(point: CGPoint?, progress: Double, clicked: Bool, rightClicked: Bool = false, holding: Bool = false, scrollY: Int32 = 0,
                dragging: Bool = false, interrupted: Bool = false) -> Bool {
        let normalizedPoint = point.flatMap(normalize)
        pointer = interrupted ? nil : point.flatMap { canvas.contains($0) ? $0 : nil }
        fraction = interrupted ? 0 : min(1, max(0, progress))
        let newlyCompleted = state.update(point: normalizedPoint, clicked: clicked,
                                          scrollY: scrollY, dragging: dragging,
                                          interrupted: interrupted || (point != nil && normalizedPoint == nil))
        self.holding = !interrupted && holding
        if !interrupted && normalizedPoint != nil && rightClicked { rightClicks += 1 }
        if newlyCompleted && currentTask == .click { hits += 1 }
        refreshChrome()
        return newlyCompleted
    }

    func interrupt() {
        _ = update(point: nil, progress: 0, clicked: false, interrupted: true)
    }

    private func normalize(_ point: CGPoint) -> CGPoint? {
        guard point.x.isFinite, point.y.isFinite, canvas.contains(point) else { return nil }
        return CGPoint(x: (point.x - canvas.minX) / canvas.width,
                       y: (point.y - canvas.minY) / canvas.height)
    }

    private func pixel(_ point: CGPoint) -> CGPoint {
        CGPoint(x: canvas.minX + point.x * canvas.width,
                y: canvas.minY + point.y * canvas.height)
    }

    func point(forNormalizedInput point: CGPoint) -> CGPoint { pixel(point) }

    private func pixel(_ rect: CGRect) -> CGRect {
        CGRect(x: canvas.minX + rect.minX * canvas.width,
               y: canvas.minY + rect.minY * canvas.height,
               width: rect.width * canvas.width, height: rect.height * canvas.height)
    }

    @objc private func taskPicked() {
        let index = min(PracticeTask.allCases.count - 1, max(0, taskPicker.selectedSegment))
        select(PracticeTask.allCases[index])
    }

    @objc private func retry() { select(currentTask) }

    @objc private func nextTask() {
        guard state.completed, let index = PracticeTask.allCases.firstIndex(of: currentTask),
              index + 1 < PracticeTask.allCases.count else { return }
        select(PracticeTask.allCases[index + 1])
    }

    private func refreshChrome() {
        switch currentTask {
        case .click: instruction.stringValue = "Click the Send button"
        case .scroll: instruction.stringValue = "Scroll to find Quarterly review"
        case .select: instruction.stringValue = "Highlight the sentence with both hands"
        }
        completion.stringValue = state.completed ? "✓  Task complete" : "Practice only · Your Mac is not controlled"
        completion.textColor = state.completed ? .systemGreen : StartupStyle.muted
        let isLast = currentTask == PracticeTask.allCases.last
        nextButton.isHidden = isLast
        nextButton.isEnabled = state.completed && !isLast
        setAccessibilityLabel("\(instruction.stringValue). \(state.completed ? "Task complete." : "Not complete.") \(hits) successful left-click targets. \(rightClicks) practice right clicks. Practice sends no system input.")
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.controlBackgroundColor.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: canvas, xRadius: 12, yRadius: 12).fill()
        switch currentTask {
        case .click: drawClickTask()
        case .scroll: drawScrollTask()
        case .select: drawSelectionTask()
        }
        drawPointer()
    }

    private func drawClickTask() {
        let card = CGRect(x: canvas.midX - 205, y: canvas.minY + 13,
                          width: 410, height: max(78, canvas.height - 26))
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(roundedRect: card, xRadius: 10, yRadius: 10).fill()
        let button = pixel(PracticeTaskState.clickTarget)
        draw("Ready to share?", at: CGPoint(x: card.minX + 20, y: button.minY + 2),
             font: .systemFont(ofSize: 15, weight: .semibold), color: .labelColor)
        draw("Send the finished note to your team.", at: CGPoint(x: card.minX + 20, y: button.maxY + 15),
             font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
        (state.completed ? NSColor.systemGreen : NSColor.controlAccentColor).setFill()
        NSBezierPath(roundedRect: button, xRadius: 7, yRadius: 7).fill()
        draw(state.completed ? "Sent ✓" : "Send", centeredIn: button,
             font: .systemFont(ofSize: 13, weight: .semibold), color: .white)
    }

    private func drawScrollTask() {
        let viewport = pixel(PracticeTaskState.listViewport)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: viewport, xRadius: 9, yRadius: 9).addClip()
        let target = pixel(state.visibleListTargetRow)
        let rowHeight = target.height
        let names = ["Budget notes", "Project kickoff", "Design review", "Quarterly review", "Launch checklist", "Customer calls", "Team planning"]
        for (offset, name) in zip(-3...3, names) {
            let row = CGRect(x: target.minX, y: target.minY + CGFloat(offset) * rowHeight,
                             width: target.width, height: rowHeight)
            if name == "Quarterly review" {
                (state.completed ? NSColor.systemGreen : NSColor.controlAccentColor).withAlphaComponent(0.17).setFill()
                NSBezierPath(roundedRect: row.insetBy(dx: 5, dy: 3), xRadius: 6, yRadius: 6).fill()
            }
            draw(name, at: CGPoint(x: row.minX + 14, y: row.midY - 8),
                 font: .systemFont(ofSize: 12, weight: name == "Quarterly review" ? .semibold : .regular),
                 color: name == "Quarterly review" ? .labelColor : .secondaryLabelColor)
            NSColor.separatorColor.setStroke()
            let divider = NSBezierPath(); divider.move(to: CGPoint(x: row.minX + 10, y: row.maxY))
            divider.line(to: CGPoint(x: row.maxX - 10, y: row.maxY)); divider.lineWidth = 0.5; divider.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        NSColor.separatorColor.setStroke()
        let outline = NSBezierPath(roundedRect: viewport, xRadius: 9, yRadius: 9)
        outline.lineWidth = 1; outline.stroke()
        draw("Scroll ↓", at: CGPoint(x: viewport.maxX + 12, y: viewport.midY - 7),
             font: .systemFont(ofSize: 11, weight: .semibold), color: .secondaryLabelColor)
    }

    private func drawSelectionTask() {
        let card = CGRect(x: canvas.minX + 44, y: canvas.minY + 16,
                          width: canvas.width - 88, height: max(72, canvas.height - 32))
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(roundedRect: card, xRadius: 10, yRadius: 10).fill()
        draw("Highlight this sentence", at: CGPoint(x: card.minX + 20, y: card.minY + 16),
             font: .systemFont(ofSize: 11, weight: .semibold), color: .secondaryLabelColor)
        let sentence = pixel(PracticeTaskState.sentenceTarget)
        if state.completed {
            NSColor.selectedTextBackgroundColor.withAlphaComponent(0.72).setFill()
            NSBezierPath(roundedRect: sentence.insetBy(dx: -3, dy: -2), xRadius: 3, yRadius: 3).fill()
        } else if let start = state.selectionStart, let end = state.selectionEnd {
            let a = pixel(start), b = pixel(end)
            let partial = CGRect(x: min(a.x, b.x), y: sentence.minY - 2,
                                 width: max(2, abs(b.x - a.x)), height: sentence.height + 4)
                .intersection(sentence.insetBy(dx: -3, dy: -2))
            NSColor.selectedTextBackgroundColor.withAlphaComponent(0.55).setFill()
            NSBezierPath(roundedRect: partial, xRadius: 3, yRadius: 3).fill()
        }
        let words = "Thoughtful tools make everyday work feel simple, direct, and effortless."
        let baseFont = NSFont.systemFont(ofSize: 15, weight: .medium)
        let baseWidth = (words as NSString).size(withAttributes: [.font: baseFont]).width
        let fontSize = min(18, max(11, 15 * (sentence.width - 16) / max(1, baseWidth)))
        let sentenceFont = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let wordSize = (words as NSString).size(withAttributes: [.font: sentenceFont])
        draw(words, at: CGPoint(x: sentence.minX + 8, y: sentence.midY - wordSize.height / 2),
             font: sentenceFont, color: .labelColor)
        NSColor.controlAccentColor.withAlphaComponent(0.55).setStroke()
        for x in [sentence.minX, sentence.maxX] {
            let marker = NSBezierPath(); marker.move(to: CGPoint(x: x, y: sentence.minY - 4))
            marker.line(to: CGPoint(x: x, y: sentence.maxY + 4)); marker.lineWidth = 1.5; marker.stroke()
        }
        if state.completed {
            draw("✓", at: CGPoint(x: sentence.maxX + 12, y: sentence.midY - 10),
                 font: .systemFont(ofSize: 18, weight: .bold), color: .systemGreen)
        }
    }

    private func drawPointer() {
        guard let pointer else { return }
        NSColor.labelColor.setFill()
        NSColor.white.withAlphaComponent(0.9).setStroke()
        let dot = NSBezierPath(ovalIn: CGRect(x: pointer.x - 5, y: pointer.y - 5, width: 10, height: 10))
        dot.lineWidth = 2; dot.fill(); dot.stroke()
        if holding {
            NSColor.systemMint.withAlphaComponent(0.25).setStroke()
            let track = NSBezierPath(ovalIn: CGRect(x: pointer.x - 17, y: pointer.y - 17, width: 34, height: 34))
            track.lineWidth = 3; track.stroke()
        }
        guard holding && fraction > 0 else { return }
        let arc = NSBezierPath()
        arc.appendArc(withCenter: pointer, radius: 17, startAngle: -90,
                      endAngle: -90 + CGFloat(fraction) * 360, clockwise: false)
        NSColor.systemMint.setStroke(); arc.lineWidth = 3; arc.lineCapStyle = .round; arc.stroke()
    }

    private func draw(_ text: String, at point: CGPoint, font: NSFont, color: NSColor) {
        (text as NSString).draw(at: point, withAttributes: [.font: font, .foregroundColor: color])
    }

    private func draw(_ text: String, centeredIn rect: CGRect, font: NSFont, color: NSColor) {
        let size = (text as NSString).size(withAttributes: [.font: font])
        draw(text, at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
             font: font, color: color)
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
              clicked: Bool, caption: String? = nil) {
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
        ring.isHidden = caption != nil
        label.stringValue = caption ?? (clicked ? "Clicked ✓"
            : String(format: "Click in %.1f s", max(0.1, remaining)))
        if !panel.isVisible { panel.orderFrontRegardless() }
    }
    func hide() { panel.orderOut(nil) }
}
