import SwiftUI

/// Персонаж: кадры из manifest — каждый файл может быть **лентой** из нескольких спрайтов.
struct GremlinSpriteCharacterView: View {
    @ObservedObject var viewModel: CompanionViewModel

    private static let resolver: GremlinCharacterAnimationResolver? = try? GremlinCharacterAnimationResolver()

    @State private var playbackEpoch = Date()

    private var displayHeight: CGFloat {
        Self.resolver?.displayHeight() ?? GremlinOverlaySpriteMetrics.displayHeight
    }

    private var sequence: GremlinResolvedFrameSequence? {
        Self.resolver?.resolveFrameSequence(
            phase: viewModel.phase,
            distractionInterventionActive: viewModel.distractionInterventionActive
        )
    }

    private var sequenceIdentity: String {
        "\(viewModel.phase)-\(viewModel.distractionInterventionActive)-\(viewModel.typingSpriteEpoch.uuidString)"
    }

    var body: some View {
        Group {
            if let seq = sequence, seq.frameCount > 0 {
                if viewModel.isInteractionFocusedOnMainAppWindow {
                    GremlinDiscreteFrameImageRepresentable(frame: seq.frames[0], displayHeight: displayHeight)
                        .fixedSize()
                        .frame(height: displayHeight)
                } else {
                    GremlinFrameSequencePlaybackView(
                        sequence: seq,
                        displayHeight: displayHeight,
                        epoch: playbackEpoch
                    )
                }
            }
        }
        .frame(height: displayHeight)
        .fixedSize(horizontal: true, vertical: false)
        .animation(nil, value: sequenceIdentity)
        .onChange(of: sequenceIdentity) { _, _ in
            playbackEpoch = Date()
        }
        .onChange(of: viewModel.typingSpriteEpoch) { _, _ in
            playbackEpoch = Date()
        }
    }
}

private struct GremlinFrameSequencePlaybackView: View {
    let sequence: GremlinResolvedFrameSequence
    var displayHeight: CGFloat
    var epoch: Date

    private var prefetchTaskID: String {
        sequence.frames.map { "\($0.url.path)#\($0.stripCellIndex)/\($0.stripCellCount)" }.joined(separator: "\u{1e}")
            + "#\(displayHeight)"
    }

    var body: some View {
        TimelineView(.periodic(from: epoch, by: 1.0 / max(sequence.fps, 0.01))) { context in
            let elapsed = context.date.timeIntervalSince(epoch)
            let idx = sequence.frameIndex(at: elapsed)
            let fr = sequence.frames[idx]
            GremlinDiscreteFrameImageRepresentable(frame: fr, displayHeight: displayHeight)
                .fixedSize()
                .frame(height: displayHeight)
        }
        .transaction { $0.animation = nil }
        .task(id: prefetchTaskID) {
            let warmupFrameCount = min(sequence.frameCount, max(12, Int(ceil(max(sequence.fps, 1)))))
            let warmupFrames = Array(sequence.frames.prefix(warmupFrameCount))
            GremlinSpriteThumbnailLoader.prefetch(
                frames: warmupFrames,
                displayHeight: displayHeight,
                priority: .userInitiated
            )

            if sequence.frameCount > warmupFrameCount {
                let remainingFrames = Array(sequence.frames.dropFirst(warmupFrameCount))
                GremlinSpriteThumbnailLoader.prefetch(
                    frames: remainingFrames,
                    displayHeight: displayHeight,
                    priority: .utility
                )
            }
        }
    }
}
