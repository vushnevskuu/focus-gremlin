import SwiftUI

/// Горизонтальный спрайт-лист: ряд кадров одинаковой ширины (idle / ожидание).
private enum GremlinIdleSheet {
    /// Число кадров в ассете `GremlinIdleSheet` (1 ряд).
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
            GremlinIdleSpriteFrameView(frameIndex: idx, box: size)
        }
    }
}

private struct GremlinIdleSpriteFrameView: View {
    let frameIndex: Int
    let box: CGFloat

    var body: some View {
        let cellW = GremlinIdleSheet.pixelWidth / CGFloat(GremlinIdleSheet.frameCount)
        let cellH = GremlinIdleSheet.pixelHeight
        let s = min(box / cellW, box / cellH)
        let imgW = GremlinIdleSheet.pixelWidth * s
        let imgH = GremlinIdleSheet.pixelHeight * s
        let cellDisplayW = cellW * s
        let cellDisplayH = cellH * s
        let padX = (box - cellDisplayW) * 0.5
        let padY = (box - cellDisplayH) * 0.5

        Image("GremlinIdleSheet")
            .resizable()
            .frame(width: imgW, height: imgH)
            .offset(x: -CGFloat(frameIndex) * cellDisplayW + padX, y: padY)
            .frame(width: box, height: box)
            .clipped()
    }
}
