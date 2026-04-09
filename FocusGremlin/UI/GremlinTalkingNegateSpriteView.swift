import SwiftUI

/// Говорение + отрицательное покачивание головой.
private enum GremlinTalkingNegateSheet {
    static let frameCount = 20
    static let pixelWidth: CGFloat = 1024
    static let pixelHeight: CGFloat = 28
    static let fps: Double = 14
}

struct GremlinTalkingNegateSpriteView: View {
    var displayHeight: CGFloat = GremlinOverlaySpriteMetrics.displayHeight

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / GremlinTalkingNegateSheet.fps)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let idx = Int(t * GremlinTalkingNegateSheet.fps) % GremlinTalkingNegateSheet.frameCount
            GremlinStripSpriteFrameView(
                imageName: "GremlinTalkingNegateSheet",
                frameIndex: idx,
                frameCount: GremlinTalkingNegateSheet.frameCount,
                pixelWidth: GremlinTalkingNegateSheet.pixelWidth,
                pixelHeight: GremlinTalkingNegateSheet.pixelHeight,
                displayHeight: displayHeight
            )
        }
    }
}
