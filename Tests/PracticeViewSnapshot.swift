import AppKit

@main
enum PracticeViewSnapshot {
    static func main() throws {
        _ = NSApplication.shared
        let destination = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/private/tmp")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        try render(name: "practice-click.png", size: NSSize(width: 844, height: 260), task: .click,
                   destination: destination) { view in
            let point = view.point(forNormalizedInput: CGPoint(x: 0.72, y: 0.37))
            _ = view.update(point: point, progress: 0, clicked: false)
        }
        try render(name: "practice-click-narrow.png", size: NSSize(width: 620, height: 260), task: .click,
                   destination: destination) { view in
            let point = view.point(forNormalizedInput: CGPoint(x: 0.72, y: 0.37))
            _ = view.update(point: point, progress: 0, clicked: false)
        }
        try render(name: "practice-click-success.png", size: NSSize(width: 844, height: 260), task: .click,
                   destination: destination) { view in
            let point = view.point(forNormalizedInput: CGPoint(x: 0.72, y: 0.37))
            _ = view.update(point: point, progress: 0, clicked: false)
            _ = view.update(point: point, progress: 0, clicked: true)
            precondition(view.state.completed, "Click snapshot must show a completed production-output state")
        }
        try render(name: "practice-scroll.png", size: NSSize(width: 844, height: 260), task: .scroll,
                   destination: destination) { view in
            let point = view.point(forNormalizedInput: CGPoint(x: 0.50, y: 0.50))
            _ = view.update(point: point, progress: 0, clicked: false, scrollY: 0)
            _ = view.update(point: point, progress: 0, clicked: false, scrollY: -160)
        }
        try render(name: "practice-scroll-narrow.png", size: NSSize(width: 620, height: 260), task: .scroll,
                   destination: destination) { view in
            let point = view.point(forNormalizedInput: CGPoint(x: 0.50, y: 0.50))
            _ = view.update(point: point, progress: 0, clicked: false, scrollY: 0)
            _ = view.update(point: point, progress: 0, clicked: false, scrollY: -160)
        }
        try render(name: "practice-scroll-success.png", size: NSSize(width: 844, height: 260), task: .scroll,
                   destination: destination) { view in
            let point = view.point(forNormalizedInput: CGPoint(x: 0.50, y: 0.50))
            _ = view.update(point: point, progress: 0, clicked: false, scrollY: 0)
            _ = view.update(point: point, progress: 0, clicked: false, scrollY: -190)
            precondition(view.state.completed, "Scroll snapshot must show a completed production-output state")
        }
        try render(name: "practice-select.png", size: NSSize(width: 844, height: 260), task: .select,
                   destination: destination) { view in
            let point = view.point(forNormalizedInput: CGPoint(x: 0.25, y: 0.49))
            _ = view.update(point: point, progress: 0, clicked: false, dragging: false)
        }
        try render(name: "practice-select-narrow.png", size: NSSize(width: 620, height: 260), task: .select,
                   destination: destination) { view in
            let point = view.point(forNormalizedInput: CGPoint(x: 0.25, y: 0.49))
            _ = view.update(point: point, progress: 0, clicked: false, dragging: false)
        }
        try render(name: "practice-select-success.png", size: NSSize(width: 844, height: 260), task: .select,
                   destination: destination) { view in
            let start = view.point(forNormalizedInput: CGPoint(x: 0.16, y: 0.49))
            let end = view.point(forNormalizedInput: CGPoint(x: 0.84, y: 0.49))
            _ = view.update(point: start, progress: 0, clicked: false, dragging: false)
            _ = view.update(point: start, progress: 0, clicked: false, dragging: true)
            _ = view.update(point: end, progress: 0, clicked: false, dragging: true)
            _ = view.update(point: end, progress: 0, clicked: false, dragging: false)
            precondition(view.state.completed, "Selection snapshot must show a completed released drag")
        }
    }

    private static func render(name: String, size: NSSize, task: PracticeTask,
                               destination: URL, prepare: (PracticeView) -> Void) throws {
        let view = PracticeView(frame: NSRect(origin: .zero, size: size))
        view.appearance = NSAppearance(named: .darkAqua)
        view.reset(task: task)
        try UIRenderSupport.prepare(view, size: size)
        prepare(view)
        try UIRenderSupport.prepare(view, size: size)

        let ambiguous = UIRenderSupport.ambiguousViews(in: view)
        guard ambiguous.isEmpty else {
            fatalError("Ambiguous layout in \(ambiguous.count) practice views at \(Int(size.width))x\(Int(size.height))")
        }
        let clipped = UIRenderSupport.fullyClippedControls(in: view)
        guard clipped.isEmpty else {
            fatalError("Fully clipped practice controls at \(Int(size.width))x\(Int(size.height))")
        }

        let output = destination.appendingPathComponent(name)
        try UIRenderSupport.writePNG(of: view, size: size, to: output)
        print(output.path)
    }
}
