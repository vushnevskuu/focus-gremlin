import SwiftUI

/// Горизонтальный спрайт «помощник улетает» (один проход, без цикла).
enum GremlinDismissSheet {
    static let frameCount = 19
    static let pixelWidth: CGFloat = 1216
    static let pixelHeight: CGFloat = 128
    static let fps: Double = 14
    /// Длительность полного прохода по кадрам (секунды).
    static var animationDuration: TimeInterval { Double(frameCount) / fps }
}

struct GremlinDismissSpriteView: View {
    var displayHeight: CGFloat = GremlinOverlaySpriteMetrics.displayHeight
    /// Момент перехода в фазу `.dismissing` — от него считаем кадры.
    var startDate: Date

    var body: some View {
        TimelineView(.periodic(from: startDate, by: 1.0 / GremlinDismissSheet.fps)) { context in
            let elapsed = context.date.timeIntervalSince(startDate)
            let raw = Int(elapsed * GremlinDismissSheet.fps)
            let idx = min(max(raw, 0), GremlinDismissSheet.frameCount - 1)
            GremlinStripSpriteFrameView(
                imageName: "GremlinDismissSheet",
                frameIndex: idx,
                frameCount: GremlinDismissSheet.frameCount,
                pixelWidth: GremlinDismissSheet.pixelWidth,
                pixelHeight: GremlinDismissSheet.pixelHeight,
                displayHeight: displayHeight
            )
        }
    }
}
