import SwiftUI

/// Персонаж: кадры из manifest — каждый PNG может быть **горизонтальной лентой** из нескольких спрайтов.
struct GremlinSpriteCharacterView: View {
    @ObservedObject var viewModel: CompanionViewModel

    private static var resolver: GremlinCharacterAnimationResolver? {
        GremlinCharacterAnimationResolver.sharedResolver()
    }

    @State private var playbackEpoch = Date()

    private var displayHeight: CGFloat {
        Self.resolver?.displayHeight() ?? GremlinOverlaySpriteMetrics.displayHeight
    }

    private var sequence: GremlinResolvedFrameSequence? {
        Self.resolver?.resolveFrameSequence(
            phase: viewModel.phase,
            distractionInterventionActive: viewModel.distractionInterventionActive,
            workReturnFinalActive: viewModel.workReturnFinalActive,
            talkingStripFilename: viewModel.activeTalkingStripFilename,
            idleStripFilename: viewModel.activeIdleStripFilename,
            streamTailIdleStripFilename: nil,
            useShortPhraseStream: viewModel.deliveryUsesShortPhraseSprite,
            deliverySpeechStyle: viewModel.deliverySpeechStyle
        )
    }

    /// Ключ плеера: метаданные VM + сигнатура кадров — при любой смене фазы/стиля/листа обязателен сброс таймера NSView.
    private var spritePlaybackIdentity: String {
        let meta = [
            "\(viewModel.phase)",
            "\(viewModel.deliverySpeechStyle)",
            "idle:\(viewModel.activeIdleStripFilename)",
            "talk:\(viewModel.activeTalkingStripFilename)",
            "short:\(viewModel.deliveryUsesShortPhraseSprite)",
            "div:\(viewModel.distractionInterventionActive)",
            "wfin:\(viewModel.workReturnFinalActive)",
            viewModel.typingSpriteEpoch.uuidString
        ].joined(separator: "|")
        guard let seq = sequence, seq.frameCount > 0 else {
            return "empty|\(meta)"
        }
        let part = seq.frames.map { "\($0.url.path)#\($0.stripCellIndex)/\($0.stripCellCount)" }.joined(separator: "\u{1e}")
        let tail = "|tail\(seq.loopTailStartIndex.map(String.init(describing:)) ?? "nil")|tfps\(seq.tailFps.map(String.init(describing:)) ?? "nil")"
        let body = part + "|fps\(seq.fps)|loop\(seq.loops)\(tail)|h\(displayHeight)"
        return "\(meta)\u{1e}\(body)"
    }

    var body: some View {
        Group {
            if let seq = sequence, seq.frameCount > 0 {
                GremlinFrameSequencePlaybackView(
                    sequence: seq,
                    displayHeight: displayHeight,
                    epoch: playbackEpoch,
                    playbackIdentity: spritePlaybackIdentity
                )
            }
        }
        .frame(height: displayHeight)
        .fixedSize(horizontal: true, vertical: false)
        .transaction { $0.animation = nil }
        .animation(nil, value: spritePlaybackIdentity)
        .onChange(of: spritePlaybackIdentity) { _, _ in
            playbackEpoch = Date()
        }
    }
}

private struct GremlinFrameSequencePlaybackView: View {
    let sequence: GremlinResolvedFrameSequence
    var displayHeight: CGFloat
    var epoch: Date
    var playbackIdentity: String

    var body: some View {
        GremlinNativeSequencePlayerRepresentable(
            frames: sequence.frames,
            fps: sequence.fps,
            loops: sequence.loops,
            loopTailStartIndex: sequence.loopTailStartIndex,
            tailFps: sequence.tailFps,
            displayHeight: displayHeight,
            animationEpoch: epoch,
            playbackIdentity: playbackIdentity
        )
        .fixedSize()
        .frame(height: displayHeight)
    }
}
