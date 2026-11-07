import Foundation
import CoreGraphics

/// One camera observation of the controlling hand, in normalized image space.
struct HandInput {
    var index: CGPoint?
    var timestamp: Double
    var handSide: String? = nil
    var palm: CGPoint? = nil
    var fiveFingerPinchRatio: Double? = nil
    var threeFingerPinchRatio: Double? = nil
    var isL = false
    var lReleased = false
    var companionPresent = false
    var companionL = false
    var companionReleased = false
}

struct InteractionSettings: Equatable {
    var allowClicks = true
    var pointerEnabled = true
    var allowScrolling = false
    var allowDragging = false
    var precisionMode = false
    var steadyAim = true
}

enum ClickPreference {
    static func restored(saved: Bool?, legacy: Bool?) -> Bool { saved ?? legacy ?? true }
}

enum InteractionBlock: String, Codable {
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
///
/// Each frame passes the gates, acquires the pointer, then tries one gesture
/// at a time in priority order: two-hand drag, five-finger right click,
/// three-finger scroll, and finally hold-still clicking while aiming.
struct InteractionEngine {
    private(set) var settings = InteractionSettings()
    private(set) var stillClick = StillClickDetector()
    private(set) var rightPinch = FiveFingerPinchDetector()
    private(set) var rightGestureActive = false
    private(set) var acquisition = PointerAcquisition()
    private(set) var scroll = ScrollDetector()
    private(set) var drag = TwoHandDragDetector()
    private(set) var dragModifierPresent = false
    private var filter = PointerFilter()
    private var scrollPinched = false
    private var pointerFrozen = false
    private var lastTimestamp: Double?
    private var lastDestination: InteractionDestination?
    private var lastLocation: CGPoint?
    private var lastBounds: CGRect?

    /// Thumb, index, and middle fingertips closer than this scroll; wider than
    /// the open ratio releases, so jitter at the threshold cannot flicker.
    static let scrollPinchClose = 0.42
    static let scrollPinchOpen = 0.60
    /// A physical mouse moving the cursor farther than this hands control back.
    static let physicalTakeoverPoints = 12.0

    var pointerControlRegion: CGRect { filter.controlRegion }
    var clickPhase: StillClickDetector.Phase { stillClick.phase }
    var clickProgress: Double { stillClick.progress }
    var clickRemainingSeconds: Double { stillClick.remainingSeconds }

    mutating func configure(_ newSettings: InteractionSettings) {
        guard settings != newSettings else { return }
        settings = newSettings
        reset()
    }

    mutating func reset() {
        cancelGestures(nil)
        filter.reset(); acquisition.reset()
        lastTimestamp = nil; lastDestination = nil; lastLocation = nil; lastBounds = nil
    }

    /// Stops an in-progress gesture when delivery stalls, retaining post-click rearm rules.
    mutating func trackingInterrupted(_ cancellation: StillClickDetector.Cancellation = .trackingInterrupted) {
        cancelGestures(cancellation)
        filter.reset(); acquisition.interrupt(); lastLocation = nil
    }

    private mutating func cancelGestures(_ cancellation: StillClickDetector.Cancellation?) {
        stillClick.reset(cancellation: cancellation)
        rightPinch.reset(); rightGestureActive = false
        pointerFrozen = false; dragModifierPresent = false; scrollPinched = false
        drag.interrupt(); scroll.reset()
    }

