import Foundation
import CoreGraphics

/// Image-space evidence, not a depth measurement or a claim about user intent.
struct ForwardPose: Equatable {
    var scale: Double
    var reach: Double
    var center: CGPoint
    var side: String

    var isValid: Bool {
        scale.isFinite && scale > 0.035 && scale < 1.5 && reach.isFinite && reach > 0.12 && reach < 3 &&
        center.x.isFinite && center.y.isFinite && (0...1).contains(center.x) && (0...1).contains(center.y) &&
        (side == "left" || side == "right")
    }

    static func measure(index: CGPoint, pip: CGPoint, dip: CGPoint, base: CGPoint,
                        littleBase: CGPoint, middleBase: CGPoint, wrist: CGPoint,
                        aspect: Double, side: String) -> ForwardPose? {
        let points = [index, pip, dip, base, littleBase, middleBase, wrist]
        guard aspect.isFinite, aspect > 0,
              points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }) else { return nil }
        func distance(_ a: CGPoint, _ b: CGPoint) -> Double { hypot(Double(a.x - b.x) * aspect, Double(a.y - b.y)) }
        let scale = max(distance(base, littleBase), distance(wrist, middleBase) * 0.75)
        let reach = distance(index, base)
        let path = distance(index, dip) + distance(dip, pip) + distance(pip, base)
        // Folded or almost completely occluded fingers are ambiguous in a 2D image.
        guard scale > 0.035, path > scale * 0.18, reach / path >= 0.65 else { return nil }
        let center = CGPoint(x: (base.x + littleBase.x + wrist.x) / 3,
                             y: (base.y + littleBase.y + wrist.y) / 3)
        let pose = ForwardPose(scale: scale, reach: reach / scale, center: center, side: side)
        return pose.isValid ? pose : nil
    }

    fileprivate var feature: CGPoint { CGPoint(x: log(scale) / 0.15, y: reach / 0.5) }
}

/// Relative image-space reference; generated automatically from ordinary pointing.
struct ForwardProfile: Equatable {
    let neutral: ForwardPose
    let pressed: ForwardPose

    init?(neutral: ForwardPose, pressed: ForwardPose) {
        guard neutral.isValid, pressed.isValid, neutral.side == pressed.side,
              pressed.scale / neutral.scale >= 1.12 || neutral.reach - pressed.reach >= 0.35 else { return nil }
        self.neutral = neutral; self.pressed = pressed
    }

    func position(of pose: ForwardPose) -> (amount: Double, offAxis: Double)? {
        guard pose.isValid, pose.side == neutral.side else { return nil }
        let a = neutral.feature, b = pressed.feature, p = pose.feature
        let dx = b.x - a.x, dy = b.y - a.y
        let length = dx * dx + dy * dy
        guard length > 0.1 else { return nil }
        let amount = ((p.x - a.x) * dx + (p.y - a.y) * dy) / length
        let offAxis = hypot(p.x - a.x - amount * dx, p.y - a.y - amount * dy)
        return (Double(amount), Double(offAxis))
    }
}

/// Learns hand scale from ordinary pointing, without buttons, pose capture, or stored data.
/// It never uses cursor stillness as click intent; recognized forward holds suspend learning.
struct AutomaticForwardReference {
    private(set) var profile: ForwardProfile?
    private var first: ForwardPose?
    private var since: Double?
    private var lastTime: Double?
    private var count = 0
    private var scaleSum = 0.0
    private var reachSum = 0.0

    mutating func reset() {
        profile = nil; lastTime = nil; clearSamples()
    }
    private mutating func clearSamples() {
        first = nil; since = nil; count = 0; scaleSum = 0; reachSum = 0
    }

    /// Returns true only when the reference changes, so the caller discards pending intent.
    mutating func update(_ pose: ForwardPose?, time: Double, canAdapt: Bool) -> Bool {
        guard let pose, pose.isValid, time.isFinite else { reset(); return true }
        if let lastTime, time <= lastTime || time - lastTime > GestureTuning.trackingGraceSeconds + 1e-9 { reset() }
        lastTime = time
        if let profile, profile.neutral.side != pose.side { reset(); lastTime = time }
        let minimumReach = max(1.05, (profile?.neutral.reach ?? 0) * 0.9)
        guard canAdapt, pose.reach >= minimumReach else { clearSamples(); return false }
        if let first, first.side != pose.side || abs(log(pose.scale / first.scale)) > 0.06 || abs(pose.reach - first.reach) > 0.12 {
            clearSamples()
        }
        if first == nil { first = pose; since = time }
        count += 1; scaleSum += pose.scale; reachSum += pose.reach
        guard count >= 4, time - (since ?? time) >= 0.25 else { return false }
        var neutral = pose
        neutral.scale = scaleSum / Double(count); neutral.reach = reachSum / Double(count)
        clearSamples()
        if let profile, abs(log(neutral.scale / profile.neutral.scale)) < 0.08,
           abs(neutral.reach - profile.neutral.reach) < 0.15 { return false }
        // Shared relative thresholds account for hand size and camera distance.
        // Foreshortening must accompany the forward pose; enlargement alone is off-axis.
        var pressed = neutral
        pressed.scale = min(1.49, neutral.scale * 1.12)
        pressed.reach = neutral.reach * 0.55
        profile = ForwardProfile(neutral: neutral, pressed: pressed)
        return true
    }
}

