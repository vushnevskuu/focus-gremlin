import Foundation

enum GremlinCharacterSheets {
    static let bundleSubdirectory: String? = nil
}

// MARK: - JSON

struct GremlinSpriteManifestFile: Decodable {
    let character: String
    let renderMode: String?
    let defaultScale: Double?
    let displayHeightPoints: CGFloat?
    /// Если каждый PNG — горизонтальная лента из N кадров, анимация перебирает ячейки 0…N−1 (см. `GremlinSpriteThumbnailLoader`).
    let stripCellsDefault: Int?
    let stripCellsByFile: [String: Int]?
    /// Горизонтально отразить кадры при отрисовке (исправление листа, где персонаж смотрит в другую сторону).
    let horizontalFlipStripByFile: [String: Bool]?
    let states: [String: GremlinFrameSequenceStateDef]
    let fallbacks: [String: String]?
}

struct GremlinFrameSequenceStateDef: Decodable {
    let files: [String]
    let fps: Double
    let loop: Bool
}

// MARK: - Runtime: один кадр = файл + индекс ячейки в горизонтальной ленте (sprite strip)

struct GremlinSpriteFrameRef: Equatable, Hashable {
    let url: URL
    /// Индекс ячейки в пределах [0, stripCellCount).
    let stripCellIndex: Int
    /// Сколько ячеек в ленте для этого файла (1 = целый PNG без нарезки).
    let stripCellCount: Int
}

struct GremlinResolvedFrameSequence: Equatable {
    let frames: [GremlinSpriteFrameRef]
    let fps: Double
    let loops: Bool
    /// Кадры `[0..<loopTailStartIndex)` проигрываются **один раз** с темпом `fps`, затем цикл только по хвосту `[loopTailStartIndex..<count)` с темпом `tailFps` (или `fps`, если `nil`).
    let loopTailStartIndex: Int?
    let tailFps: Double?

    init(
        frames: [GremlinSpriteFrameRef],
        fps: Double,
        loops: Bool,
        loopTailStartIndex: Int? = nil,
        tailFps: Double? = nil
    ) {
        self.frames = frames
        self.fps = fps
        self.loops = loops
        self.loopTailStartIndex = loopTailStartIndex
        self.tailFps = tailFps
    }

    var frameCount: Int { frames.count }
    var duration: TimeInterval { Double(frameCount) / max(fps, 0.01) }

    /// Сколько секунд держать фазу `.streaming` после конца печати, чтобы **один раз** доиграть интро (smile / talking / short_phrase), не обрезая его переходом в `.holding`.
    /// Включает +1 кадр по `fps`, чтобы таймер плеера успел показать последний кадр интро.
    func minimumElapsedInStreamingBeforeHolding() -> TimeInterval {
        let frameSlack = 1.0 / max(fps, 0.01)
        if let tailStart = loopTailStartIndex, tailStart > 0, tailStart < frameCount {
            return Double(tailStart) / max(fps, 0.01) + frameSlack
        }
        let oneLoop = Double(frameCount) / max(fps, 0.01)
        return max(oneLoop, 0.05) + frameSlack
    }

    func frameIndex(at elapsed: TimeInterval) -> Int {
        guard frameCount > 0, fps > 0 else { return 0 }
        if let tailStart = loopTailStartIndex, tailStart > 0, tailStart < frameCount {
            let fTail = tailFps ?? fps
            let introDuration = Double(tailStart) / max(fps, 0.01)
            if elapsed < introDuration {
                let raw = Int(floor(elapsed * fps))
                return min(max(raw, 0), tailStart - 1)
            }
            let tailLen = frameCount - tailStart
            guard tailLen > 0 else { return tailStart - 1 }
            let tTail = elapsed - introDuration
            let rawTail = Int(floor(tTail * max(fTail, 0.01)))
            let m = rawTail % tailLen
            return tailStart + (m < 0 ? m + tailLen : m)
        }
        let raw = Int(floor(elapsed * fps))
        if loops, frameCount > 0 {
            let m = raw % frameCount
            return m < 0 ? m + frameCount : m
        }
        return min(max(raw, 0), max(0, frameCount - 1))
    }
}

enum GremlinSpriteManifestStore {
    private static var cached: GremlinSpriteManifestFile?

    static func load() throws -> GremlinSpriteManifestFile {
        if let cached { return cached }
        let url: URL? = if let sub = GremlinCharacterSheets.bundleSubdirectory {
            Bundle.main.url(forResource: "GremlinSpriteManifest", withExtension: "json", subdirectory: sub)
        } else {
            Bundle.main.url(forResource: "GremlinSpriteManifest", withExtension: "json")
        }
        guard let url else {
            throw NSError(domain: "GremlinSpriteManifest", code: 1, userInfo: [NSLocalizedDescriptionKey: "manifest not in bundle"])
        }
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(GremlinSpriteManifestFile.self, from: data)
        GremlinSpriteStripConfig.apply(manifest: decoded)
        cached = decoded
        return decoded
    }

    static func sheetURL(filename: String) -> URL? {
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension.isEmpty ? "png" : (filename as NSString).pathExtension
        if let sub = GremlinCharacterSheets.bundleSubdirectory {
            return Bundle.main.url(forResource: base, withExtension: ext, subdirectory: sub)
        }
        return Bundle.main.url(forResource: base, withExtension: ext)
    }
}
