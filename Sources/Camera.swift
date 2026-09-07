import AVFoundation
import Vision

struct HandFrame {
    var points: [VNHumanHandPoseObservation.JointName: CGPoint]
    var pinchRatio: Double?
    var timestamp: Double
    var aspect: CGFloat
}

final class HandCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "handmouse.camera", qos: .userInitiated)
    private let request = VNDetectHumanHandPoseRequest()
    var onFrame: ((HandFrame) -> Void)?
    var onStatus: ((String) -> Void)?
    var onError: ((String) -> Void)?
    private var configured = false
    private var generation = 0 // Main thread only.
    private var activeGeneration = 0 // Capture queue only.
    private let delivery = LatestFrameBuffer<(frame: HandFrame, token: Int)>()

    override init() { super.init(); request.maximumHandCount = 1 }

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
        queue.async { [self] in if session.isRunning { session.stopRunning() } }
    }

    private func configureAndStart(token: Int) {
        queue.async { [self] in
            activeGeneration = token
            do {
                if !configured {
                    let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera],
                        mediaType: .video, position: .unspecified).devices
                    guard let device = devices.first(where: { $0.position == .front }) ?? devices.first
                            ?? AVCaptureDevice.default(for: .video) else {
                        status("No camera found. Connect a camera and try again.", token: token, error: true); return
                    }
                    let input = try AVCaptureDeviceInput(device: device)
                    session.beginConfiguration()
                    defer { session.commitConfiguration() }
                    if session.canSetSessionPreset(.vga640x480) { session.sessionPreset = .vga640x480 }
                    guard session.canAddInput(input) else { status("Cannot open this camera.", token: token, error: true); return }
                    session.addInput(input)
                    let output = AVCaptureVideoDataOutput()
                    output.alwaysDiscardsLateVideoFrames = true
                    output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                    output.setSampleBufferDelegate(self, queue: queue)
                    guard session.canAddOutput(output) else {
                        session.removeInput(input); status("Cannot read camera frames.", token: token, error: true); return
                    }
                    session.addOutput(output)
                    if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
                        connection.automaticallyAdjustsVideoMirroring = false
                        connection.isVideoMirrored = false
                    }
                    configured = true
                }
                session.startRunning()
                status(session.isRunning ? "Show one hand and separate thumb + index to get ready."
                    : "Camera could not start. Try closing other camera apps.", token: token, error: !session.isRunning)
            } catch { status("Camera error: \(error.localizedDescription)", token: token, error: true) }
        }
    }

    private func status(_ message: String, token: Int, error: Bool = false) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == token else { return }
            if error { self.onError?(message) } else { self.onStatus?(message) }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let token = activeGeneration
        let now = ProcessInfo.processInfo.systemUptime
        guard let format = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
        let dimensions = CMVideoFormatDescriptionGetDimensions(format)
        guard dimensions.height > 0 else { return }
        let aspect = CGFloat(dimensions.width) / CGFloat(dimensions.height)
        var frame = HandFrame(points: [:], pinchRatio: nil, timestamp: now, aspect: aspect)
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
            guard let hand = request.results?.first else { return }
            let all = try hand.recognizedPoints(.all)
            for (joint, point) in all where point.confidence >= 0.35 {
                frame.points[joint] = CGPoint(x: 1 - point.location.x, y: 1 - point.location.y)
            }
            // A hidden thumb or pinky must not prevent index-finger movement.
            guard (all[.indexTip]?.confidence ?? 0) >= 0.45 else {
                frame.points.removeValue(forKey: .indexTip); return
            }
            guard let thumb = frame.points[.thumbTip], let index = frame.points[.indexTip] else { return }
            frame.pinchRatio = HandGeometry.pinchRatio(thumb: thumb, index: index,
                indexBase: frame.points[.indexMCP], littleBase: frame.points[.littleMCP],
                wrist: frame.points[.wrist], middleBase: frame.points[.middleMCP], aspect: Double(aspect))
        } catch { frame.points = [:] }
    }
}
