import Foundation
import CoreGraphics

enum PracticeTask: String, CaseIterable {
    case click
    case scroll
    case select
}

/// Deterministic practice state expressed in a normalized, top-left-origin canvas.
/// It consumes simulation output only and has no AppKit or system-event dependency.
struct PracticeTaskState {
    static let clickTarget = CGRect(x: 0.62, y: 0.28, width: 0.22, height: 0.18)
    static let listViewport = CGRect(x: 0.16, y: 0.15, width: 0.68, height: 0.68)
    static let listTargetRow = CGRect(x: 0.20, y: 0.96, width: 0.60, height: 0.12)
    static let sentenceTarget = CGRect(x: 0.14, y: 0.40, width: 0.72, height: 0.18)
    static let maxScrollOffset: CGFloat = 0.35

    private static let scrollPointsPerCanvas: CGFloat = 700
    private static let selectionEdgeInset: CGFloat = 0.10

    private(set) var task: PracticeTask
    private(set) var completed = false
    private(set) var scrollOffset: CGFloat = 0
    private(set) var selectionStart: CGPoint?
    private(set) var selectionEnd: CGPoint?

    private var clickReady = false
    private var scrollReady = false
    private var selecting = false
    private var dragBlockedUntilRelease = true

    init(task: PracticeTask = .click) {
        self.task = task
    }

    var visibleListTargetRow: CGRect {
        Self.listTargetRow.offsetBy(dx: 0, dy: -scrollOffset)
    }

    mutating func reset(task: PracticeTask) {
        self.task = task
        completed = false
        scrollOffset = 0
        selectionStart = nil
        selectionEnd = nil
        clickReady = false
        scrollReady = false
        selecting = false
        dragBlockedUntilRelease = true
    }

    /// Returns true only on the update that completes the current task.
    @discardableResult
    mutating func update(point: CGPoint?, clicked: Bool, scrollY: Int32,
                         dragging: Bool, interrupted: Bool = false) -> Bool {
        let validPoint = point.flatMap { Self.validated($0) }

        if interrupted || (point != nil && validPoint == nil) {
            if completed {
                selecting = false
                dragBlockedUntilRelease = true
            } else {
                cancelSelectionForInterruption()
            }
            clickReady = false
            scrollReady = false
            return false
        }

        // Each task reset and interruption requires neutral input before a new
        // gesture can count, so held output cannot carry into another attempt.
        if !clicked { clickReady = true }
        if scrollY == 0 { scrollReady = true }
        if dragBlockedUntilRelease {
            if !dragging { dragBlockedUntilRelease = false }
            return false
        }

        guard !completed else { return false }

        switch task {
        case .click:
            guard clickReady, clicked else { return false }
            clickReady = false
            guard scrollY == 0, !dragging else { return false }
            guard let validPoint, Self.clickTarget.contains(validPoint) else { return false }
            completed = true
            return true

        case .scroll:
            guard scrollReady, scrollY != 0 else { return false }
            guard !clicked, !dragging else {
                scrollReady = false
                return false
            }
            // Match production/AppKit scrolling: negative wheel deltas move the
            // list upward and reveal content farther down.
            let movement = -CGFloat(scrollY) / Self.scrollPointsPerCanvas
            scrollOffset = min(Self.maxScrollOffset, max(0, scrollOffset + movement))
            let row = visibleListTargetRow
            if row.minY >= Self.listViewport.minY && row.maxY <= Self.listViewport.maxY {
                completed = true
                return true
            }
            return false

        case .select:
            guard !clicked, scrollY == 0 else {
                if selecting { cancelSelectionForInterruption() }
                return false
            }
            return updateSelection(point: validPoint, dragging: dragging)
        }
    }

    private mutating func updateSelection(point: CGPoint?, dragging: Bool) -> Bool {
        if dragging {
            guard let point else {
                cancelSelectionForInterruption()
                return false
            }
            if !selecting {
                guard Self.sentenceTarget.contains(point) else {
                    dragBlockedUntilRelease = true
                    return false
                }
                selecting = true
                selectionStart = point
            }
            selectionEnd = point
            return false
        }

        guard selecting else {
            selecting = false
            return false
        }
        guard let point, let start = selectionStart else {
            cancelSelectionForInterruption()
            return false
        }
        selectionEnd = point
        let end = point
        selecting = false

        let target = Self.sentenceTarget
        let staysOnLine = target.contains(start) && target.contains(end)
        let coversLeftEdge = min(start.x, end.x) <= target.minX + Self.selectionEdgeInset
        let coversRightEdge = max(start.x, end.x) >= target.maxX - Self.selectionEdgeInset
        guard staysOnLine, coversLeftEdge, coversRightEdge else {
            selectionStart = nil
            selectionEnd = nil
            return false
        }
        completed = true
        return true
    }

    private mutating func cancelSelectionForInterruption() {
        selecting = false
        selectionStart = nil
        selectionEnd = nil
        dragBlockedUntilRelease = true
    }

    private static func validated(_ point: CGPoint) -> CGPoint? {
        guard point.x.isFinite, point.y.isFinite,
              (0...1).contains(point.x), (0...1).contains(point.y) else { return nil }
        return point
    }
}
