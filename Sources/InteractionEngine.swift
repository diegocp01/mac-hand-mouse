import Foundation
import CoreGraphics

struct InteractionSettings: Equatable {
    var mode: ClickMode = .pinch
    var allowClicks = false
    var pointerEnabled = true
    var pinchThreshold = 0.42
    var dwellSeconds = 0.65
}

enum InteractionBlock {
    case paused, permission, previewOnly, staleFrame, missingHand, invalidDisplay
}

struct InteractionStep {
    var location: CGPoint?
    var click = false
    var restartedDwell = false
    var blocked: InteractionBlock?
}

/// The actual camera-to-pointer path. No UI, camera, or CGEvent side effects,
/// so integration tests exercise the same ordering used by the running app.
struct InteractionEngine {
    private(set) var settings = InteractionSettings()
    private(set) var pinch = PinchDetector()
    private(set) var dwell = DwellDetector()
    private var filter = PointerFilter()
    private var lastTimestamp: Double?
    private var lastHand: Double?

    mutating func configure(_ newSettings: InteractionSettings) {
        guard settings != newSettings else { return }
        settings = newSettings
        pinch.settings.closeRatio = newSettings.pinchThreshold
        dwell.settings.dwellSeconds = newSettings.dwellSeconds
        reset()
    }

    mutating func reset() {
        pinch.reset(); dwell.reset(); filter.reset()
        lastTimestamp = nil; lastHand = nil
    }

    /// Stops an in-progress gesture when delivery stalls, retaining post-click rearm rules.
    mutating func trackingInterrupted() {
        pinch.reset(); dwell.trackingLost(); filter.reset(); lastHand = nil
    }

    mutating func process(index: CGPoint?, pinchRatio: Double?, timestamp: Double, now: Double,
                          bounds: CGRect, running: Bool, trusted: Bool) -> InteractionStep {
        guard running else { reset(); return InteractionStep(blocked: .paused) }
        guard trusted else { reset(); return InteractionStep(blocked: .permission) }
        guard settings.pointerEnabled else { reset(); return InteractionStep(blocked: .previewOnly) }
        guard timestamp.isFinite, now.isFinite, timestamp <= now, now - timestamp < 0.20,
              lastTimestamp.map({ timestamp > $0 }) ?? true else {
            trackingInterrupted(); return InteractionStep(blocked: .staleFrame)
        }
        guard bounds.origin.x.isFinite, bounds.origin.y.isFinite,
              bounds.width.isFinite, bounds.height.isFinite, bounds.width > 1, bounds.height > 1,
              bounds.maxX.isFinite, bounds.maxY.isFinite else {
            reset(); return InteractionStep(blocked: .invalidDisplay)
        }
        lastTimestamp = timestamp
        guard let index, index.x.isFinite, index.y.isFinite else {
            _ = pinch.update(ratio: nil, time: timestamp)
            _ = dwell.update(point: .zero, time: timestamp, tracking: false)
            if lastHand.map({ timestamp - $0 > GestureTuning.trackingGraceSeconds }) ?? true { filter.reset() }
            return InteractionStep(blocked: .missingHand)
        }
        lastHand = timestamp
        let sample = filter.unfrozenTarget(point: index, bounds: bounds)
        let fired: Bool
        let wasArming = dwell.phase == .arming
        if !settings.allowClicks {
            pinch.reset(); dwell.reset(); fired = false
        } else if settings.mode == .dwell {
            fired = dwell.update(point: sample, time: timestamp, tracking: true)
        } else {
            fired = pinch.update(ratio: pinchRatio, time: timestamp)
        }
        let freeze = settings.allowClicks && (settings.mode == .dwell ? dwell.shouldFreeze : pinch.shouldFreeze)
        let location = filter.update(point: index, bounds: bounds, time: timestamp, freeze: freeze)
        return InteractionStep(location: location,
                               click: SafetyPolicy.shouldInjectClick(gestureFired: fired,
                                   allowClicks: settings.allowClicks, axTrusted: trusted,
                                   pointerControlEnabled: settings.pointerEnabled),
                               restartedDwell: settings.mode == .dwell && wasArming && dwell.phase == .idle)
    }
}
