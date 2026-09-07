import AVFoundation
import Vision

struct HandFrame {
    var points: [VNHumanHandPoseObservation.JointName: CGPoint]
    var pinchRatio: Double?
    var timestamp: Double
    var aspect: CGFloat
    var forwardPose: ForwardPose?
    var forwardIssue: ForwardPoseIssue? = nil
    var source = ""
    var handSide: String?
    var dragPinchRatio: Double?
    var palm: CGPoint?
    var scrollPoint: CGPoint?
    var pointingPose: PointingPose?
    var fiveFingerPinchRatio: Double?
    var tapPose: TapPose?
    var fingerSeparationRatio: Double?
    var isL = false
    var lReleased = false
    var companionPresent = false
    var companionL = false
    var companionReleased = false
}

struct HandCapture {
    var hands: [HandFrame] = []
    var timestamp: Double
    var aspect: CGFloat
    var source: String
}

final class HandCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "handmouse.camera", qos: .userInitiated)
    private let request = VNDetectHumanHandPoseRequest()
    var onFrame: ((HandCapture) -> Void)?
    var onStatus: ((String) -> Void)?
    var onError: ((String) -> Void)?
    private var configured = false
    private var generation = 0 // Main thread only.
    private var activeGeneration = 0 // Capture queue only.
    private var captureActive = false // Capture queue only.
    private var sourceID = "" // Capture queue only; never persisted or logged.
    private var observers: [NSObjectProtocol] = []
    private var consecutiveVisionFailures = 0 // Capture queue only.
    private let delivery = LatestFrameBuffer<(frame: HandCapture, token: Int)>()

    override init() {
        super.init()
        request.maximumHandCount = 2
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main) {
                [weak self] notification in self?.captureRuntimeError(notification)
            },
            center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: .main) {
                [weak self] _ in self?.captureWasInterrupted()
            },
            center.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification, object: nil, queue: .main) {
                [weak self] notification in self?.captureDeviceWasDisconnected(notification)
            }
        ]
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    func start() {
        generation += 1
        let token = generation
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configureAndStart(token: token)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                DispatchQueue.main.async {
                    guard let self, self.generation == token else { return }
                    if allowed { self.configureAndStart(token: token) }
                    else { self.onError?("Camera permission needed. Open Camera Settings, then try again.") }
                }
            }
        default: onError?("Camera permission needed. Open Camera Settings, then try again.")
        }
    }

    func stop() {
        generation += 1
        queue.async { [self] in
            captureActive = false
            invalidateConfiguration()
        }
    }

    private func configureAndStart(token: Int) {
        queue.async { [self] in
            activeGeneration = token
            captureActive = true
            do {
                if !configured {
                    let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera],
                        mediaType: .video, position: .unspecified).devices
                    guard let device = devices.first(where: { $0.position == .front }) ?? devices.first
                            ?? AVCaptureDevice.default(for: .video) else {
                        captureActive = false
                        status("No camera found. Connect a camera and try again.", token: token, error: true); return
                    }
                    let input = try AVCaptureDeviceInput(device: device)
                    session.beginConfiguration()
                    defer { session.commitConfiguration() }
                    if session.canSetSessionPreset(.vga640x480) { session.sessionPreset = .vga640x480 }
                    guard session.canAddInput(input) else {
                        captureActive = false
                        status("Cannot open this camera.", token: token, error: true); return
                    }
                    session.addInput(input)
                    let output = AVCaptureVideoDataOutput()
                    output.alwaysDiscardsLateVideoFrames = true
                    output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                    output.setSampleBufferDelegate(self, queue: queue)
                    guard session.canAddOutput(output) else {
                        session.removeInput(input); captureActive = false
                        status("Cannot read camera frames.", token: token, error: true); return
                    }
                    session.addOutput(output)
                    if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
                        connection.automaticallyAdjustsVideoMirroring = false
                        connection.isVideoMirrored = false
                    }
                    configured = true
                    sourceID = device.uniqueID
                }
                session.startRunning()
                if session.isRunning {
                    consecutiveVisionFailures = 0
                    status("Show one hand, palm toward camera. Raise only your index finger and hold still briefly.", token: token)
                } else {
                    captureActive = false
                    invalidateConfiguration()
                    status("Camera could not start. Close other camera apps, then start camera again.",
                           token: token, error: true)
                }
            } catch {
                captureActive = false
                invalidateConfiguration()
                status("Camera error: \(error.localizedDescription). Start camera to try again.",
                       token: token, error: true)
            }
        }
    }

    private func captureRuntimeError(_ notification: Notification) {
        let token = generation
        let detail = (notification.userInfo?[AVCaptureSessionErrorKey] as? Error)?.localizedDescription
        queue.async { [weak self] in
            guard let self else { return }
            let message = detail.map { "Camera stopped after a system error: \($0). Start camera to try again." }
                ?? "Camera stopped after a system error. Start camera to try again."
            self.failCapture(message, token: token)
        }
    }

    private func captureWasInterrupted() {
        let token = generation
        queue.async { [weak self] in
            guard let self else { return }
            self.failCapture("Camera was interrupted. Close other camera apps if needed, then start camera again.",
                             token: token)
        }
    }

    private func captureDeviceWasDisconnected(_ notification: Notification) {
        guard let disconnected = notification.object as? AVCaptureDevice else { return }
        let token = generation
        queue.async { [weak self] in
            guard let self else { return }
            let wasSelected = self.session.inputs.compactMap { $0 as? AVCaptureDeviceInput }
                .contains { $0.device.uniqueID == disconnected.uniqueID }
            guard wasSelected else { return }
            self.failCapture("Camera disconnected. Reconnect it, then start camera again.",
                             token: token)
        }
    }

    private func failCapture(_ message: String, token: Int) {
        guard captureActive, token == activeGeneration else { return }
        captureActive = false
        invalidateConfiguration()
        status(message, token: token, error: true)
    }

    private func invalidateConfiguration() {
        if session.isRunning { session.stopRunning() }
        session.beginConfiguration()
        for output in session.outputs {
            (output as? AVCaptureVideoDataOutput)?.setSampleBufferDelegate(nil, queue: nil)
            session.removeOutput(output)
        }
        for input in session.inputs { session.removeInput(input) }
        session.commitConfiguration()
        configured = false
        sourceID = ""
        consecutiveVisionFailures = 0
    }

    private func status(_ message: String, token: Int, error: Bool = false) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == token else { return }
            if error { self.onError?(message) } else { self.onStatus?(message) }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        // A removed output can still have a callback queued when a new session starts.
        guard captureActive, session.outputs.contains(where: { $0 === output }) else { return }
        let token = activeGeneration
        let now = ProcessInfo.processInfo.systemUptime
        guard let format = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
        let dimensions = CMVideoFormatDescriptionGetDimensions(format)
        guard dimensions.width > 0, dimensions.height > 0 else { return }
        let aspect = CGFloat(dimensions.width) / CGFloat(dimensions.height)
        var frame = HandCapture(timestamp: now, aspect: aspect,
            source: "\(sourceID):\(dimensions.width)x\(dimensions.height)")
        defer {
            if delivery.offer((frame, token)) {
                DispatchQueue.main.async { [weak self] in
                    guard let self, let latest = self.delivery.take(), self.generation == latest.token else { return }
                    self.onFrame?(latest.frame)
                }
            }
        }
        do {
            try VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up).perform([request])
            frame.hands = try (request.results ?? []).map { try measure($0, capture: frame) }
            consecutiveVisionFailures = 0
        } catch {
            frame.hands = []
            consecutiveVisionFailures += 1
            if consecutiveVisionFailures == 5 {
                let token = activeGeneration
                let detail = error.localizedDescription
                // Leave the delegate callback before stopping and reconfiguring its session.
                queue.async { [weak self] in
                    self?.failCapture("Hand tracking failed repeatedly: \(detail). Start camera to try again.",
                                      token: token)
                }
            }
        }
    }
    private func measure(_ hand: VNHumanHandPoseObservation, capture: HandCapture) throws -> HandFrame {
        let aspect = capture.aspect
        var frame = HandFrame(points: [:], pinchRatio: nil, timestamp: capture.timestamp, aspect: aspect)
        frame.source = capture.source
        let all = try hand.recognizedPoints(.all)
        frame.handSide = hand.chirality == .left ? "left" : (hand.chirality == .right ? "right" : nil)
        for (joint, point) in all where point.confidence >= 0.35 {
            frame.points[joint] = CGPoint(x: 1 - point.location.x, y: 1 - point.location.y)
        }
        let palmJoints: [VNHumanHandPoseObservation.JointName] = [.wrist, .indexMCP, .middleMCP, .littleMCP]
        frame.palm = PinchDragPalm.measure(points: palmJoints.map { frame.points[$0] },
            confidences: palmJoints.map { Double(all[$0]?.confidence ?? 0) })
        // A hidden thumb or pinky must not prevent index-finger movement.
        guard (all[.indexTip]?.confidence ?? 0) >= 0.45 else {
            frame.points.removeValue(forKey: .indexTip); return frame
        }
        func finger(_ tip: VNHumanHandPoseObservation.JointName, _ pip: VNHumanHandPoseObservation.JointName,
                    _ base: VNHumanHandPoseObservation.JointName) -> FingerShape {
            guard [tip, pip, base].allSatisfy({ (all[$0]?.confidence ?? 0) >= 0.6 }),
                  let t = frame.points[tip], let p = frame.points[pip], let b = frame.points[base] else { return .uncertain }
            return ScrollPoseGeometry.shape(tip: t, pip: p, base: b, aspect: Double(aspect))
        }
        let indexShape = finger(.indexTip, .indexPIP, .indexMCP)
        let middleShape = finger(.middleTip, .middlePIP, .middleMCP)
        if indexShape == .extended,
           finger(.ringTip, .ringPIP, .ringMCP) == .folded,
           finger(.littleTip, .littlePIP, .littleMCP) == .folded {
            if middleShape == .folded { frame.pointingPose = .move }
            else if middleShape == .extended { frame.pointingPose = .click }
        }
        let tipJoints: [VNHumanHandPoseObservation.JointName] = [.thumbTip, .indexTip, .middleTip, .ringTip, .littleTip]
        if (tipJoints + palmJoints).allSatisfy({ (all[$0]?.confidence ?? 0) >= 0.6 }),
           let indexBase = frame.points[.indexMCP], let littleBase = frame.points[.littleMCP],
           let wrist = frame.points[.wrist], let middleBase = frame.points[.middleMCP] {
            frame.fiveFingerPinchRatio = FiveFingerPinchGeometry.ratio(tips: tipJoints.compactMap { frame.points[$0] },
                indexBase: indexBase, littleBase: littleBase, wrist: wrist, middleBase: middleBase, aspect: Double(aspect))
        }
        let tapJoints: [VNHumanHandPoseObservation.JointName] = [.indexTip, .indexPIP, .indexMCP, .middleTip, .middlePIP, .middleMCP]
        if tapJoints.allSatisfy({ (all[$0]?.confidence ?? 0) >= 0.6 }) {
            let indexShape = finger(.indexTip, .indexPIP, .indexMCP)
            let middleShape = finger(.middleTip, .middlePIP, .middleMCP)
            if indexShape == .extended && middleShape == .extended { frame.tapPose = .raised }
            else if indexShape == .folded && middleShape == .folded { frame.tapPose = .bent }
            else { frame.tapPose = .transition }
        }
        let separationJoints: [VNHumanHandPoseObservation.JointName] = [.indexTip, .middleTip, .indexMCP, .littleMCP]
        if separationJoints.allSatisfy({ (all[$0]?.confidence ?? 0) >= 0.6 }),
           let index = frame.points[.indexTip], let middle = frame.points[.middleTip] {
            frame.fingerSeparationRatio = HandGeometry.pinchRatio(thumb: middle, index: index,
                indexBase: frame.points[.indexMCP], littleBase: frame.points[.littleMCP],
                wrist: nil, middleBase: nil, aspect: Double(aspect))
        }
        // Only clearly folded pointing fingers or unfolded remaining fingers prove release.
        // Low-confidence joints and marginal L angles never rearm a canceled drag.
        frame.lReleased = finger(.thumbTip, .thumbIP, .thumbMP) == .folded
            || finger(.indexTip, .indexPIP, .indexMCP) == .folded
            || finger(.middleTip, .middlePIP, .middleMCP) == .extended
            || finger(.ringTip, .ringPIP, .ringMCP) == .extended
            || finger(.littleTip, .littlePIP, .littleMCP) == .extended
        let lJoints: [VNHumanHandPoseObservation.JointName] = [.thumbTip, .thumbIP, .thumbMP, .indexTip, .indexPIP, .indexMCP]
        if lJoints.allSatisfy({ (all[$0]?.confidence ?? 0) >= 0.6 }),
           let thumb = frame.points[.thumbTip], let thumbIP = frame.points[.thumbIP], let thumbBase = frame.points[.thumbMP],
           let index = frame.points[.indexTip], let indexPIP = frame.points[.indexPIP], let indexBase = frame.points[.indexMCP] {
            frame.isL = LPoseGeometry.matches(thumbTip: thumb, thumbIP: thumbIP, thumbBase: thumbBase,
                indexTip: index, indexPIP: indexPIP, indexBase: indexBase,
                otherFingersFolded: finger(.middleTip, .middlePIP, .middleMCP) == .folded
                    && finger(.ringTip, .ringPIP, .ringMCP) == .folded
                    && finger(.littleTip, .littlePIP, .littleMCP) == .folded,
                aspect: Double(aspect))
        }
        if finger(.indexTip, .indexPIP, .indexMCP) == .extended,
           finger(.middleTip, .middlePIP, .middleMCP) == .extended,
           finger(.ringTip, .ringPIP, .ringMCP) == .folded,
           finger(.littleTip, .littlePIP, .littleMCP) == .folded,
           let index = frame.points[.indexTip], let middle = frame.points[.middleTip] {
            frame.scrollPoint = CGPoint(x: (index.x + middle.x) / 2, y: (index.y + middle.y) / 2)
        }
        func forwardJoint(_ name: VNHumanHandPoseObservation.JointName) -> ForwardJoint? {
            guard let point = all[name] else { return nil }
            return ForwardJoint(point: CGPoint(x: 1 - point.location.x, y: 1 - point.location.y),
                                confidence: Double(point.confidence))
        }
        let forward = ForwardPose.assess(index: forwardJoint(.indexTip), pip: forwardJoint(.indexPIP),
            dip: forwardJoint(.indexDIP), base: forwardJoint(.indexMCP), littleBase: forwardJoint(.littleMCP),
            middleBase: forwardJoint(.middleMCP), wrist: forwardJoint(.wrist),
            aspect: Double(aspect), side: frame.handSide ?? "unknown")
        frame.forwardPose = forward.pose
        frame.forwardIssue = forward.issue
        guard let thumb = frame.points[.thumbTip], let index = frame.points[.indexTip] else { return frame }
        frame.pinchRatio = HandGeometry.pinchRatio(thumb: thumb, index: index,
            indexBase: frame.points[.indexMCP], littleBase: frame.points[.littleMCP],
            wrist: frame.points[.wrist], middleBase: frame.points[.middleMCP], aspect: Double(aspect))
        if frame.palm != nil, (all[.thumbTip]?.confidence ?? 0) >= 0.6,
           (all[.indexTip]?.confidence ?? 0) >= 0.6 {
            frame.dragPinchRatio = frame.pinchRatio
        }
        return frame
    }
}
