import Foundation
import CoreGraphics

/// What the status card and the cursor overlay should say for one gesture state.
struct FeedbackMessage {
    struct Ring {
        var progress: Double = 0
        var remaining: Double = 0
        var clicked = false
        var caption: String? = nil
    }
    var title: String
    var detail: String
    /// Status-card ring fill; nil hides that ring.
    var progress: Double? = nil
    /// Cursor overlay; nil hides it.
    var ring: Ring? = nil
}

/// Pure text for the live engine state. No views, so it is cheap to review and test.
enum GestureFeedback {
    typealias Ring = FeedbackMessage.Ring

    /// Hold-still clicking and the five-finger right click share the click slot.
    static func click(_ engine: InteractionEngine) -> FeedbackMessage {
        if engine.rightGestureActive {
            let held = engine.rightPinch.phase == .held
            let confirming = engine.rightPinch.phase == .confirming
            return FeedbackMessage(
                title: held ? "Open your hand" : (confirming ? "Hold five tips together" : "Open your hand to prepare"),
                detail: held ? "One right-click was completed. Open your hand to move."
                    : (confirming ? "Keep all five fingertips together and visible. Hold briefly to right-click once."
                        : "Open your hand with all five fingertips visible, then bring the fingertips together to right-click."),
                ring: Ring(caption: held ? "Open your hand" : "Five tips together"))
        }
        switch engine.clickPhase {
        case .ready:
            return FeedbackMessage(title: "Hold still to click",
                                   detail: "Point at a target and stop moving. The ring fills and clicks once.")
        case .holding:
            let remaining = engine.clickRemainingSeconds
            return FeedbackMessage(title: String(format: "Click in %.1f s", max(0.1, remaining)),
                detail: "Keep still. Move away to cancel. One click when the ring fills.",
                progress: engine.clickProgress,
                ring: Ring(progress: engine.clickProgress, remaining: remaining))
        case .clicked:
            return FeedbackMessage(title: "Clicked ✓", detail: "Move away to aim at the next target.",
                                   ring: Ring(progress: 1, caption: "Move to click again"))
        }
    }

    /// Shown briefly after a click was actually sent.
    static func clicked(right: Bool) -> FeedbackMessage {
        FeedbackMessage(title: right ? "Right clicked ✓" : "Clicked ✓",
            detail: right ? "Open your hand, then point with your index to move." : "Move away to aim at the next target.",
            ring: Ring(progress: 1, clicked: true, caption: right ? "Right clicked ✓" : nil))
    }

    static func scroll(_ engine: InteractionEngine) -> FeedbackMessage {
        let active = engine.scroll.phase == .scrolling
        return FeedbackMessage(title: active ? "Scrolling ↑↓" : "Hold pinch briefly",
            detail: "Keep thumb + index + middle pinched together and move your hand up/down. Release to resume aiming.",
            ring: Ring(caption: active ? "Scrolling ↑↓" : "Pinch…"))
    }

    static func drag(_ engine: InteractionEngine, dragging: Bool, primaryL: Bool, clicksAllowed: Bool) -> FeedbackMessage {
        let phase = engine.drag.phase
        let title = phase == .needsRelease ? "Open either hand to reset dragging"
            : (dragging ? "Dragging / selecting" : (phase == .confirming ? "Hold both L poses briefly"
                : (!primaryL ? "Make an L with your pointer hand" : "Make an L with your second hand")))
        let detail = phase == .needsRelease
            ? "Open either hand briefly, then form both L poses again."
            : "Make an L with each thumb + index; fold the other fingers. Move your original hand to drag. Open either hand to release."
        let confirming = phase == .confirming
        let caption = !clicksAllowed ? "Dragging off" : (phase == .needsRelease ? "Open hand to reset"
            : (dragging ? "Dragging" : (confirming ? "Starting drag" : "Both hands: L")))
        return FeedbackMessage(title: clicksAllowed ? title : "Dragging off",
            detail: clicksAllowed ? detail : "Enable Allow clicks to use two-hand dragging.",
            ring: Ring(progress: confirming ? engine.drag.progress : 0,
                       remaining: confirming ? 0.25 * (1 - engine.drag.progress) : 0, caption: caption))
    }
}
