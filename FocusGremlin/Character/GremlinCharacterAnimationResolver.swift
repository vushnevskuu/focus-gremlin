import Foundation

/// Резолвит фазы агента в последовательность кадров: каждый PNG может быть **горизонтальной лентой** (см. `stripCells` в manifest).
@MainActor
final class GremlinCharacterAnimationResolver {
    private static let transitionLeadFrameCount = 6

    private static var sharedCached: GremlinCharacterAnimationResolver?

    /// Один экземпляр на процесс: `CompanionViewModel` не теряет расчёт длительности речи, если `try?` на init вдруг даст nil.
    static func sharedResolver() -> GremlinCharacterAnimationResolver? {
        if let s = sharedCached { return s }
        guard let r = try? GremlinCharacterAnimationResolver() else { return nil }
        sharedCached = r
        return r
    }

    private let manifest: GremlinSpriteManifestFile
    private let fallbacks: [String: String]

    init(manifest: GremlinSpriteManifestFile) {
        self.manifest = manifest
        self.fallbacks = manifest.fallbacks ?? [:]
    }

    convenience init() throws {
        try self.init(manifest: GremlinSpriteManifestStore.load())
    }

    func displayHeight() -> CGFloat {
        manifest.displayHeightPoints ?? GremlinOverlaySpriteMetrics.displayHeight
    }

    /// Все уникальные кадры из состояний манифеста (idle → talking → final) для фонового прогрева ImageIO-кэша до первого показа.
    func allManifestFrameRefsForWarmup() -> [GremlinSpriteFrameRef] {
        var seen = Set<GremlinSpriteFrameRef>()
        var ordered: [GremlinSpriteFrameRef] = []
        ordered.reserveCapacity(220)
        for st in GremlinSpriteState.allCases {
            guard let seq = resolveState(st.rawValue) else { continue }
            for fr in seq.frames where !seen.contains(fr) {
                seen.insert(fr)
                ordered.append(fr)
            }
        }
        return ordered
    }

    /// Сопоставление поведения:
    /// - `.appearing`: короткий не-looping lead-in из `idle`, а проявление даёт SwiftUI transition
    /// - `.typingDots`: в живой доставке не используется (точки показываются при `.streaming` и пустом тексте); для API — `idle`.
    /// - `.holding` / `.textFalling`: `idle` из `streamTailIdleStripFilename` при передаче, иначе из `idleStripFilename`.
    /// - `.streaming`: `smile` и `talking_*` идут один раз вперёд и сразу назад, затем цикл `idle`; `short_phrase` — один проход вперёд, затем `idle`
    /// - `.textFalling` и далее — idle
    /// - `.dismissing`: короткий обратный lead-out из `idle` поверх fade/scale исчезновения
    /// - `workReturnFinalActive`: полный `final` как терминальный финал сценария
    /// - Parameter talkingStripFilename: для состояния `talking` — один лист из манифеста (например `talking_2.png`); `nil` = все листы подряд (как раньше).
    /// - Parameter idleStripFilename: для `idle` в паузах, lead-in/out, holding — выбранный лист (`idle_1` / `idle_2`).
    /// - Parameter streamTailIdleStripFilename: хвост композита «речь → idle» во время `.streaming`. `nil` = тот же лист, что `idleStripFilename` (например `idle_2` при реакции на страницу).
    /// - Parameter useShortPhraseStream: реплика из 1–2 слов — лента `short_phrase` вместо `talking_*` (если не смех).
    /// - Parameter deliverySpeechStyle: при `.giggle` — лента `smile` (важнее короткой фразы).
    /// - Parameter idleSinglePass: если `true`, фоновый `idle` без зацикливания (один проход листа — реакция на новую ссылку).
    func resolveFrameSequence(
        phase: BubblePhase,
        distractionInterventionActive: Bool,
        workReturnFinalActive: Bool = false,
        ambientSpitActive: Bool = false,
        talkingStripFilename: String? = nil,
        idleStripFilename: String? = nil,
        streamTailIdleStripFilename: String? = nil,
        useShortPhraseStream: Bool = false,
        deliverySpeechStyle: GremlinDeliverySpeechStyle = .spatial,
        idleSinglePass: Bool = false
    ) -> GremlinResolvedFrameSequence {
        if workReturnFinalActive, phase == .idle {
            if let resolved = resolveTerminalFinalSequence() {
                return resolved
            }
        }
        if phase == .appearing, let resolved = resolveAppearanceSequence(idleStripFilename: idleStripFilename) {
            return resolved
        }
        if phase == .dismissing, let resolved = resolveDismissSequence(idleStripFilename: idleStripFilename) {
            return resolved
        }
        let idleLoopOverride: Bool? = idleSinglePass ? false : nil
        if ambientSpitActive,
           phase == .idle,
           let composite = resolveAmbientSpitOnceThenIdle(tailIdleFilename: idleStripFilename) {
            return composite
        }
        if phase == .streaming {
            let tailIdle = streamTailIdleStripFilename ?? idleStripFilename
            if deliverySpeechStyle == .giggle,
               let composite = resolveStreamingSmileOnceThenIdle(tailIdleFilename: tailIdle) {
                return composite
            }
            if useShortPhraseStream,
               let composite = resolveStreamingShortPhraseOnceThenIdle(tailIdleFilename: tailIdle) {
                return composite
            }
            if let composite = resolveStreamingTalkingOnceThenIdle(
                talkingStripFilename: talkingStripFilename,
                tailIdleFilename: tailIdle
            ) {
                return composite
            }
        }
        let ambientIdle: String? = {
            switch phase {
            case .holding, .textFalling:
                return streamTailIdleStripFilename ?? idleStripFilename
            default:
                return idleStripFilename
            }
        }()

        for state in Self.preferredStates(for: phase, distractionInterventionActive: distractionInterventionActive) {
            if state == .talking {
                if let resolved = resolveTalkingState(preferredStripFilename: talkingStripFilename) {
                    return resolved
                }
            } else if state == .idle {
                if let resolved = resolveIdleState(preferredStripFilename: ambientIdle, loopsOverride: idleLoopOverride) {
                    return resolved
                }
            } else if let resolved = resolveNonTerminalState(state.rawValue) {
                return resolved
            }
        }
        return builtInIdle(loopsOverride: idleLoopOverride)
    }

