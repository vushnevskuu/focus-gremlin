import AppKit
import Dispatch
import SwiftUI

/// Воспроизведение последовательности кадров **внутри AppKit**, без `TimelineView` (иначе SwiftUI пересобирает дерево десятки раз в секунду и всё лагает).
final class GremlinNativeSequencePlayerView: NSView {
    private let imageView = GremlinDiscreteFrameImageView(frame: .zero)
    /// `Timer` на главном RunLoop иногда «залипает» во время spring-анимаций SwiftUI рядом; `DispatchSourceTimer` стабильнее.
    private var tickSource: DispatchSourceTimer?
    private var frames: [GremlinSpriteFrameRef] = []
    private var fps: Double = 12
    private var loops: Bool = true
    private var loopTailStartIndex: Int?
    private var tailFps: Double?
    private var displayHeight: CGFloat = 120
    private var epochStart: CFAbsoluteTime = 0
    /// Пауза кадров (окно настроек на переднем плане — не крутить спрайт впустую).
    private var tickerSuspended = false
    /// `DispatchSourceTimer` создаётся уже с suspension count = 1; без флага легко сделать лишний `resume()` или `suspend()`.
    private var tickerDidResume = false

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        cancelTickSourceSafely()
    }

    /// `cancel()` на приостановленном `DispatchSource` даёт «Release of a suspended object» — сначала балансируем suspend-count.
    private func cancelTickSourceSafely() {
        guard let src = tickSource else { return }
        tickSource = nil
        if !tickerDidResume {
            src.resume()
        }
        src.cancel()
        tickerDidResume = false
    }

    func configure(
        frames: [GremlinSpriteFrameRef],
        fps: Double,
        loops: Bool,
        loopTailStartIndex: Int?,
        tailFps: Double?,
        displayHeight: CGFloat,
        restartClock: Bool
    ) {
        cancelTickSourceSafely()

        self.frames = frames
        self.fps = max(fps, 0.01)
        self.loops = loops
        self.loopTailStartIndex = loopTailStartIndex
        self.tailFps = tailFps.map { max($0, 0.01) }
        self.displayHeight = displayHeight

        guard !frames.isEmpty else {
            needsLayout = true
            return
        }

        if restartClock {
            epochStart = CFAbsoluteTimeGetCurrent()
        }

        if let first = frames.first {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            imageView.configure(
                frame: first,
                displayHeight: displayHeight,
                allowSynchronousLoad: true
            )
            CATransaction.commit()
        }

        let maxFps = max(self.fps, self.tailFps ?? self.fps)
        let interval = 1.0 / maxFps
        let src = DispatchSource.makeTimerSource(queue: .main)
        src.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(1))
        src.setEventHandler { [weak self] in
            self?.tick()
        }
        tickSource = src
        applyTickerSuspension()

        tick()
    }

    func setTickerSuspended(_ suspended: Bool) {
        guard suspended != tickerSuspended else { return }
        tickerSuspended = suspended
        applyTickerSuspension()
    }

    private func applyTickerSuspension() {
        guard let src = tickSource else { return }
        if tickerSuspended {
            guard tickerDidResume else { return }
            src.suspend()
            tickerDidResume = false
        } else {
            guard !tickerDidResume else { return }
            src.resume()
            tickerDidResume = true
        }
    }

    private func frameIndex(elapsed: TimeInterval) -> Int {
        let seq = GremlinResolvedFrameSequence(
            frames: frames,
            fps: fps,
            loops: loops,
            loopTailStartIndex: loopTailStartIndex,
            tailFps: tailFps
        )
        return seq.frameIndex(at: elapsed)
    }

    private func tick() {
        guard !frames.isEmpty else { return }
        let elapsed = CFAbsoluteTimeGetCurrent() - epochStart
        let idx = frameIndex(elapsed: elapsed)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageView.configure(frame: frames[idx], displayHeight: displayHeight)
        CATransaction.commit()
        // Не инвалидируем intrinsic на каждом кадре — размер ячейки ленты не меняется; иначе SwiftUI/AppKit перелэйаутят оверлей ~12×/с и рвётся плавность курсора.
    }

    override var intrinsicContentSize: NSSize {
        imageView.intrinsicContentSize
    }
}

struct GremlinNativeSequencePlayerRepresentable: NSViewRepresentable {
    var frames: [GremlinSpriteFrameRef]
    var fps: Double
    var loops: Bool
    var loopTailStartIndex: Int?
    var tailFps: Double?
    var displayHeight: CGFloat
    var animationEpoch: Date
    /// Синхронизация с SwiftUI: смена фазы/стиля листа должна сбрасывать плеер даже при редких совпадениях кадров.
    var playbackIdentity: String
    var suspendSpriteTicker: Bool

    final class Coordinator {
        var contentKey: String?
        var epochSeconds: TimeInterval = 0
        var prefetchKey: String?
        var suspendSpriteTicker = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> GremlinNativeSequencePlayerView {
        GremlinNativeSequencePlayerView(frame: .zero)
    }

    func updateNSView(_ nsView: GremlinNativeSequencePlayerView, context: Context) {
        let c = context.coordinator
        if c.suspendSpriteTicker != suspendSpriteTicker {
            c.suspendSpriteTicker = suspendSpriteTicker
            nsView.setTickerSuspended(suspendSpriteTicker)
        }

        let ck = Self.contentSignature(
            frames: frames,
            fps: fps,
            loops: loops,
            loopTailStartIndex: loopTailStartIndex,
            tailFps: tailFps,
            displayHeight: displayHeight,
            playbackIdentity: playbackIdentity
        )
        let ep = animationEpoch.timeIntervalSinceReferenceDate

        if let ok = c.contentKey, ok == ck, abs(c.epochSeconds - ep) < 1e-9 {
            return
        }

        let restart = c.contentKey != ck || abs(c.epochSeconds - ep) > 1e-9
        c.contentKey = ck
        c.epochSeconds = ep

        if c.prefetchKey != ck {
            c.prefetchKey = ck
            let warmupCount = min(frames.count, max(12, Int(ceil(max(fps, 1)))))
            let warmup = Array(frames.prefix(warmupCount))
            GremlinSpriteThumbnailLoader.prefetch(frames: warmup, displayHeight: displayHeight, priority: .userInitiated)
            if frames.count > warmupCount {
                GremlinSpriteThumbnailLoader.prefetch(
                    frames: Array(frames.dropFirst(warmupCount)),
                    displayHeight: displayHeight,
                    priority: .utility
                )
            }
        }

        nsView.configure(
            frames: frames,
            fps: fps,
            loops: loops,
            loopTailStartIndex: loopTailStartIndex,
            tailFps: tailFps,
            displayHeight: displayHeight,
            restartClock: restart
        )
    }

    private static func contentSignature(
        frames: [GremlinSpriteFrameRef],
        fps: Double,
        loops: Bool,
        loopTailStartIndex: Int?,
        tailFps: Double?,
        displayHeight: CGFloat,
        playbackIdentity: String
    ) -> String {
        let part = frames.map { "\($0.url.path)#\($0.stripCellIndex)/\($0.stripCellCount)" }.joined(separator: "\u{1e}")
        let tail = "|tail\(loopTailStartIndex.map(String.init(describing:)) ?? "nil")|tfps\(tailFps.map(String.init(describing:)) ?? "nil")"
        return part + "|fps\(fps)|loop\(loops)\(tail)|h\(displayHeight)|pid:\(playbackIdentity)"
    }
}
