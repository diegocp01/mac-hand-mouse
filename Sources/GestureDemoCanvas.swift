import AppKit

/// Hand-drawn vector artwork for the gesture tutorial. Pure drawing: no camera, no input.
final class GestureDemoCanvas: NSView {
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

    func refreshAppearance() {
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
            drawCentered("Point and hold still for 1 second", in: NSRect(x: rect.minX, y: button.maxY + 14, width: rect.width, height: 18),
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
