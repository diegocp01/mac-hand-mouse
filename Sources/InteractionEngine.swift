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
    var precisionMode = false
    var steadyAim = true
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
    var rightClick = false
    var scrollY: Int32 = 0
    var blocked: InteractionBlock?
    var destination: InteractionDestination = .system
    var dragging = false
    var buttonHeld = false

    // Simulation results are never eligible for the OS event dispatch path.
    var systemLocation: CGPoint? { destination == .system ? location : nil }
    var systemClick: Bool { destination == .system && click }
    var systemRightClick: Bool { destination == .system && rightClick }
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
    private(set) var pointHold = PointHoldDetector()
    private(set) var rightPinch = FiveFingerPinchDetector()
    private(set) var rightGestureActive = false
    private var pointingFrozen = false
    private(set) var forward = ForwardClickDetector()
    private var forwardReference = AutomaticForwardReference()
    var forwardProfile: ForwardProfile? { forwardReference.profile }
    private(set) var acquisition = PointerAcquisition()
    private(set) var scroll = ScrollDetector()
    private(set) var drag = TwoHandDragDetector()
    private(set) var pinchDrag = OneHandDragDetector()
    private var filter = PointerFilter()
    private(set) var fingersTogether = false
    private(set) var dragModifierPresent = false
    private var scrollPinched = false
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
        tap.reset(); pointHold.reset(); rightPinch.reset()
        rightGestureActive = false; pointingFrozen = false
        dragModifierPresent = false
        fingersTogether = false
        scrollPinched = false
        drag.interrupt(); pinchDrag.reset()
        pinch.reset(); forward.reset(); forwardReference.reset(); filter.reset()
        lastTimestamp = nil
        lastDestination = nil
        acquisition.reset(); scroll.reset(); lastLocation = nil; lastBounds = nil
    }

    /// Stops an in-progress gesture when delivery stalls, retaining post-click rearm rules.
    mutating func trackingInterrupted() {
        tap.reset(); pointHold.reset(); rightPinch.reset()
        rightGestureActive = false; pointingFrozen = false
        dragModifierPresent = false
        fingersTogether = false
        scrollPinched = false
        drag.interrupt(); pinchDrag.reset()
        pinch.reset(); forward.reset(); forwardReference.reset(); scroll.reset(); filter.reset()
        acquisition.interrupt(); lastLocation = nil
    }

    mutating func process(index: CGPoint?, pinchRatio: Double?, forwardPose: ForwardPose? = nil, timestamp: Double, now: Double,
                          bounds: CGRect, running: Bool, trusted: Bool,
                          destination: InteractionDestination = .system, cursorPosition: CGPoint? = nil,
                          handSide: String? = nil, scrollPoint scrollPointInput: CGPoint? = nil,
                          primaryL: Bool = false, companionPresent: Bool = false, companionL: Bool = false,
                          primaryReleased: Bool = false, companionReleased: Bool = false, palm: CGPoint? = nil,
                          tapPose: TapPose? = nil, fingerSeparationRatio: Double? = nil, scrollPinchRatio: Double? = nil,
                          pointingPose: PointingPose? = nil, fiveFingerPinchRatio: Double? = nil,
                          threeFingerPinchRatio: Double? = nil) -> InteractionStep {
        dragModifierPresent = false
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
        let scrollPoint: CGPoint?
        if settings.mode == .twoFingerTap || settings.mode == .pointAndHold {
            let scrollRatio = settings.mode == .pointAndHold ? threeFingerPinchRatio : scrollPinchRatio
            if settings.allowScrolling, let ratio = scrollRatio, ratio.isFinite, ratio >= 0, let palm,
               palm.x.isFinite, palm.y.isFinite {
                if ratio < settings.pinchThreshold { scrollPinched = true }
                else if ratio > settings.pinchThreshold + 0.18 { scrollPinched = false }
                scrollPoint = scrollPinched ? palm : nil
            } else { scrollPinched = false; scrollPoint = nil }
        } else { scrollPoint = scrollPointInput }
        if settings.mode == .forward {
            let canAdapt = (forward.phase == .needsNeutral || forward.phase == .ready) && scrollPoint == nil && !(settings.allowDragging && companionPresent)
            if forwardReference.update(forwardPose, time: timestamp, canAdapt: canAdapt) { forward.reset() }
        }
        let wasActive = acquisition.active
        let neutral: Bool
        if settings.mode == .pointAndHold {
            neutral = pointingPose == .move && (fiveFingerPinchRatio.map { $0.isFinite && $0 > 0.85 } ?? true)
        } else if settings.mode == .twoFingerTap {
            neutral = tapPose == .raised
        } else if settings.mode == .forward {
            if let profile = forwardProfile, let pose = forwardPose, let position = profile.position(of: pose) {
                neutral = position.amount > -0.4 && position.amount < 0.25 && position.scaleDeviation < 0.5
            } else { neutral = false }
        } else { neutral = pinchRatio.map { $0.isFinite && $0 > settings.pinchThreshold + 0.18 } ?? false }
        guard acquisition.update(point: index, cursor: cursorPosition, side: handSide, neutral: neutral && scrollPoint == nil, time: timestamp) else {
            tap.reset(); pointHold.reset(); rightPinch.reset(); rightGestureActive = false; pointingFrozen = false
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
            let location = filter.update(point: motionPoint, bounds: bounds, time: timestamp, precision: settings.precisionMode,
                freeze: pinchDrag.phase == .confirming || pinchDrag.phase == .pressed || beganDrag || ended || canceled)
            lastLocation = location
            return InteractionStep(location: location, click: pinchDrag.releasedClick && destination == .practice,
                destination: destination, dragging: pinchDrag.phase == .dragging, buttonHeld: pinchDrag.held)
        }
        // The second hand is a modifier only. Its appearance cancels single-hand
        // click/scroll intent, even before it forms an L. Only the owner's index moves.
        if settings.allowDragging && !oneHandDrag && (companionPresent || drag.phase != .idle) {
            dragModifierPresent = companionPresent
            tap.reset(); pointHold.reset(); rightPinch.reset(); rightGestureActive = false; pointingFrozen = false
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
            let location = filter.update(point: index, bounds: bounds, time: timestamp, precision: settings.precisionMode,
                steadyAim: (settings.mode == .twoFingerTap || settings.mode == .pointAndHold) && settings.steadyAim && drag.phase != .dragging,
                freeze: settings.allowClicks && (drag.phase == .confirming || began || ended))
            lastLocation = location
            return InteractionStep(location: location, destination: destination, dragging: drag.phase == .dragging)
        }
        if settings.mode == .pointAndHold {
            let rightFired: Bool
            if settings.allowClicks {
                rightFired = rightPinch.update(ratio: fiveFingerPinchRatio, time: timestamp)
            } else { rightPinch.reset(); rightFired = false }
            let wasRightGesture = rightGestureActive
            if let ratio = fiveFingerPinchRatio, ratio.isFinite, ratio >= 0 {
                if ratio < 0.75 { rightGestureActive = true }
                else if ratio > 0.85 { rightGestureActive = false }
            }
            // All-five closure wins over its embedded thumb/index/middle scroll pinch.
            // A lost fingertip observation cannot turn a held right click into a scroll.
            if rightGestureActive || wasRightGesture {
                pointHold.reset(); scroll.reset(); scrollPinched = false
                pointingFrozen = true
                if !rightGestureActive {
                    filter.reanchor(point: index, cursor: cursorPosition, bounds: bounds, time: timestamp)
                }
                let location = filter.update(point: index, bounds: bounds, time: timestamp,
                    precision: settings.precisionMode, steadyAim: settings.steadyAim, freeze: true)
                lastLocation = location
                return InteractionStep(location: location,
                    rightClick: SafetyPolicy.shouldInjectClick(gestureFired: rightFired,
                        allowClicks: settings.allowClicks, axTrusted: inputAllowed,
                        pointerControlEnabled: settings.pointerEnabled), destination: destination)
            }
        }
        if settings.allowScrolling && scrollPoint != nil {
            tap.reset(); pointHold.reset(); fingersTogether = false
            pointingFrozen = true
            pinch.reset(); forward.reset(); pinchDrag.reset()
            let delta = scroll.update(point: scrollPoint, time: timestamp)
            if scroll.phase == .idle {
                trackingInterrupted()
                return InteractionStep(blocked: .acquiring)
            }
            let location = filter.update(point: index, bounds: bounds, time: timestamp, precision: settings.precisionMode, freeze: true)
            lastLocation = location
            return InteractionStep(location: location, scrollY: delta, destination: destination)
        } else if scroll.phase != .idle {
            if settings.mode == .twoFingerTap || settings.mode == .pointAndHold {
                scroll.reset(); tap.reset(); pointHold.reset(); fingersTogether = false
                filter.reanchor(point: index, cursor: cursorPosition, bounds: bounds, time: timestamp)
                lastLocation = cursorPosition
                return InteractionStep(location: cursorPosition, destination: destination)
            }
            trackingInterrupted()
            return InteractionStep(blocked: .acquiring)
        }
        if settings.mode == .pointAndHold {
            let fired: Bool
            if settings.allowClicks {
                fired = pointHold.update(pose: pointingPose, point: index, time: timestamp)
            } else { pointHold.reset(); fired = false }
            // Only the one-index pose moves. Raising the middle finger holds the
            // target still; unclear poses cancel the countdown without moving it.
            let freeze = pointingPose != .move
            if pointingFrozen && !freeze {
                filter.reanchor(point: index, cursor: cursorPosition, bounds: bounds, time: timestamp)
            }
            pointingFrozen = freeze
            let location = filter.update(point: index, bounds: bounds, time: timestamp,
                precision: settings.precisionMode, steadyAim: settings.steadyAim, freeze: freeze)
            lastLocation = location
            return InteractionStep(location: location,
                click: SafetyPolicy.shouldInjectClick(gestureFired: fired,
                    allowClicks: settings.allowClicks, axTrusted: inputAllowed,
                    pointerControlEnabled: settings.pointerEnabled), destination: destination)
        }
        // Lock on the first close observation, independent of tap arming/timeout.
        // Missing proximity observations retain an existing lock until visible separation.
        let wasTogether = fingersTogether
        if settings.mode == .twoFingerTap && settings.allowClicks {
            if let ratio = fingerSeparationRatio, ratio.isFinite, ratio >= 0 {
                if ratio <= 0.30 { fingersTogether = true }
                else if ratio >= 0.42 { fingersTogether = false }
            }
        } else { fingersTogether = false }
        if wasTogether && !fingersTogether {
            filter.reanchor(point: index, cursor: cursorPosition, bounds: bounds, time: timestamp)
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
        let freeze = settings.allowClicks && (settings.mode == .twoFingerTap ? fingersTogether || tap.shouldFreeze || fired : (settings.mode == .forward ? forward.shouldFreeze : pinch.shouldFreeze))
        let location = filter.update(point: index, bounds: bounds, time: timestamp, precision: settings.precisionMode,
                                     steadyAim: (settings.mode == .twoFingerTap || settings.mode == .pointAndHold) && settings.steadyAim, freeze: freeze)
        lastLocation = location
        return InteractionStep(location: location,
                               click: SafetyPolicy.shouldInjectClick(gestureFired: fired,
                                   allowClicks: settings.allowClicks, axTrusted: inputAllowed,
                                   pointerControlEnabled: settings.pointerEnabled),
                               destination: destination)
    }
}