    mutating func process(_ input: HandInput, now: Double, bounds: CGRect, running: Bool, trusted: Bool,
                          destination: InteractionDestination = .system, cursorPosition: CGPoint?) -> InteractionStep {
        dragModifierPresent = false
        guard running else { reset(); return InteractionStep(blocked: .paused) }
        let inputAllowed = trusted || destination == .practice
        guard inputAllowed else { reset(); return InteractionStep(blocked: .permission) }
        guard settings.pointerEnabled else { reset(); return InteractionStep(blocked: .previewOnly) }
        if lastDestination != destination { reset(); lastDestination = destination }
        let timestamp = input.timestamp
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
        if let previous = lastTimestamp, timestamp - previous > GestureTuning.trackingGraceSeconds + 1e-9 {
            trackingInterrupted(.frameGap)
        }
        lastTimestamp = timestamp
        guard let index = input.index, index.x.isFinite, index.y.isFinite else {
            trackingInterrupted(); return InteractionStep(blocked: .missingHand)
        }
        guard let cursor = cursorPosition, cursor.x.isFinite, cursor.y.isFinite, bounds.contains(cursor) else {
            trackingInterrupted(); return InteractionStep(blocked: .cursorUnavailable)
        }
        if let owner = acquisition.owner, owner != input.handSide {
            trackingInterrupted(); return InteractionStep(blocked: .differentHand)
        }
        if let lastLocation, hypot(cursor.x - lastLocation.x, cursor.y - lastLocation.y) > Self.physicalTakeoverPoints {
            trackingInterrupted()
        }

        let wasActive = acquisition.active
        guard acquisition.update(point: index, cursor: cursor, side: input.handSide) else {
            cancelGestures(.trackingInterrupted)
            return InteractionStep(blocked: .acquiring)
        }
        if !wasActive {
            // Control resumes at the existing cursor; the hand never warps it.
            filter.reanchor(point: index, cursor: cursor, bounds: bounds, time: timestamp)
            lastLocation = cursor
            return InteractionStep(location: cursor, destination: destination)
        }

        let frame = Frame(input: input, index: index, cursor: cursor, bounds: bounds,
                          destination: destination, inputAllowed: inputAllowed)
        if let step = dragStep(frame) { return step }
        if let step = rightClickStep(frame) { return step }
        if let step = scrollStep(frame) { return step }
        return clickStep(frame)
    }

    /// Everything a gesture step needs after the gates and acquisition passed.
    private struct Frame {
        let input: HandInput
        let index: CGPoint
        let cursor: CGPoint
        let bounds: CGRect
        let destination: InteractionDestination
        let inputAllowed: Bool
        var time: Double { input.timestamp }
    }

    private func injected(_ fired: Bool, inputAllowed: Bool) -> Bool {
        SafetyPolicy.shouldInjectClick(gestureFired: fired, allowClicks: settings.allowClicks,
                                       axTrusted: inputAllowed, pointerControlEnabled: settings.pointerEnabled)
    }

    /// The second hand is a modifier only. Its appearance cancels single-hand
    /// click/scroll intent, even before it forms an L. Only the owner's index moves.
    private mutating func dragStep(_ frame: Frame) -> InteractionStep? {
        guard settings.allowDragging, frame.input.companionPresent || drag.phase != .idle else { return nil }
        let input = frame.input
        dragModifierPresent = input.companionPresent
        stillClick.reset(cancellation: .competingGesture)
        rightPinch.reset(); rightGestureActive = false; pointerFrozen = false
        scroll.reset()
        let previous = drag.phase
        if settings.allowClicks {
            drag.update(bothL: input.isL && input.companionPresent && input.companionL,
                visiblyReleased: input.lReleased || (input.companionPresent && input.companionReleased), time: frame.time)
        } else { drag.interrupt() }
        let began = previous != .dragging && drag.phase == .dragging
        let ended = previous == .dragging && drag.phase != .dragging
        if began {
            // Start at the aim held during confirmation; discard hand motion while arming.
            filter.reanchor(point: frame.index, cursor: frame.cursor, bounds: frame.bounds, time: frame.time)
        }
        let location = filter.update(point: frame.index, bounds: frame.bounds, time: frame.time, precision: settings.precisionMode,
            steadyAim: settings.steadyAim && drag.phase != .dragging,
            freeze: settings.allowClicks && (drag.phase == .confirming || began || ended))
        lastLocation = location
        return InteractionStep(location: location, destination: frame.destination, dragging: drag.phase == .dragging)
    }

