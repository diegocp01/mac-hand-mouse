import AppKit

enum UIRenderError: Error, CustomStringConvertible {
    case invalidSize(NSSize)
    case bitmapUnavailable
    case pngUnavailable

    var description: String {
        switch self {
        case .invalidSize(let size):
            return "Invalid snapshot size \(size.width)x\(size.height)"
        case .bitmapUnavailable:
            return "AppKit could not allocate a bitmap for the view"
        case .pngUnavailable:
            return "AppKit could not encode the rendered view as PNG"
        }
    }
}

/// Camera-free AppKit snapshot support for visual review of the real production views.
/// The caller is responsible for constructing the view in a deliberately inert state.
enum UIRenderSupport {
    static func prepare(_ view: NSView, size: NSSize) throws {
        guard size.width > 0, size.height > 0,
              size.width.isFinite, size.height.isFinite else {
            throw UIRenderError.invalidSize(size)
        }

        view.frame = NSRect(origin: .zero, size: size)
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
    }

    static func writePNG(of view: NSView, size: NSSize, to destination: URL) throws {
        try prepare(view, size: size)

        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw UIRenderError.bitmapUnavailable
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw UIRenderError.pngUnavailable
        }
        try data.write(to: destination, options: .atomic)
    }

    static func descendants(of root: NSView) -> [NSView] {
        root.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    /// Reports controls whose visible frame has no intersection with their immediate
    /// container. It intentionally ignores partially clipped content inside scroll views.
    static func fullyClippedControls(in root: NSView) -> [NSControl] {
        descendants(of: root).compactMap { $0 as? NSControl }.filter { control in
            guard !control.isHidden, let parent = control.superview else { return false }
            if control.enclosingScrollView != nil { return false }
            return !parent.bounds.intersects(control.frame)
        }
    }

    static func ambiguousViews(in root: NSView) -> [NSView] {
        ([root] + descendants(of: root)).filter(\.hasAmbiguousLayout)
    }
}
