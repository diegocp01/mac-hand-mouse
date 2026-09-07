import AppKit

@main
enum GestureGuideSnapshot {
    static func main() throws {
        _ = NSApplication.shared
        let destination = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/private/tmp")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        try render(
            name: "gesture-guide-default.png",
            size: NSSize(width: 900, height: 370),
            selected: .click,
            active: .move,
            scrollingEnabled: true,
            selectionEnabled: true,
            destination: destination
        )
        try render(
            name: "gesture-guide-narrow.png",
            size: NSSize(width: 620, height: 350),
            selected: .scroll,
            active: .scroll,
            scrollingEnabled: true,
            selectionEnabled: false,
            destination: destination
        )
    }

    private static func render(name: String, size: NSSize, selected: GestureAction,
                               active: GestureAction?, scrollingEnabled: Bool,
                               selectionEnabled: Bool, destination: URL) throws {
        let guide = GestureGuideView(frame: NSRect(origin: .zero, size: size))
        guide.appearance = NSAppearance(named: .darkAqua)
        guide.select(selected)
        guide.update(active: active, scrollingEnabled: scrollingEnabled,
                     selectionEnabled: selectionEnabled)

        try UIRenderSupport.prepare(guide, size: size)
        let ambiguous = UIRenderSupport.ambiguousViews(in: guide)
        guard ambiguous.isEmpty else {
            fatalError("Ambiguous layout in \(ambiguous.count) gesture-guide views at \(Int(size.width))x\(Int(size.height))")
        }
        let clipped = UIRenderSupport.fullyClippedControls(in: guide)
        guard clipped.isEmpty else {
            fatalError("Fully clipped gesture controls at \(Int(size.width))x\(Int(size.height))")
        }

        let output = destination.appendingPathComponent(name)
        try UIRenderSupport.writePNG(of: guide, size: size, to: output)
        print(output.path)
    }
}