    /// All five fingertips closing wins over the embedded three-finger scroll
    /// pinch. A lost fingertip observation cannot turn a held right click into a scroll.
    private mutating func rightClickStep(_ frame: Frame) -> InteractionStep? {
        let fired: Bool
        if settings.allowClicks {
            fired = rightPinch.update(ratio: frame.input.fiveFingerPinchRatio, time: frame.time)
        } else { rightPinch.reset(); fired = false }
        let wasActive = rightGestureActive
        if let ratio = frame.input.fiveFingerPinchRatio, ratio.isFinite, ratio >= 0 {
            if ratio < 0.75 { rightGestureActive = true }
            else if ratio > 0.85 { rightGestureActive = false }
        }
        guard rightGestureActive || wasActive else { return nil }
        stillClick.reset(cancellation: .competingGesture); scroll.reset(); scrollPinched = false
        pointerFrozen = true
        if !rightGestureActive {
            filter.reanchor(point: frame.index, cursor: frame.cursor, bounds: frame.bounds, time: frame.time)
        }
        let location = filter.update(point: frame.index, bounds: frame.bounds, time: frame.time,
            precision: settings.precisionMode, steadyAim: settings.steadyAim, freeze: true)
        lastLocation = location
        return InteractionStep(location: location, rightClick: injected(fired, inputAllowed: frame.inputAllowed),
                               destination: frame.destination)
    }

    /// Thumb, index, and middle fingertips together scroll with palm motion.
    /// The pointer stays frozen; releasing resumes aiming at the same cursor.
    private mutating func scrollStep(_ frame: Frame) -> InteractionStep? {
        var scrollPoint: CGPoint?
        if settings.allowScrolling, let ratio = frame.input.threeFingerPinchRatio, ratio.isFinite, ratio >= 0,
           let palm = frame.input.palm, palm.x.isFinite, palm.y.isFinite {
            if ratio < Self.scrollPinchClose { scrollPinched = true }
            else if ratio > Self.scrollPinchOpen { scrollPinched = false }
            scrollPoint = scrollPinched ? palm : nil
        } else { scrollPinched = false }
        if let scrollPoint {
            stillClick.reset(cancellation: .competingGesture)
            pointerFrozen = true
            let delta = scroll.update(point: scrollPoint, time: frame.time)
            if scroll.phase == .idle {
                trackingInterrupted()
                return InteractionStep(blocked: .acquiring)
            }
            let location = filter.update(point: frame.index, bounds: frame.bounds, time: frame.time,
                                         precision: settings.precisionMode, freeze: true)
            lastLocation = location
            return InteractionStep(location: location, scrollY: delta, destination: frame.destination)
        }
        guard scroll.phase != .idle else { return nil }
        scroll.reset(); stillClick.reset(cancellation: .competingGesture)
        filter.reanchor(point: frame.index, cursor: frame.cursor, bounds: frame.bounds, time: frame.time)
        lastLocation = frame.cursor
        return InteractionStep(location: frame.cursor, destination: frame.destination)
    }

    /// Ordinary aiming. The pointer moves freely and a click fires where it has rested.
    private mutating func clickStep(_ frame: Frame) -> InteractionStep {
        if pointerFrozen {
            // Finger motion during a frozen gesture is not pointer travel.
            filter.reanchor(point: frame.index, cursor: frame.cursor, bounds: frame.bounds, time: frame.time)
            pointerFrozen = false
        }
        let location = filter.update(point: frame.index, bounds: frame.bounds, time: frame.time,
            precision: settings.precisionMode, steadyAim: settings.steadyAim, freeze: false)
        let fired: Bool
        if settings.allowClicks {
            fired = stillClick.update(location: location, time: frame.time)
        } else { stillClick.reset(cancellation: .clicksDisabled); fired = false }
        lastLocation = location
        return InteractionStep(location: location, click: injected(fired, inputAllowed: frame.inputAllowed),
                               destination: frame.destination)
    }
}