enum ForwardClickPhase { case needsNeutral, ready, confirming, holding, clicked }

/// A fresh movement → forward pose transition authorizes exactly one countdown.
/// Timer cancellation observes the palm independently of the frozen pointer.
struct ForwardClickDetector {
    var holdSeconds = 0.65
    private(set) var phase: ForwardClickPhase = .needsNeutral
    private(set) var timer = DwellDetector()
    private var neutralSince: Double?
    private var neutralSamples = 0
    private var candidateSince: Double?
    private var pressedSince: Double?
    private var pressedSamples = 0
    private var lastObserved: Double?
    private var lastFire = -Double.infinity
    private var anchor: ForwardPose?
    private var motion: [(Double, CGPoint)] = []

    var progress: Double { phase == .holding ? timer.progress : 0 }
    var remainingSeconds: Double { phase == .holding ? timer.remainingSeconds : 0 }
    var shouldFreeze: Bool { phase == .confirming || phase == .holding || phase == .clicked }

    mutating func reset() {
        phase = .needsNeutral; timer.reset(); neutralSince = nil; neutralSamples = 0
        candidateSince = nil; pressedSince = nil; pressedSamples = 0
        lastObserved = nil; anchor = nil; motion.removeAll()
    }

    mutating func update(_ pose: ForwardPose?, profile: ForwardProfile?, time: Double, bounds: CGRect) -> Bool {
        guard let pose, let profile, let evidence = profile.position(of: pose),
              time.isFinite, holdSeconds.isFinite, holdSeconds >= 0.4,
              bounds.width.isFinite, bounds.height.isFinite, bounds.width > 1, bounds.height > 1 else { reset(); return false }
        if let previous = lastObserved,
           time <= previous || time - previous > GestureTuning.trackingGraceSeconds + 1e-9 { reset() }
        lastObserved = time
        let neutral = evidence.amount < 0.25 && evidence.amount > -0.4 && evidence.offAxis < 0.5
        if neutral {
            if neutralSince == nil { neutralSince = time; neutralSamples = 0 }
            neutralSamples += 1
            if phase != .ready { phase = .needsNeutral; timer.reset(); anchor = nil; motion.removeAll() }
            if time - neutralSince! >= 0.18 && neutralSamples >= 3 && time - lastFire >= 0.45 { phase = .ready }
            return false
        }
        neutralSince = nil; neutralSamples = 0
        guard evidence.offAxis < 0.6, evidence.amount >= 0.25, evidence.amount <= 1.55 else { reset(); return false }
        switch phase {
        case .needsNeutral: return false
        case .ready:
            guard evidence.amount >= 0.45 else { return false }
            phase = .confirming; candidateSince = time; anchor = pose
            pressedSince = nil; pressedSamples = 0; motion.removeAll()
        case .clicked: return false
        case .confirming, .holding: break
        }
        guard let anchor else { reset(); return false }
        // Perspective compensation removes the expected expansion of a forward push.
        let palm = CGPoint(x: ((pose.center.x - 0.5) / pose.scale - (anchor.center.x - 0.5) / anchor.scale) * anchor.scale * bounds.width,
                           y: ((pose.center.y - 0.5) / pose.scale - (anchor.center.y - 0.5) / anchor.scale) * anchor.scale * bounds.height)
        guard palm.x.isFinite, palm.y.isFinite, hypot(palm.x, palm.y) <= 18 else { reset(); return false }
        motion.append((time, palm))
        motion.removeAll { time - $0.0 > 0.22 }
        // A sustained drift cancels even when it has not left the movement radius yet.
        if motion.count >= 4, let first = motion.first, time - first.0 >= 0.16 {
            let meanTime = motion.reduce(0) { $0 + $1.0 } / Double(motion.count)
            let meanX = motion.reduce(0) { $0 + $1.1.x } / Double(motion.count)
            let meanY = motion.reduce(0) { $0 + $1.1.y } / Double(motion.count)
            let variance = motion.reduce(0) { $0 + pow($1.0 - meanTime, 2) }
            let vx = motion.reduce(0) { $0 + ($1.0 - meanTime) * ($1.1.x - meanX) } / max(variance, 1e-9)
            let vy = motion.reduce(0) { $0 + ($1.0 - meanTime) * ($1.1.y - meanY) } / max(variance, 1e-9)
            if hypot(vx, vy) > 16 { reset(); return false }
        }
        if phase == .confirming {
            guard time - (candidateSince ?? time) <= 0.8 else { reset(); return false }
            if evidence.amount >= 0.78 {
                if pressedSince == nil { pressedSince = time }
                pressedSamples += 1
                if pressedSamples >= 3 && time - pressedSince! >= 0.10 {
                    phase = .holding; timer.reset(); timer.settings.dwellSeconds = holdSeconds
                }
            } else { pressedSince = nil; pressedSamples = 0 }
        }
        guard phase == .holding else { return false }
        guard evidence.amount >= 0.60 else { reset(); return false }
        if timer.update(point: palm, time: time, tracking: true) {
            phase = .clicked; lastFire = time
            return true
        }
        // The internal timer can cancel on motion too; never let it auto-rearm
        // while the outer detector is still holding the same forward gesture.
        if timer.phase != .arming { reset() }
        return false
    }
}
