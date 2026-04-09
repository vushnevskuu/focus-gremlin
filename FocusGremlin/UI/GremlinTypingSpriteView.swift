import SwiftUI

/// Спрайт «смотрит на курсор слева → на текст справа» во время точек и набора текста.
/// Замени `gremlin_typing.png` на свой лист; при другом размере поправь константы ниже.
private enum GremlinTypingSheet {
    static let frameCount = 20
    static let pixelWidth: CGFloat = 1024
    static let pixelHeight: CGFloat = 28
    /// Как у idle — визуально один темп, проще стыковать.
    static let fps: Double = 12
}

/// Циклическое проигрывание листа печати (пока фаза typing/streaming).
struct GremlinTypingSpriteView: View {
    var displayHeight: CGFloat = GremlinOverlaySpriteMetrics.displayHeight

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / GremlinTypingSheet.fps)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let idx = Int(t * GremlinTypingSheet.fps) % GremlinTypingSheet.frameCount
            GremlinStripSpriteFrameView(
                imageName: "GremlinTypingSheet",
                frameIndex: idx,
                frameCount: GremlinTypingSheet.frameCount,
                pixelWidth: GremlinTypingSheet.pixelWidth,
                pixelHeight: GremlinTypingSheet.pixelHeight,
                displayHeight: displayHeight
            )
        }
    }
}