    /// Длительность одного прохода всех кадров выбранного листа `idle` (для таймера после смены URL).
    func durationOfOneIdleStripPass(preferredStripFilename: String?) -> TimeInterval? {
        guard let seq = resolveIdleState(preferredStripFilename: preferredStripFilename, loopsOverride: false) else { return nil }
        return seq.duration
    }

    /// Длительность интро `spit` в композите (пинг-понг, как у talking), без idle-хвоста.
    func durationOfOneSpitPass() -> TimeInterval? {
        guard let spitSeq = resolveState(GremlinSpriteState.spit.rawValue), !spitSeq.frames.isEmpty else { return nil }
        let intro = mirroredIntroFrames(spitSeq.frames)
        return Double(intro.count) / max(spitSeq.fps, 0.01)
    }

    /// Цепочка состояний для повседневных фаз пузырька. Терминальный `final` здесь не участвует.
    nonisolated static func preferredStates(
        for phase: BubblePhase,
        distractionInterventionActive: Bool
    ) -> [GremlinSpriteState] {
        switch phase {
        case .idle:
            return [.idle]
        case .typingDots:
            return [.idle]
        case .streaming:
            return [.talking, .idle]
        case .holding:
            return [.idle]
        case .textFalling:
            return [.idle]
        case .appearing, .dismissing:
            return [.idle]
        }
    }

    /// Разрешить только `idle` / `talking` и их fallbacks из манифеста (без ключа `final`).
    private func resolveNonTerminalState(_ key: String) -> GremlinResolvedFrameSequence? {
        guard key != GremlinSpriteState.final.rawValue else { return nil }
        var k = key
        var seen = Set<String>()
        while !seen.contains(k) {
            seen.insert(k)
            guard k != GremlinSpriteState.final.rawValue else { break }
            if let seq = resolveState(k) { return seq }
            guard let next = fallbacks[k] else { break }
            guard next != GremlinSpriteState.final.rawValue else { break }
            k = next
        }
        return nil
    }

    /// Явное разрешение терминальной ленты `final` — **только** `final`, без fallback на `talking` из манифеста (иначе вместо финала крутится речь).
    private func resolveTerminalFinalSequence() -> GremlinResolvedFrameSequence? {
        resolveState(GremlinSpriteState.final.rawValue)
    }

    private func resolveAppearanceSequence(idleStripFilename: String?) -> GremlinResolvedFrameSequence? {
        resolveIdleLeadSequence(reversed: false, idleStripFilename: idleStripFilename)
    }

