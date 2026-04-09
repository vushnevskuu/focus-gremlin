import SwiftUI

/// Рот в камеру / «говорит», когда курсор в центральной зоне экрана.
/// Текущий ассет в репо: полоса **1024×28**. Если заменишь на **1408×64** с **22** кадрами 64×64 — обнови константы.
private enum GremlinTalkingCenterSheet {
    static let frameCount = 20
    static let pixelWidth: CGFloat = 1024
    static let pixelHeight: CGFloat = 28
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
