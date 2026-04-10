import SwiftUI

/// «Говорит», голова вправу — когда курсор в правой зоне экрана.
private enum GremlinTalkingRightSheet {
    static let frameCount = 20
    static let pixelWidth: CGFloat = 1280
    static let pixelHeight: CGFloat = 128
    static let fps: Double = 14
}

struct GremlinTalkingRightSpriteView: View {
    var displayHeight: CGFloat = GremlinOverlaySpriteMetrics.displayHeight

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / GremlinTalkingRightSheet.fps)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let idx = Int(t * GremlinTalkingRightSheet.fps) % GremlinTalkingRightSheet.frameCount
            GremlinStripSpriteFrameView(
                imageName: "GremlinTalkingRightSheet",
                frameIndex: idx,
                frameCount: GremlinTalkingRightSheet.frameCount,
                pixelWidth: GremlinTalkingRightSheet.pixelWidth,
                pixelHeight: GremlinTalkingRightSheet.pixelHeight,
                displayHeight: displayHeight
            )
        }
    }
}
