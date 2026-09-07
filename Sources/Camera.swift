import AVFoundation
import Vision

struct HandFrame {
    var points: [VNHumanHandPoseObservation.JointName: CGPoint]
    var pinchRatio: Double
    var timestamp: Double
}

final class HandCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "handmouse.camera", qos: .userInitiated)
    private let request = VNDetectHumanHandPoseRequest()
    var onFrame: ((HandFrame?) -> Void)?
    var onStatus: ((String) -> Void)?
    private var configured = false
    private var generation = 0 // Accessed only on the main thread.

    override init() { super.init(); request.maximumHandCount = 1 }

    func start() {
        generation += 1
        let token = generation
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                DispatchQueue.main.async {
                    guard let self, self.generation == token else { return }
                    if allowed { self.configureAndStart() }
                    else { self.onStatus?("Camera permission needed. Open Camera Settings, then try again.") }
                }
            }
        default: onStatus?("Camera permission needed. Open Camera Settings, then try again.")
        }
    }

    func stop() {
        generation += 1
        queue.async { [self] in if session.isRunning { session.stopRunning() } }
    }

    private func configureAndStart() {
        queue.async { [self] in
            do {
                if !configured {
                    // Prefer the Mac's built-in camera over a phone or virtual camera.
                    let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera],
                        mediaType: .video, position: .unspecified).devices
                    guard let device = devices.first(where: { $0.position == .front }) ?? devices.first
                            ?? AVCaptureDevice.default(for: .video) else {
                        status("No camera found. Connect a camera and try again."); return
                    }
                    let input = try AVCaptureDeviceInput(device: device)
                    session.beginConfiguration()
                    defer { session.commitConfiguration() }
                    session.sessionPreset = .vga640x480
                    guard session.canAddInput(input) else { status("Cannot open this camera."); return }
                    session.addInput(input)
                    let output = AVCaptureVideoDataOutput()
                    output.alwaysDiscardsLateVideoFrames = true
                    output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                    output.setSampleBufferDelegate(self, queue: queue)
                    guard session.canAddOutput(output) else {
                        session.removeInput(input); status("Cannot read camera frames."); return
                    }
                    session.addOutput(output)
                    if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
                        connection.automaticallyAdjustsVideoMirroring = false
                        connection.isVideoMirrored = false
                    }
                    configured = true
                }
                session.startRunning()
                status(session.isRunning ? "Show one hand, with your fingers apart." : "Camera could not start. Try closing other camera apps.")
            } catch { status("Camera error: \(error.localizedDescription)") }
        }
    }

    private func status(_ message: String) {
        DispatchQueue.main.async { [weak self] in self?.onStatus?(message) }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let now = ProcessInfo.processInfo.systemUptime
        // Process every available frame. The serial queue and discard-late setting
        // already prevent a capture backlog; a wall-clock gate can skip good frames.
        do {
            try VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up).perform([request])
            guard let hand = request.results?.first else { deliver(nil); return }
            let all = try hand.recognizedPoints(.all)
            let required: [VNHumanHandPoseObservation.JointName] = [.thumbTip, .indexTip, .indexMCP, .littleMCP]
            guard required.allSatisfy({ (all[$0]?.confidence ?? 0) > 0.45 }) else { deliver(nil); return }
            var points: [VNHumanHandPoseObservation.JointName: CGPoint] = [:]
            for (joint, point) in all where point.confidence > 0.35 {
                // Mirror left/right, and use top-left coordinates for both preview and Quartz.
                points[joint] = CGPoint(x: 1 - point.location.x, y: 1 - point.location.y)
            }
            let dimensions = CMVideoFormatDescriptionGetDimensions(CMSampleBufferGetFormatDescription(sampleBuffer)!)
            let aspect = Double(dimensions.width) / Double(dimensions.height)
            func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
                hypot(Double(a.x - b.x) * aspect, Double(a.y - b.y))
            }
            let palm = distance(points[.indexMCP]!, points[.littleMCP]!)
            guard palm > 0.035 else { deliver(nil); return }
            let ratio = distance(points[.thumbTip]!, points[.indexTip]!) / palm
            deliver(HandFrame(points: points, pinchRatio: ratio, timestamp: now))
        } catch { deliver(nil) }
    }

    private func deliver(_ frame: HandFrame?) {
        DispatchQueue.main.async { [weak self] in self?.onFrame?(frame) }
    }
}
