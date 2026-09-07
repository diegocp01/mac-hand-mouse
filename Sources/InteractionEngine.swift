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

enum InteractionDestination { case system, practice }

struct InteractionStep {
    var location: CGPoint?
    var click = false
    var blocked: InteractionBlock?
    var destination: InteractionDestination = .system

    // Simulation results are never eligible for the OS event dispatch path.
    var systemLocation: CGPoint? { destination == .system ? location : nil }
    var systemClick: Bool { destination == .system && click }
}

/// The actual camera-to-pointer path. No UI, camera, or CGEvent side effects,
/// so integration tests exercise the same ordering used by the running app.
struct InteractionEngine {
    private(set) var settings = InteractionSettings()
    private(set) var pinch = PinchDetector()
    private(set) var forward = ForwardClickDetector()
    private(set) var forwardProfile: ForwardProfile?
    private var filter = PointerFilter()
    private var lastTimestamp: Double?
    private var lastHand: Double?
    private var lastDestination: InteractionDestination?

    mutating func configure(_ newSettings: InteractionSettings) {
        guard settings != newSettings else { return }
        settings = newSettings
        pinch.settings.closeRatio = newSettings.pinchThreshold
        forward.holdSeconds = newSettings.dwellSeconds
        reset()
    }

    mutating func reset() {
        pinch.reset(); forward.reset(); filter.reset()
        lastTimestamp = nil; lastHand = nil
        lastDestination = nil
    }

    /// Stops an in-progress gesture when delivery stalls, retaining post-click rearm rules.
    mutating func trackingInterrupted() {
        pinch.reset(); forward.reset(); filter.reset(); lastHand = nil
    }

    mutating func setForwardProfile(_ profile: ForwardProfile?) {
        forwardProfile = profile
        reset()
    }

    mutating func process(index: CGPoint?, pinchRatio: Double?, forwardPose: ForwardPose? = nil, timestamp: Double, now: Double,
                          bounds: CGRect, running: Bool, trusted: Bool,
                          destination: InteractionDestination = .system) -> InteractionStep {
        guard running else { reset(); return InteractionStep(blocked: .paused) }
        let inputAllowed = trusted || destination == .practice
        guard inputAllowed else { reset(); return InteractionStep(blocked: .permission) }
        guard settings.pointerEnabled else { reset(); return InteractionStep(blocked: .previewOnly) }
        if lastDestination != destination { reset(); lastDestination = destination }
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
            forward.reset()
            if lastHand.map({ timestamp - $0 > GestureTuning.trackingGraceSeconds }) ?? true { filter.reset() }
            return InteractionStep(blocked: .missingHand)
        }
        lastHand = timestamp
        let fired: Bool
        if !settings.allowClicks {
            pinch.reset(); forward.reset(); fired = false
        } else if settings.mode == .forward {
            fired = forward.update(forwardPose, profile: forwardProfile, time: timestamp, bounds: bounds)
        } else {
            fired = pinch.update(ratio: pinchRatio, time: timestamp)
        }
        let freeze = settings.allowClicks && (settings.mode == .forward ? forward.shouldFreeze : pinch.shouldFreeze)
        let location = filter.update(point: index, bounds: bounds, time: timestamp, freeze: freeze)
        return InteractionStep(location: location,
                               click: SafetyPolicy.shouldInjectClick(gestureFired: fired,
                                   allowClicks: settings.allowClicks, axTrusted: inputAllowed,
                                   pointerControlEnabled: settings.pointerEnabled),
                               destination: destination)
    }
}
