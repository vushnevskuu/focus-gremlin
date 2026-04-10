import Foundation

/// Резолвит фазы агента в последовательность кадров: каждый PNG может быть **горизонтальной лентой** (см. `stripCells` в manifest).
@MainActor
final class GremlinCharacterAnimationResolver {
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

    /// Сопоставление поведения:
    /// - idle: ожидание / нейтральный режим
    /// - talking: подготовка к реплике и активная речь
    /// - final: акцент / punchline / предупреждение (в т.ч. вмешательство при отвлечении)
    func resolveFrameSequence(
        phase: BubblePhase,
        distractionInterventionActive: Bool
    ) -> GremlinResolvedFrameSequence {
        for state in Self.preferredStates(for: phase, distractionInterventionActive: distractionInterventionActive) {
            if let resolved = resolveWithFallback(state.rawValue) {
                return resolved
            }
        }
        return builtInIdle()
    }

    nonisolated static func preferredStates(
        for phase: BubblePhase,
        distractionInterventionActive: Bool
    ) -> [GremlinSpriteState] {
        switch phase {
        case .idle:
            return [.idle]
        case .typingDots:
            if distractionInterventionActive {
                return [.final, .talking, .idle]
            }
            return [.talking, .idle]
        case .streaming:
            if distractionInterventionActive {
                return [.talking, .final, .idle]
            }
            return [.talking, .idle]
        case .holding:
            if distractionInterventionActive {
                return [.final, .idle, .talking]
            }
            return [.idle, .talking]
        case .dismissing:
            return [.idle]
        }
    }

    private func resolveState(_ key: String) -> GremlinResolvedFrameSequence? {
        guard let def = manifest.states[key] else { return nil }
        var frames: [GremlinSpriteFrameRef] = []
        frames.reserveCapacity(def.files.count * 8)
        for name in def.files {
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

    private func builtInIdle() -> GremlinResolvedFrameSequence {
        let names = ["idle_1.png", "idle_2.png"]
        var frames: [GremlinSpriteFrameRef] = []
        for name in names {
            guard let url = GremlinSpriteManifestStore.sheetURL(filename: name) else { continue }
            let cells = GremlinSpriteStripConfig.stripCellCount(forFilename: name) ?? 1
            let n = max(1, cells)
            for c in 0 ..< n {
                frames.append(GremlinSpriteFrameRef(url: url, stripCellIndex: c, stripCellCount: n))
            }
        }
        return GremlinResolvedFrameSequence(frames: frames, fps: 12, loops: true)
    }
}
