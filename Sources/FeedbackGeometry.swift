import Foundation
import CoreGraphics

/// Keeps the label inside a display without moving the ring away from the click target.
struct CursorFeedbackLayout {
    static func appKitPoint(_ quartzPoint: CGPoint, primaryTop: CGFloat) -> CGPoint {
        CGPoint(x: quartzPoint.x, y: primaryTop - quartzPoint.y)
    }

    let origin: CGPoint
    let ringOrigin: CGPoint
    let labelOrigin: CGPoint

    init(center: CGPoint, screen: CGRect) {
        let x = min(max(center.x - 75, screen.minX), screen.maxX - 150)
        let y = min(max(center.y - 55, screen.minY), screen.maxY - 110)
        origin = CGPoint(x: x, y: y)
        let local = CGPoint(x: center.x - x, y: center.y - y)
        ringOrigin = CGPoint(x: local.x - 25, y: local.y - 25)
        // Move the caption above the pointer when it would fall below the display.
        let captionY = local.y >= 50 ? local.y - 50 : local.y + 28
        labelOrigin = CGPoint(x: 0, y: min(88, max(0, captionY)))
    }
}
