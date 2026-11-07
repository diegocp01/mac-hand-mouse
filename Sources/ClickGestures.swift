import Foundation
import CoreGraphics

enum FingerShape: String, Codable { case extended, folded, uncertain }

/// Hold-still click: keep the on-screen pointer inside a small circle for one
/// second and it clicks once. No finger pose is needed. After a click the
/// pointer must travel away before another click can start, so resting in
/// place never repeats clicks.
struct StillClickDetector {
    enum Phase: String, Codable { case ready, holding, clicked }
    enum Cancellation: String, Codable {
        case movement, frameGap, invalidTime, invalidPoint, trackingInterrupted, competingGesture, clicksDisabled

        var title: String {
            switch self {
            case .movement: return "Pointer moved beyond the hold limit"
            case .frameGap: return "Camera callback gap exceeded 120 ms"
            case .invalidTime: return "Invalid or out-of-order frame time"
            case .invalidPoint: return "Pointer position was missing or invalid"
            case .trackingInterrupted: return "Hand tracking was interrupted"
            case .competingGesture: return "Another gesture took priority"
            case .clicksDisabled: return "Clicking was disabled"
            }
        }
    }

    private(set) var phase: Phase = .ready
    private(set) var lastCancellation: Cancellation?
    private var anchor: CGPoint?
    private var stillSince: Double?
    private var stillSamples = 0
    private var lastTime: Double?
    private var observed = 0.0

    /// Stillness before the ring appears, so ordinary aiming shows nothing.
    static let settleSeconds = 0.25
    /// Ring fill time after settling. Total time to click is settle + hold.
    static let holdSeconds = 0.75
    /// Screen points the pointer may wander while still counting as still.
    static let stillRadius = 14.0
    /// Screen points the pointer must travel after a click to allow another.
    static let rearmDistance = 36.0
    private let maximumGap = 0.12

    var progress: Double {
        if phase == .clicked { return 1 }
        guard phase == .holding else { return 0 }
        return min(1, max(0, (observed - Self.settleSeconds) / Self.holdSeconds))
    }

    var remainingSeconds: Double {
        phase == .holding ? max(0, Self.settleSeconds + Self.holdSeconds - observed) : 0
    }

    /// Screen distance from the current anchor, for diagnostics only.
    func movement(from location: CGPoint?) -> Double? {
        guard let anchor, let location, location.x.isFinite, location.y.isFinite else { return nil }
        return hypot(location.x - anchor.x, location.y - anchor.y)
    }

    mutating func reset(cancellation: Cancellation? = nil) {
        if let cancellation, phase == .holding { lastCancellation = cancellation }
        else if cancellation == nil { lastCancellation = nil }
        // A reset after a click keeps the click anchor so stopping and
        // restarting tracking in place cannot click again.
        if phase != .clicked { phase = .ready; anchor = nil }
        stillSince = nil; stillSamples = 0; lastTime = nil; observed = 0
    }

    /// `location` is the pointer position in screen points. Returns true once per click.
    mutating func update(location: CGPoint?, time: Double) -> Bool {
        guard time.isFinite else { reset(cancellation: .invalidTime); return false }
        if let previous = lastTime, time <= previous || time - previous > maximumGap + 1e-9 {
            reset(cancellation: time <= previous ? .invalidTime : .frameGap)
        }
        lastTime = time
        guard let location, location.x.isFinite, location.y.isFinite else {
            reset(cancellation: .invalidPoint); return false
        }
        if phase == .clicked {
            guard let anchor, hypot(location.x - anchor.x, location.y - anchor.y) > Self.rearmDistance else { return false }
            phase = .ready; self.anchor = location; stillSince = time; stillSamples = 1; observed = 0
            return false
        }
        guard let anchor, let since = stillSince,
              hypot(location.x - anchor.x, location.y - anchor.y) <= Self.stillRadius else {
            if phase == .holding { lastCancellation = .movement }
            phase = .ready; self.anchor = location; stillSince = time; stillSamples = 1; observed = 0
            return false
        }
        stillSamples += 1
        observed = time - since
        if observed + 1e-9 >= Self.settleSeconds { phase = .holding }
        guard phase == .holding, stillSamples >= 3,
              observed + 1e-9 >= Self.settleSeconds + Self.holdSeconds else { return false }
        phase = .clicked
        return true
    }
}