    private func resolveDismissSequence(idleStripFilename: String?) -> GremlinResolvedFrameSequence? {
        resolveIdleLeadSequence(reversed: true, idleStripFilename: idleStripFilename)
    }

    private func resolveIdleLeadSequence(reversed: Bool, idleStripFilename: String?) -> GremlinResolvedFrameSequence? {
        guard let seq = resolveIdleState(preferredStripFilename: idleStripFilename, loopsOverride: nil) else { return nil }
        let leadCount = min(Self.transitionLeadFrameCount, seq.frameCount)
        guard leadCount > 0 else { return nil }
        let lead = Array(seq.frames.prefix(leadCount))
        return GremlinResolvedFrameSequence(
            frames: reversed ? Array(lead.reversed()) : lead,
            fps: seq.fps,
            loops: false
        )
    }

    private func resolveState(_ key: String) -> GremlinResolvedFrameSequence? {
        guard let def = manifest.states[key] else { return nil }
        return buildFrames(for: def, fileNames: def.files)
    }

    /// Одна случайная «говорящая» лента за реплику или все листы, если `preferredStripFilename == nil`.
    private func resolveTalkingState(preferredStripFilename: String?) -> GremlinResolvedFrameSequence? {
        guard let def = manifest.states[GremlinSpriteState.talking.rawValue] else { return nil }
        let names: [String]
        if let p = preferredStripFilename, def.files.contains(p) {
            names = [p]
        } else {
            names = def.files
        }
        return buildFrames(for: def, fileNames: names)
    }

    /// Один лист `idle` из манифеста; при `nil` — первый файл (стабильные тесты и fallback).
    /// - Parameter loopsOverride: `false` — один проход без цикла; `nil` — как в манифесте.
    private func resolveIdleState(preferredStripFilename: String?, loopsOverride: Bool? = nil) -> GremlinResolvedFrameSequence? {
        guard let def = manifest.states[GremlinSpriteState.idle.rawValue], let first = def.files.first else { return nil }
        let names: [String]
        if let p = preferredStripFilename, def.files.contains(p) {
            names = [p]
        } else {
            names = [first]
        }
        guard let built = buildFrames(for: def, fileNames: names) else { return nil }
        guard let o = loopsOverride else { return built }
        return GremlinResolvedFrameSequence(
            frames: built.frames,
            fps: built.fps,
            loops: o,
            loopTailStartIndex: built.loopTailStartIndex,
            tailFps: built.tailFps
        )
    }

    /// Смех: один раз `smile` вперёд и сразу назад, затем idle (хвост — `tailIdleFilename`, обычно idle_1).
    private func resolveStreamingSmileOnceThenIdle(tailIdleFilename: String?) -> GremlinResolvedFrameSequence? {
        guard let smileSeq = resolveState(GremlinSpriteState.smile.rawValue),
              let idleSeq = resolveIdleState(preferredStripFilename: tailIdleFilename, loopsOverride: nil),
              !smileSeq.frames.isEmpty,
              !idleSeq.frames.isEmpty
        else { return nil }
        let introFrames = mirroredIntroFrames(smileSeq.frames)
        let introFps = max(smileSeq.fps, 0.01)
        let tailFps = max(idleSeq.fps, 0.01)
        let tailStart = introFrames.count
        return GremlinResolvedFrameSequence(
            frames: introFrames + idleSeq.frames,
            fps: introFps,
            loops: true,
            loopTailStartIndex: tailStart,
            tailFps: tailFps
        )
    }

    /// Плевок между репликами: лента `spit` **вперёд и назад** (как talking), затем цикл idle.
    private func resolveAmbientSpitOnceThenIdle(tailIdleFilename: String?) -> GremlinResolvedFrameSequence? {
        guard let spitSeq = resolveState(GremlinSpriteState.spit.rawValue),
              let idleSeq = resolveIdleState(preferredStripFilename: tailIdleFilename, loopsOverride: nil),
              !spitSeq.frames.isEmpty,
              !idleSeq.frames.isEmpty
        else { return nil }
        let introFrames = mirroredIntroFrames(spitSeq.frames)
        let introFps = max(spitSeq.fps, 0.01)
        let tailFps = max(idleSeq.fps, 0.01)
        let tailStart = introFrames.count
        return GremlinResolvedFrameSequence(
            frames: introFrames + idleSeq.frames,
            fps: introFps,
            loops: true,
            loopTailStartIndex: tailStart,
            tailFps: tailFps
        )
    }

