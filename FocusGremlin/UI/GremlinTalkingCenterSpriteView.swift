import SwiftUI

/// Рот в камеру / «говорит», когда курсор в центральной зоне экрана.
/// Горизонтальный лист: `pixelWidth` = `frameCount` × ширина кадра в px (сейчас 64).
private enum GremlinTalkingCenterSheet {
    static let frameCount = 20
    static let pixelWidth: CGFloat = 1280
    static let pixelHeight: CGFloat = 128
    static let fps: Double = 14
}

struct GremlinTalkingCenterSpriteView: View {
    var displayHeight: CGFloat = GremlinOverlaySpriteMetrics.displayHeight

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / GremlinTalkingCenterSheet.fps)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let idx = Int(t * GremlinTalkingCenterSheet.fps) % GremlinTalkingCenterSheet.frameCount
            GremlinStripSpriteFrameView(
                imageName: "GremlinTalkingCenterSheet",
                frameIndex: idx,
                frameCount: GremlinTalkingCenterSheet.frameCount,
                pixelWidth: GremlinTalkingCenterSheet.pixelWidth,
                pixelHeight: GremlinTalkingCenterSheet.pixelHeight,
                displayHeight: displayHeight
            )
        }
    }
}