/// Detects one observed fingertip-closing cycle. Palm-relative geometry is an
/// image-space proxy: this detector cannot establish physical fingertip contact.
struct FiveFingerPinchDetector {
    enum Phase { case needsOpen, ready, confirming, held }

    private(set) var phase: Phase = .needsOpen
    private var lastTime: Double?
    private var openSince: Double?
    private var openSamples = 0
    private var closedSince: Double?
    private var closedSamples = 0

    private let maximumGap = 0.12
    private let epsilon = 1e-9

    var shouldFreeze: Bool { phase == .confirming || phase == .held }

    mutating func reset() {
        phase = .needsOpen; lastTime = nil; openSince = nil; openSamples = 0
        closedSince = nil; closedSamples = 0
    }

    mutating func update(ratio: Double?, time: Double) -> Bool {
        guard time.isFinite else { reset(); return false }
        if let previous = lastTime,
           time <= previous || time - previous > maximumGap + epsilon { reset() }
        lastTime = time
        guard let ratio, ratio.isFinite, ratio >= 0 else { reset(); return false }

        if phase == .held {
            guard ratio > 0.85 else { return false }
            phase = .needsOpen; openSince = nil; openSamples = 0
            closedSince = nil; closedSamples = 0
        }

        switch phase {
        case .needsOpen:
            guard ratio > 1.0 else { openSince = nil; openSamples = 0; return false }
            if openSince == nil { openSince = time }
            openSamples += 1
            if openSamples >= 3, time - (openSince ?? time) + epsilon >= 0.15 {
                phase = .ready
            }
            return false
        case .ready:
            guard ratio < 0.55 else { return false }
            phase = .confirming; closedSince = time; closedSamples = 1
            return false
        case .confirming:
            // Breaking a closing attempt requires a visibly open hand before
            // another attempt, just like interrupted or delivered clicks.
            guard ratio < 0.55 else {
                phase = .needsOpen; openSince = nil; openSamples = 0
                closedSince = nil; closedSamples = 0
                return false
            }
            closedSamples += 1
            guard let since = closedSince, closedSamples >= 3,
                  time - since + epsilon >= 0.10 else { return false }
            phase = .held
            return true
        case .held:
            return false
        }
    }
}

enum ThreeFingerPinchGeometry {
    static func ratio(tips: [CGPoint], indexBase: CGPoint, littleBase: CGPoint,
                      wrist: CGPoint, middleBase: CGPoint, aspect: Double) -> Double? {
        guard tips.count == 3 else { return nil }
        return FingertipClusterGeometry.ratio(tips: tips, indexBase: indexBase, littleBase: littleBase,
            wrist: wrist, middleBase: middleBase, aspect: aspect)
    }
}

enum FiveFingerPinchGeometry {
    static func ratio(tips: [CGPoint], indexBase: CGPoint, littleBase: CGPoint,
                      wrist: CGPoint, middleBase: CGPoint, aspect: Double) -> Double? {
        guard tips.count == 5 else { return nil }
        return FingertipClusterGeometry.ratio(tips: tips, indexBase: indexBase, littleBase: littleBase,
            wrist: wrist, middleBase: middleBase, aspect: aspect)
    }
}

private enum FingertipClusterGeometry {
    /// Every pair of tips must be close. Thumb/index contact alone cannot stand
    /// in for a three-finger pinch. Landmark confidence is checked by the camera.
    static func ratio(tips: [CGPoint], indexBase: CGPoint, littleBase: CGPoint,
                      wrist: CGPoint, middleBase: CGPoint, aspect: Double) -> Double? {
        guard aspect.isFinite, aspect > 0,
              (tips + [indexBase, littleBase, wrist, middleBase]).allSatisfy({
                  $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y)
              }) else { return nil }
        func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
            hypot((a.x - b.x) * aspect, a.y - b.y)
        }
        let scale = max(distance(indexBase, littleBase), distance(wrist, middleBase) * 0.75)
        guard scale.isFinite, scale > 0.035 else { return nil }
        var diameter = 0.0
        for i in 0..<tips.count {
            for j in (i + 1)..<tips.count {
                diameter = max(diameter, distance(tips[i], tips[j]))
            }
        }
        let ratio = diameter / scale
        return ratio.isFinite ? ratio : nil
    }
}
