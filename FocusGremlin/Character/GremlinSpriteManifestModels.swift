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

    var frameCount: Int { frames.count }

    func frameIndex(at elapsed: TimeInterval) -> Int {
        guard frameCount > 0, fps > 0 else { return 0 }
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
