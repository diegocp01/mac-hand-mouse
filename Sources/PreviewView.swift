import AppKit
import AVFoundation
import Vision

final class PreviewView: NSView {
    let preview: AVCaptureVideoPreviewLayer
    private let skeleton = CAShapeLayer()
    private let guide = CAShapeLayer()
    var controlRegion = PointerFilter().controlRegion { didSet { drawHand() } }
    private var points: [VNHumanHandPoseObservation.JointName: CGPoint] = [:]
    private var aspect: CGFloat = 4 / 3
    private let placeholder = NSTextField(wrappingLabelWithString: "")
    private let reticle = StandbyReticleView(frame: .zero)

    init(session: AVCaptureSession) {
        preview = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.borderWidth = 1
        layer?.cornerRadius = 18
        layer?.masksToBounds = true
        preview.videoGravity = .resizeAspect
        layer?.addSublayer(preview)
        skeleton.strokeColor = NSColor.systemMint.cgColor
        skeleton.fillColor = NSColor.systemMint.cgColor
        skeleton.lineWidth = 2
        layer?.addSublayer(skeleton)
        guide.strokeColor = NSColor.white.withAlphaComponent(0.35).cgColor
        guide.fillColor = nil
        guide.lineDashPattern = [6, 6]
        layer?.addSublayer(guide)
        placeholder.textColor = StartupStyle.muted
        placeholder.font = .systemFont(ofSize: 12, weight: .medium)
        placeholder.alignment = .center
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholder)
        reticle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(reticle)
        NSLayoutConstraint.activate([
            placeholder.centerXAnchor.constraint(equalTo: centerXAnchor),
            reticle.centerXAnchor.constraint(equalTo: centerXAnchor),
            reticle.centerYAnchor.constraint(equalTo: centerYAnchor),
            reticle.widthAnchor.constraint(equalToConstant: 82),
            reticle.heightAnchor.constraint(equalToConstant: 82),
            placeholder.topAnchor.constraint(equalTo: reticle.bottomAnchor, constant: 5),
            placeholder.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.8)
        ])
        updateColors()
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }
    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = (placeholder.isHidden ? NSColor.black : StartupStyle.surface).cgColor
            layer?.borderColor = NSColor.separatorColor.cgColor
        }
    }
    override var isFlipped: Bool { true }
    override func layout() {
        super.layout()
        preview.frame = bounds
        drawHand()
    }
    func update(_ frame: HandFrame?, highlighted: Bool = false, clicked: Bool = false) {
        if let connection = preview.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        points = frame?.points ?? [:]
        if let frame { aspect = frame.aspect }
        let color: NSColor = clicked ? .white : (highlighted ? .systemCyan : .systemMint)
        skeleton.strokeColor = color.cgColor
        skeleton.fillColor = color.cgColor
        drawHand()
    }
    func showPlaceholder(_ text: String?) {
        placeholder.stringValue = text ?? ""
        placeholder.isHidden = text == nil
        reticle.isHidden = text == nil
        guide.isHidden = text != nil
        updateColors()
    }
    private func drawHand() {
        // Match the actual capture format, including cameras that deliver 16:9.
        let rect = HandGeometry.fittedRect(in: bounds, aspect: aspect)
        func pixel(_ p: CGPoint) -> CGPoint { CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height) }
        let path = CGMutablePath()
        let chains: [[VNHumanHandPoseObservation.JointName]] = [
            [.wrist, .thumbCMC, .thumbMP, .thumbIP, .thumbTip],
            [.wrist, .indexMCP, .indexPIP, .indexDIP, .indexTip],
            [.wrist, .middleMCP, .middlePIP, .middleDIP, .middleTip],
            [.wrist, .ringMCP, .ringPIP, .ringDIP, .ringTip],
            [.wrist, .littleMCP, .littlePIP, .littleDIP, .littleTip]]
        for chain in chains {
            for pair in zip(chain, chain.dropFirst()) {
                if let a = points[pair.0], let b = points[pair.1] {
                    path.move(to: pixel(a)); path.addLine(to: pixel(b))
                }
            }
        }
        for point in points.values {
            let p = pixel(point)
            path.addEllipse(in: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6))
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        skeleton.path = path
        guide.isHidden = !placeholder.isHidden
        let travelRect = CGRect(x: rect.minX + controlRegion.minX * rect.width,
            y: rect.minY + controlRegion.minY * rect.height,
            width: controlRegion.width * rect.width, height: controlRegion.height * rect.height)
        guide.path = CGPath(roundedRect: travelRect, cornerWidth: 10, cornerHeight: 10, transform: nil)
        CATransaction.commit()
    }
}
