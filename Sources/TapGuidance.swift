/// The same next action appears in practice, the setup guide, and beside the cursor.
/// In particular, lifting is only offered once the detector can actually click.
struct TapGuidance {
    enum Action { case raise, aim, bend, lift }
    let action: Action
    let title: String
    let detail: String
    let caption: String?

    init(tap: TwoFingerTapDetector, locked: Bool) {
        switch tap.phase {
        case .waiting:
            action = .raise
            switch tap.cancellation {
            case .timedOut:
                title = "Let's try again"
                detail = "No click sent. Raise index + middle, then bend and lift in one motion."
            case .incompleteBend:
                title = "Raise both fingers to retry"
                detail = "No click sent. On your next tap, bend index + middle a little more."
            case .trackingLost:
                title = "Show both fingers"
                detail = "No click sent. Raise index + middle with your palm toward the camera."
            case nil:
                title = "Raise index + middle"
                detail = "Keep your palm toward the camera. Hold briefly to get ready."
            }
            caption = tap.cancellation != nil || locked ? "Raise both fingers" : nil
        case .ready:
            action = locked ? .bend : .aim
            title = locked ? "Bend to click here" : "Aim at your target"
            detail = locked
                ? "Pointer locked. Bend index + middle together. Separate them to move."
                : "Move your index finger. When you're on target, bend index + middle together."
            caption = locked ? "Bend to click" : nil
        case .pressed:
            action = tap.canReleaseToClick ? .lift : .bend
            title = tap.canReleaseToClick ? "Lift to click" : "Bend both fingers"
            detail = tap.canReleaseToClick
                ? "Lift index + middle together. Your pointer stays on the target."
                : "Bend index + middle a little more. Your pointer stays on the target."
            caption = title
        }
    }
}