    /// Печать 1–2 слова: один раз `short_phrase`, затем idle.
    private func resolveStreamingShortPhraseOnceThenIdle(tailIdleFilename: String?) -> GremlinResolvedFrameSequence? {
        guard let phraseSeq = resolveState(GremlinSpriteState.shortPhrase.rawValue),
              let idleSeq = resolveIdleState(preferredStripFilename: tailIdleFilename, loopsOverride: nil),
              !phraseSeq.frames.isEmpty,
              !idleSeq.frames.isEmpty
        else { return nil }
        let introFps = max(phraseSeq.fps, 0.01)
        let tailFps = max(idleSeq.fps, 0.01)
        let tailStart = phraseSeq.frames.count
        return GremlinResolvedFrameSequence(
            frames: phraseSeq.frames + idleSeq.frames,
            fps: introFps,
            loops: true,
            loopTailStartIndex: tailStart,
            tailFps: tailFps
        )
    }

    /// Печать: один раз вся talking-лента (выбранный лист) вперёд и сразу назад, дальше только idle по кругу.
    private func resolveStreamingTalkingOnceThenIdle(talkingStripFilename: String?, tailIdleFilename: String?) -> GremlinResolvedFrameSequence? {
        guard let talkingSeq = resolveTalkingState(preferredStripFilename: talkingStripFilename),
              let idleSeq = resolveIdleState(preferredStripFilename: tailIdleFilename, loopsOverride: nil),
              !talkingSeq.frames.isEmpty,
              !idleSeq.frames.isEmpty
        else { return nil }
        let introFrames = mirroredIntroFrames(talkingSeq.frames)
        let introFps = max(talkingSeq.fps, 0.01)
        let tailFps = max(idleSeq.fps, 0.01)
        let tailStart = introFrames.count
        return GremlinResolvedFrameSequence(
            frames: introFrames + idleSeq.frames,
            fps: introFps,
            loops: true,
            loopTailStartIndex: tailStart,
            tailFps: tailFps
        )
    }

    private func mirroredIntroFrames(_ frames: [GremlinSpriteFrameRef]) -> [GremlinSpriteFrameRef] {
        guard !frames.isEmpty else { return frames }
        if frames.count == 1 {
            // Одна ячейка в ленте: «туда-обратно» дало бы один кадр ≈ 1/fps — визуально «не играет».
            let f = frames[0]
            return [f, f, f, f]
        }
        return frames + Array(frames.dropLast().reversed())
    }

    private func buildFrames(for def: GremlinFrameSequenceStateDef, fileNames: [String]) -> GremlinResolvedFrameSequence? {
        var frames: [GremlinSpriteFrameRef] = []
        frames.reserveCapacity(fileNames.count * 8)
        for name in fileNames {
            guard let url = GremlinSpriteManifestStore.sheetURL(filename: name) else { return nil }
            let cells = GremlinSpriteStripConfig.stripCellCount(forFilename: name) ?? 1
            let n = max(1, cells)
            for c in 0 ..< n {
                frames.append(GremlinSpriteFrameRef(url: url, stripCellIndex: c, stripCellCount: n))
            }
        }
        guard !frames.isEmpty else { return nil }
        let fps = max(def.fps, 0.01)
        return GremlinResolvedFrameSequence(frames: frames, fps: fps, loops: def.loop)
    }

    private func resolveWithFallback(_ key: String) -> GremlinResolvedFrameSequence? {
        var k = key
        var seen = Set<String>()
        while !seen.contains(k) {
            seen.insert(k)
            if let seq = resolveState(k) { return seq }
            guard let next = fallbacks[k] else { break }
            k = next
        }
        return nil
    }

    private func builtInIdle(loopsOverride: Bool? = nil) -> GremlinResolvedFrameSequence {
        let names = ["idle_1.png"]
        var frames: [GremlinSpriteFrameRef] = []
        for name in names {
            guard let url = GremlinSpriteManifestStore.sheetURL(filename: name) else { continue }
            let cells = GremlinSpriteStripConfig.stripCellCount(forFilename: name) ?? 1
            let n = max(1, cells)
            for c in 0 ..< n {
                frames.append(GremlinSpriteFrameRef(url: url, stripCellIndex: c, stripCellCount: n))
            }
        }
        let loop = loopsOverride ?? true
        return GremlinResolvedFrameSequence(frames: frames, fps: 12, loops: loop)
    }
}
