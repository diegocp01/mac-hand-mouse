import AppKit

@main
enum GestureGuideSnapshot {
    static func main() throws {
        _ = NSApplication.shared
        let destination = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/private/tmp")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        try render(
            name: "gesture-guide-click-hold.png",
            size: NSSize(width: 900, height: 360),
            selected: .click,
            active: .move,
            scrollingEnabled: true,
            selectionEnabled: true,
            demoTime: 1.72,
            destination: destination
        )
        try render(
            name: "gesture-guide-click-complete.png",
            size: NSSize(width: 900, height: 360),
            selected: .click,
            active: .move,
            scrollingEnabled: true,
            selectionEnabled: true,
            demoTime: 2.60,
            destination: destination
        )
        try render(
            name: "gesture-guide-scroll.png",
            size: NSSize(width: 900, height: 360),
            selected: .scroll,
            active: .scroll,
            scrollingEnabled: true,
            selectionEnabled: false,
            demoTime: 2.60,
            destination: destination
        )
        try render(
            name: "gesture-guide-select-narrow.png",
            size: NSSize(width: 620, height: 350),
            selected: .select,
            active: nil,
            scrollingEnabled: false,
            selectionEnabled: false,
            demoTime: 2.70,
            destination: destination
        )
        try render(
            name: "gesture-guide-reduce-motion.png",
            size: NSSize(width: 620, height: 350),
            selected: .click,
            active: nil,
            scrollingEnabled: false,
            selectionEnabled: false,
            demoTime: 0,
            reduceMotion: true,
            destination: destination
        )
    }

    private static func render(name: String, size: NSSize, selected: GestureAction,
                               active: GestureAction?, scrollingEnabled: Bool,
                               selectionEnabled: Bool, demoTime: TimeInterval,
                               reduceMotion: Bool = false,
                               destination: URL) throws {
        let guide = GestureGuideView(frame: NSRect(origin: .zero, size: size))
        guide.appearance = NSAppearance(named: .darkAqua)
        guide.select(selected)
        guide.update(active: active, scrollingEnabled: scrollingEnabled,
                     selectionEnabled: selectionEnabled)
        guide.setDemoTimeForRendering(demoTime)
        guide.setReduceMotionForRendering(reduceMotion)

        try UIRenderSupport.prepare(guide, size: size)
        let ambiguous = UIRenderSupport.ambiguousViews(in: guide)
        guard ambiguous.isEmpty else {
            fatalError("Ambiguous layout in \(ambiguous.count) gesture-guide views at \(Int(size.width))x\(Int(size.height))")
        }
        let clipped = UIRenderSupport.fullyClippedControls(in: guide)
        guard clipped.isEmpty else {
            let details = clipped.map { "\(type(of: $0)) frame=\($0.frame) parent=\($0.superview?.bounds ?? .zero)" }.joined(separator: "; ")
            fatalError("Fully clipped gesture controls at \(Int(size.width))x\(Int(size.height)): \(details)")
        }

        let output = destination.appendingPathComponent(name)
        try UIRenderSupport.writePNG(of: guide, size: size, to: output)
        print(output.path)
    }
}
