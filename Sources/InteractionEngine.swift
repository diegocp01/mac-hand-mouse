import Foundation
import CoreGraphics

struct InteractionSettings: Equatable {
    var mode: ClickMode = .pinch
    var allowClicks = true
    var pointerEnabled = true
    var pinchThreshold = 0.42
    var dwellSeconds = 0.65
    var allowScrolling = false
}

enum ClickPreference {
    static func restored(saved: Bool?, legacy: Bool?) -> Bool { saved ?? legacy ?? true }
}

enum InteractionBlock {
    case paused, permission, previewOnly, staleFrame, missingHand, invalidDisplay, acquiring, differentHand, cursorUnavailable
}

enum InteractionDestination { case system, practice }

struct InteractionStep {
    var location: CGPoint?
    var click = false
    var scrollY: Int32 = 0
    var blocked: InteractionBlock?
    var destination: InteractionDestination = .system

    // Simulation results are never eligible for the OS event dispatch path.
    var systemLocation: CGPoint? { destination == .system ? location : nil }
    var systemClick: Bool { destination == .system && click }
    var systemScrollY: Int32 { destination == .system ? scrollY : 0 }
}

/// The actual camera-to-pointer path. No UI, camera, or CGEvent side effects,
/// so integration tests exercise the same ordering used by the running app.
struct InteractionEngine {
    private(set) var settings = InteractionSettings()
    private(set) var pinch = PinchDetector()
    private(set) var forward = ForwardClickDetector()
    private var forwardReference = AutomaticForwardReference()
    var forwardProfile: ForwardProfile? { forwardReference.profile }
    private(set) var acquisition = PointerAcquisition()
    private(set) var scroll = ScrollDetector()
    private var filter = PointerFilter()
    private var lastTimestamp: Double?
    private var lastDestination: InteractionDestination?
    private var lastLocation: CGPoint?
    private var lastBounds: CGRect?

    mutating func configure(_ newSettings: InteractionSettings) {
        guard settings != newSettings else { return }
        settings = newSettings
        pinch.settings.closeRatio = newSettings.pinchThreshold
        forward.holdSeconds = newSettings.dwellSeconds
        reset()
    }

    mutating func reset() {
        pinch.reset(); forward.reset(); forwardReference.reset(); filter.reset()
        lastTimestamp = nil
        lastDestination = nil
        acquisition.reset(); scroll.reset(); lastLocation = nil; lastBounds = nil
    }

    /// Stops an in-progress gesture when delivery stalls, retaining post-click rearm rules.
    mutating func trackingInterrupted() {
        pinch.reset(); forward.reset(); forwardReference.reset(); scroll.reset(); filter.reset()
        acquisition.interrupt(); lastLocation = nil
    }

    mutating func process(index: CGPoint?, pinchRatio: Double?, forwardPose: ForwardPose? = nil, timestamp: Double, now: Double,
                          bounds: CGRect, running: Bool, trusted: Bool,
                          destination: InteractionDestination = .system, cursorPosition: CGPoint? = nil,
                          handSide: String? = nil, scrollPoint: CGPoint? = nil) -> InteractionStep {
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
        if lastBounds != nil && lastBounds != bounds { trackingInterrupted() }
        lastBounds = bounds
        if let previous = lastTimestamp, timestamp - previous > GestureTuning.trackingGraceSeconds + 1e-9 { trackingInterrupted() }
        lastTimestamp = timestamp
        guard let index, index.x.isFinite, index.y.isFinite else {
            trackingInterrupted()
            return InteractionStep(blocked: .missingHand)
        }
        guard let cursorPosition, cursorPosition.x.isFinite, cursorPosition.y.isFinite,
              bounds.contains(cursorPosition) else {
            trackingInterrupted(); return InteractionStep(blocked: .cursorUnavailable)
        }
        if let owner = acquisition.owner, owner != handSide {
            trackingInterrupted(); return InteractionStep(blocked: .differentHand)
        }
        if let lastLocation, hypot(cursorPosition.x - lastLocation.x, cursorPosition.y - lastLocation.y) > 12 {
            trackingInterrupted()
        }
        if settings.mode == .forward {
            let canAdapt = (forward.phase == .needsNeutral || forward.phase == .ready) && scrollPoint == nil
            if forwardReference.update(forwardPose, time: timestamp, canAdapt: canAdapt) { forward.reset() }
        }
        let wasActive = acquisition.active
        let neutral: Bool
        if settings.mode == .forward {
            if let profile = forwardProfile, let pose = forwardPose, let position = profile.position(of: pose) {
                neutral = position.amount > -0.4 && position.amount < 0.25 && position.scaleDeviation < 0.5
            } else { neutral = false }
        } else { neutral = pinchRatio.map { $0.isFinite && $0 > settings.pinchThreshold + 0.18 } ?? false }
        guard acquisition.update(point: index, cursor: cursorPosition, side: handSide, neutral: neutral && scrollPoint == nil, time: timestamp) else {
            pinch.reset(); forward.reset(); scroll.reset()
            return InteractionStep(blocked: .acquiring)
        }
        if !wasActive {
            filter.reanchor(point: index, cursor: cursorPosition, bounds: bounds, time: timestamp)
            lastLocation = cursorPosition
            return InteractionStep(location: cursorPosition, destination: destination)
        }
        if settings.allowScrolling && scrollPoint != nil {
            pinch.reset(); forward.reset()
            let delta = scroll.update(point: scrollPoint, time: timestamp)
            if scroll.phase == .idle {
                trackingInterrupted()
                return InteractionStep(blocked: .acquiring)
            }
            let location = filter.update(point: index, bounds: bounds, time: timestamp, freeze: true)
            lastLocation = location
            return InteractionStep(location: location, scrollY: delta, destination: destination)
        } else if scroll.phase != .idle {
            trackingInterrupted()
            return InteractionStep(blocked: .acquiring)
        }
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
        lastLocation = location
        return InteractionStep(location: location,
                               click: SafetyPolicy.shouldInjectClick(gestureFired: fired,
                                   allowClicks: settings.allowClicks, axTrusted: inputAllowed,
                                   pointerControlEnabled: settings.pointerEnabled),
                               destination: destination)
    }
}
