import Foundation
import CoreGraphics

enum PointingPose { case move, click }
enum FingerShape { case extended, folded, uncertain }

enum PointingPoseClassifier {
    static func classify(index: FingerShape, middle: FingerShape,
                         ring: FingerShape, little: FingerShape) -> PointingPose? {
        // A visible open hand is ordinary aiming and can prepare the next click.
        if ring == .extended || little == .extended { return .move }
        if index == .extended && middle == .folded { return .move }
        // Folded fingertips can obscure one another. One confirmed folded outer
        // finger is sufficient, but absent evidence for both never means a click.
        if index == .extended && middle == .extended &&
            (ring == .folded || little == .folded) { return .click }
        return nil
    }
}

/// A visible pointing pose arms one stationary two-finger hold. Missing samples
/// cancel the hold rather than counting unobserved time toward a click.
struct PointHoldDetector {
    enum Phase { case needsMove, ready, holding, clicked }

    private(set) var phase: Phase = .needsMove
    private var lastTime: Double?
    private var moveSince: Double?
    private var moveSamples = 0
    private var holdSince: Double?
    private var holdSamples = 0
    private var anchor: CGPoint?
    private var observedHold = 0.0

    private let holdSeconds = 1.0
    private let maximumGap = 0.12
    private let epsilon = 1e-9

    var progress: Double {
        if phase == .clicked { return 1 }
        return phase == .holding ? min(1, max(0, observedHold / holdSeconds)) : 0
    }

    var remainingSeconds: Double {
        phase == .holding ? max(0, holdSeconds - observedHold) : 0
    }

    var shouldFreeze: Bool { phase == .holding || phase == .clicked }

    mutating func reset() {
        phase = .needsMove; lastTime = nil; moveSince = nil; moveSamples = 0
        holdSince = nil; holdSamples = 0; anchor = nil; observedHold = 0
    }

    mutating func update(pose: PointingPose?, point: CGPoint?, time: Double) -> Bool {
        guard time.isFinite else { reset(); return false }
        if let previous = lastTime,
           time <= previous || time - previous > maximumGap + epsilon { reset() }
        lastTime = time
        guard let pose, let point,
              point.x.isFinite, point.y.isFinite,
              (0...1).contains(point.x), (0...1).contains(point.y) else {
            reset(); return false
        }

        if pose == .move {
            if phase == .holding || phase == .clicked {
                phase = .needsMove; moveSince = nil; moveSamples = 0
            }
            holdSince = nil; holdSamples = 0; anchor = nil; observedHold = 0
            if moveSince == nil { moveSince = time }
            moveSamples += 1
            if moveSamples >= 3, time - (moveSince ?? time) + epsilon >= 0.15 {
                phase = .ready
            }
            return false
        }

        // A click pose cannot arm itself, including after an interrupted hold.
        moveSince = nil; moveSamples = 0
        switch phase {
        case .needsMove, .clicked:
            return false
        case .ready:
            phase = .holding; holdSince = time; holdSamples = 1
            anchor = point; observedHold = 0
            return false
        case .holding:
            guard let anchor, let since = holdSince,
                  hypot(point.x - anchor.x, point.y - anchor.y) <= 0.025 + epsilon else {
                reset(); return false
            }
            holdSamples += 1
            observedHold = max(0, time - since)
            guard holdSamples >= 3, observedHold + epsilon >= holdSeconds else { return false }
            phase = .clicked; observedHold = holdSeconds
            return true
        }
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
