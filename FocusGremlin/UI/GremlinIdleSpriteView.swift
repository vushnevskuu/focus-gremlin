import SwiftUI

/// Высота одного кадра гремлина на оверлее (ширина из пропорций спрайт-листа).
enum GremlinOverlaySpriteMetrics {
    static let displayHeight: CGFloat = 120
}

/// Один кадр горизонтального спрайт-листа: **AppKit + CGImage.cropping** — настоящий спрайт, один кадр за тик.
struct GremlinStripSpriteFrameView: View {
    let imageName: String
    let frameIndex: Int
    let frameCount: Int
    let pixelWidth: CGFloat
    let pixelHeight: CGFloat
    /// Высота кадра на экране; ширина вью = ширина клетки с учётом масштаба.
    var displayHeight: CGFloat

    var body: some View {
        let cellW = pixelWidth / CGFloat(frameCount)
        let cellH = pixelHeight
        let s = displayHeight / cellH
        let cellDisplayW = cellW * s

        GremlinSpriteStripRepresentable(
            imageName: imageName,
            frameIndex: frameIndex,
            frameCount: frameCount,
            displayHeight: displayHeight
        )
        .frame(width: cellDisplayW, height: displayHeight)
        .transaction { $0.animation = nil }
    }
}

/// Горизонтальный спрайт-лист: ряд кадров одинаковой ширины (idle / ожидание).
private enum GremlinIdleSheet {
    static let frameCount = 20
    /// Лист 20×64×128 (см. scripts/generate_placeholder_gremlin_sheets.py).
    static let pixelWidth: CGFloat = 1280
    static let pixelHeight: CGFloat = 128
    static let fps: Double = 12
}

/// Циклическая анимация idle через `TimelineView` (без ручного Timer).
struct GremlinIdleSpriteView: View {
    var displayHeight: CGFloat = GremlinOverlaySpriteMetrics.displayHeight

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / GremlinIdleSheet.fps)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let idx = Int(t * GremlinIdleSheet.fps) % GremlinIdleSheet.frameCount
            GremlinStripSpriteFrameView(
                imageName: "GremlinIdleSheet",
                frameIndex: idx,
                frameCount: GremlinIdleSheet.frameCount,
                pixelWidth: GremlinIdleSheet.pixelWidth,
                pixelHeight: GremlinIdleSheet.pixelHeight,
                displayHeight: displayHeight
            )
        }
    }
}
