import SwiftUI

/// Один кадр горизонтального спрайт-листа (ровная сетка по ширине).
struct GremlinStripSpriteFrameView: View {
    let imageName: String
    let frameIndex: Int
    let frameCount: Int
    let pixelWidth: CGFloat
    let pixelHeight: CGFloat
    let box: CGFloat

    var body: some View {
        let cellW = pixelWidth / CGFloat(frameCount)
        let cellH = pixelHeight
        let s = min(box / cellW, box / cellH)
        let imgW = pixelWidth * s
        let imgH = pixelHeight * s
        let cellDisplayW = cellW * s
        let cellDisplayH = cellH * s
        let padX = (box - cellDisplayW) * 0.5
        let padY = (box - cellDisplayH) * 0.5

        Image(imageName)
            .resizable()
            .frame(width: imgW, height: imgH)
            .offset(x: -CGFloat(frameIndex) * cellDisplayW + padX, y: padY)
            .frame(width: box, height: box)
            .clipped()
    }
}

/// Горизонтальный спрайт-лист: ряд кадров одинаковой ширины (idle / ожидание).
private enum GremlinIdleSheet {
    static let frameCount = 20
    static let pixelWidth: CGFloat = 1024
    static let pixelHeight: CGFloat = 28
    static let fps: Double = 12
}

/// Циклическая анимация idle через `TimelineView` (без ручного Timer).
struct GremlinIdleSpriteView: View {
    var size: CGFloat = 38

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
                box: size
            )
        }
    }
}
