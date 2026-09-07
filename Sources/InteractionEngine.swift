import Foundation
import CoreGraphics

struct InteractionSettings: Equatable {
    var mode: ClickMode = .pinch
    var allowClicks = true
    var pointerEnabled = true
    var pinchThreshold = 0.42
    var dwellSeconds = 0.65
    var allowScrolling = false
    var allowDragging = false
    var allowPinchDragging = false
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
    var dragging = false
    var buttonHeld = false

    // Simulation results are never eligible for the OS event dispatch path.
    var systemLocation: CGPoint? { destination == .system ? location : nil }
    var systemClick: Bool { destination == .system && click }
    var systemScrollY: Int32 { destination == .system ? scrollY : 0 }
    var systemButtonHeld: Bool { destination == .system && (buttonHeld || dragging) }
    var systemDragging: Bool { destination == .system && dragging }
}

/// The actual camera-to-pointer path. No UI, camera, or CGEvent side effects,
/// so integration tests exercise the same ordering used by the running app.
struct InteractionEngine {
    private(set) var settings = InteractionSettings()
    private(set) var pinch = PinchDetector()
    private(set) var tap = TwoFingerTapDetector()
    private(set) var forward = ForwardClickDetector()
    private var forwardReference = AutomaticForwardReference()
    var forwardProfile: ForwardProfile? { forwardReference.profile }
    private(set) var acquisition = PointerAcquisition()
    private(set) var scroll = ScrollDetector()
    private(set) var drag = TwoHandDragDetector()
    private(set) var pinchDrag = OneHandDragDetector()
    private var filter = PointerFilter()
    var pointerControlRegion: CGRect { filter.controlRegion }
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
        tap.reset()
        drag.interrupt(); pinchDrag.reset()
        pinch.reset(); forward.reset(); forwardReference.reset(); filter.reset()
        lastTimestamp = nil
        lastDestination = nil
        acquisition.reset(); scroll.reset(); lastLocation = nil; lastBounds = nil
    }

    /// Stops an in-progress gesture when delivery stalls, retaining post-click rearm rules.
    mutating func trackingInterrupted() {
        tap.reset()
        drag.interrupt(); pinchDrag.reset()
        pinch.reset(); forward.reset(); forwardReference.reset(); scroll.reset(); filter.reset()
        acquisition.interrupt(); lastLocation = nil
    }

    mutating func process(index: CGPoint?, pinchRatio: Double?, forwardPose: ForwardPose? = nil, timestamp: Double, now: Double,
                          bounds: CGRect, running: Bool, trusted: Bool,
                          destination: InteractionDestination = .system, cursorPosition: CGPoint? = nil,
                          handSide: String? = nil, scrollPoint: CGPoint? = nil,
                          primaryL: Bool = false, companionPresent: Bool = false, companionL: Bool = false,
                          primaryReleased: Bool = false, companionReleased: Bool = false, palm: CGPoint? = nil,
                          tapPose: TapPose? = nil) -> InteractionStep {
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
        let scrollPoint = settings.mode == .twoFingerTap ? nil : scrollPoint
        if settings.mode == .forward {
            let canAdapt = (forward.phase == .needsNeutral || forward.phase == .ready) && scrollPoint == nil && !(settings.allowDragging && companionPresent)
            if forwardReference.update(forwardPose, time: timestamp, canAdapt: canAdapt) { forward.reset() }
        }
        let wasActive = acquisition.active
        let neutral: Bool
        if settings.mode == .twoFingerTap {
            neutral = tapPose == .raised
        } else if settings.mode == .forward {
            if let profile = forwardProfile, let pose = forwardPose, let position = profile.position(of: pose) {
                neutral = position.amount > -0.4 && position.amount < 0.25 && position.scaleDeviation < 0.5
            } else { neutral = false }
        } else { neutral = pinchRatio.map { $0.isFinite && $0 > settings.pinchThreshold + 0.18 } ?? false }
        guard acquisition.update(point: index, cursor: cursorPosition, side: handSide, neutral: neutral && scrollPoint == nil, time: timestamp) else {
            tap.reset()
            pinch.reset(); forward.reset(); scroll.reset(); drag.interrupt(); pinchDrag.reset()
            return InteractionStep(blocked: .acquiring)
        }
        if !wasActive {
            filter.reanchor(point: index, cursor: cursorPosition, bounds: bounds, time: timestamp)
            lastLocation = cursorPosition
            return InteractionStep(location: cursorPosition, destination: destination)
        }
        let oneHandDrag = settings.allowPinchDragging && settings.mode == .pinch
        if oneHandDrag && settings.allowClicks && scroll.phase == .idle && (!settings.allowScrolling || scrollPoint == nil || pinchDrag.engaged) {
            pinch.reset(); forward.reset(); drag.interrupt()
            let previous = pinchDrag.phase
            guard pinchDrag.update(ratio: pinchRatio, palm: palm, time: timestamp,
                                   bounds: bounds, threshold: settings.pinchThreshold), let palm else {
                trackingInterrupted(); return InteractionStep(blocked: .acquiring)
            }
            let beganDrag = previous != .dragging && pinchDrag.phase == .dragging
            let ended = (previous == .pressed || previous == .dragging) && !pinchDrag.held
            let canceled = previous == .confirming && !pinchDrag.engaged
            let motionPoint = pinchDrag.phase == .dragging ? palm : index
            if beganDrag || ended || canceled {
                // Switch landmarks without jumping, including release back to the index.
                filter.reanchor(point: motionPoint, cursor: cursorPosition, bounds: bounds, time: timestamp)
            }
            let location = filter.update(point: motionPoint, bounds: bounds, time: timestamp,
                freeze: pinchDrag.phase == .confirming || pinchDrag.phase == .pressed || beganDrag || ended || canceled)
            lastLocation = location
            return InteractionStep(location: location, click: pinchDrag.releasedClick && destination == .practice,
                destination: destination, dragging: pinchDrag.phase == .dragging, buttonHeld: pinchDrag.held)
        }
        // The second hand is a modifier only. Its appearance cancels single-hand
        // click/scroll intent, even before it forms an L. Only the owner's index moves.
        if settings.allowDragging && !oneHandDrag && (companionPresent || drag.phase != .idle) {
            tap.reset()
            pinch.reset(); forward.reset(); scroll.reset()
            let previous = drag.phase
            if settings.allowClicks {
                drag.update(bothL: primaryL && companionPresent && companionL,
                    visiblyReleased: primaryReleased || (companionPresent && companionReleased), time: timestamp)
            } else { drag.interrupt() }
            let began = previous != .dragging && drag.phase == .dragging
            let ended = previous == .dragging && drag.phase != .dragging
            if began {
                // Start at the aim held during confirmation; discard hand motion while arming.
                filter.reanchor(point: index, cursor: cursorPosition, bounds: bounds, time: timestamp)
            }
            let location = filter.update(point: index, bounds: bounds, time: timestamp,
                freeze: settings.allowClicks && (drag.phase == .confirming || began || ended))
            lastLocation = location
            return InteractionStep(location: location, destination: destination, dragging: drag.phase == .dragging)
        }
        if settings.allowScrolling && scrollPoint != nil {
            pinch.reset(); forward.reset(); pinchDrag.reset()
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
            tap.reset()
            pinch.reset(); forward.reset(); fired = false
        } else if settings.mode == .twoFingerTap {
            let wasPressed = tap.shouldFreeze
            fired = tap.update(tapPose, time: timestamp)
            // Finger flexion is not pointer travel. Reanchor on release/cancellation.
            if wasPressed && !tap.shouldFreeze {
                filter.reanchor(point: index, cursor: cursorPosition, bounds: bounds, time: timestamp)
            }
        } else if settings.mode == .forward {
            fired = forward.update(forwardPose, profile: forwardProfile, time: timestamp, bounds: bounds)
        } else {
            fired = pinch.update(ratio: pinchRatio, time: timestamp)
        }
        let freeze = settings.allowClicks && (settings.mode == .twoFingerTap ? tap.shouldFreeze || fired : (settings.mode == .forward ? forward.shouldFreeze : pinch.shouldFreeze))
        let location = filter.update(point: index, bounds: bounds, time: timestamp, freeze: freeze)
        lastLocation = location
        return InteractionStep(location: location,
                               click: SafetyPolicy.shouldInjectClick(gestureFired: fired,
                                   allowClicks: settings.allowClicks, axTrusted: inputAllowed,
                                   pointerControlEnabled: settings.pointerEnabled),
                               destination: destination)
    }
}
