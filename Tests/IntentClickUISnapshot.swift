import AppKit

/// Renders inert production views only: no camera session, event posting, or windows.
@main enum IntentClickUISnapshot {
    private final class Canvas: NSView {
        override var isFlipped: Bool { true }
    }

    private struct State {
        let name: String
        let title: String
        let fraction: Double?
        let clicked: Bool
        let leftHit: Bool
        let rightClick: Bool
        let holding: Bool
    }

    static func main() throws {
        _ = NSApplication.shared
        let destination = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/private/tmp")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let size = NSSize(width: 1424, height: 1270)
        let canvas = Canvas(frame: NSRect(origin: .zero, size: size))
        canvas.appearance = NSAppearance(named: .darkAqua)
        canvas.wantsLayer = true
        canvas.layer?.backgroundColor = StartupStyle.background.cgColor
        let title = label("Point, hold, click", size: 25, weight: .semibold)
        title.frame = CGRect(x: 24, y: 18, width: 1000, height: 34)
        canvas.addSubview(title)
        let subtitle = label("Production feedback and practice views · Camera off · No system input", size: 12)
        subtitle.textColor = StartupStyle.muted
        subtitle.frame = CGRect(x: 24, y: 55, width: 1000, height: 20)
        canvas.addSubview(subtitle)

        let states = [
            State(name: "01  MOVE", title: "Raise middle to click", fraction: nil,
                clicked: false, leftHit: false, rightClick: false, holding: false),
            State(name: "02  HOLD START · 0.0 s", title: "Click in 1.0 s", fraction: 0,
                clicked: false, leftHit: false, rightClick: false, holding: true),
            State(name: "03  HALFWAY · 0.5 s", title: "Click in 0.5 s", fraction: 0.5,
                clicked: false, leftHit: false, rightClick: false, holding: true),
            State(name: "04  LEFT CLICK · 1.0 s", title: "Target hit ✓", fraction: nil,
                clicked: true, leftHit: true, rightClick: false, holding: true),
            State(name: "05  RIGHT CLICK", title: "Right click 1 ✓", fraction: nil,
                clicked: true, leftHit: false, rightClick: true, holding: false),
            State(name: "06  RIGHT AFTER LEFT", title: "Right click 1 ✓", fraction: nil,
                clicked: true, leftHit: true, rightClick: true, holding: false)
        ]
        var feedbackViews: [ClickFeedbackView] = []
        for (index, state) in states.enumerated() {
            let column = index % 2
            let row = index / 2
            let x = 24 + CGFloat(column) * 704
            let y = 92 + CGFloat(row) * 384
            let heading = label(state.name, size: 11, weight: .semibold)
            heading.textColor = StartupStyle.muted
            heading.frame = CGRect(x: x, y: y, width: 676, height: 20)
            canvas.addSubview(heading)

            let feedback = ClickFeedbackView(frame: CGRect(x: x, y: y + 26, width: 676, height: 66))
            feedback.update(title: state.title, detail: "Synthetic practice state. No system input is sent.",
                fraction: state.fraction, clicked: state.clicked)
            canvas.addSubview(feedback)
            feedbackViews.append(feedback)

            let practice = PracticeView(frame: CGRect(x: x, y: y + 102, width: 676, height: 260))
            canvas.addSubview(practice)
            let firstTarget = practice.point(forNormalizedInput: CGPoint(x: 0.72, y: 0.37))
            let nextTarget = firstTarget
            _ = practice.update(point: firstTarget, progress: 0, clicked: false)
            if state.leftHit {
                precondition(practice.update(point: firstTarget, progress: 1, clicked: true, holding: state.holding),
                    "A left click at the target must register a successful hit")
            }
            if state.rightClick {
                let rightTarget = state.leftHit ? nextTarget : firstTarget
                precondition(!practice.update(point: rightTarget, progress: 0, clicked: false,
                    rightClicked: true, holding: false), "A right click cannot claim a left target")
            } else if !state.leftHit {
                precondition(!practice.update(point: firstTarget, progress: state.fraction ?? 0,
                    clicked: false, holding: state.holding), "A countdown cannot score before its click")
            }
            precondition(practice.hits == (state.leftHit ? 1 : 0), "Left-target count remains independent")
            precondition(practice.rightClicks == (state.rightClick ? 1 : 0), "Right-click count remains independent")
            let accessibility = practice.accessibilityLabel() ?? ""
            precondition(accessibility.contains("\(practice.hits) successful left-click targets") &&
                accessibility.contains("\(practice.rightClicks) practice right clicks"),
                "Practice announces both counters accurately")

            let rings = UIRenderSupport.descendants(of: feedback).compactMap { $0 as? DwellRingView }
            precondition(rings.count == 1, "Production feedback exposes one rendered countdown ring")
            precondition(rings[0].isHidden == (state.fraction == nil && !state.clicked),
                "The zero-progress countdown and click confirmation must remain visible")
            precondition(rings[0].progress == (state.fraction ?? 0) && rings[0].clicked == state.clicked,
                "Feedback ring reflects the supplied observed state")
        }

        try UIRenderSupport.prepare(canvas, size: size)
        for feedback in feedbackViews {
            precondition(UIRenderSupport.ambiguousViews(in: feedback).isEmpty,
                "Feedback controls must have determinate layout")
            precondition(UIRenderSupport.fullyClippedControls(in: feedback).isEmpty,
                "Feedback labels and progress must remain visible")
        }
        let output = destination.appendingPathComponent("intent-click-production-states.png")
        try UIRenderSupport.writePNG(of: canvas, size: size, to: output)
        print("Validated six production feedback/practice states: \(output.path)")
    }

    private static func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = StartupStyle.text
        return field
    }
}
