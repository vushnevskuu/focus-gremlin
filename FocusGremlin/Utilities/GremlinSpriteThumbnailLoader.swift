import AppKit
import CoreGraphics
import Foundation
import ImageIO

/// Глобальные подсказки: каждый PNG может быть горизонтальной лентой из `n` кадров (кадр = `stripCellIndex`).
enum GremlinSpriteStripConfig {
    /// Если `nil`, широкие полосы не режем (только thumbnail целого файла).
    static var defaultStripCells: Int?
    static var cellsByFilename: [String: Int] = [:]

    static func apply(manifest: GremlinSpriteManifestFile) {
        defaultStripCells = manifest.stripCellsDefault
        cellsByFilename = manifest.stripCellsByFile ?? [:]
    }

    static func stripCellCount(forFilename name: String) -> Int? {
        if let o = cellsByFilename[name] { return max(1, o) }
        guard let d = defaultStripCells else { return nil }
        return max(1, d)
    }
}

/// Декод с ImageIO: thumbnail целого файла или **конкретной ячейки** горизонтальной ленты.
enum GremlinSpriteThumbnailLoader {
    private static let cache = NSCache<NSString, CGImage>()
    private static let cacheLock = NSLock()
    private static var sourceSizeCache: [NSString: CGSize] = [:]

    static func maxPixelDimension(forDisplayHeightPoints height: CGFloat) -> Int {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        return max(256, min(640, Int(ceil(height * scale * 2))))
    }

    static func cgImage(
        url: URL,
        maxPixelDimension: Int,
        stripCellCount: Int? = nil,
        stripCellIndex: Int = 0
    ) -> CGImage? {
        let strip = stripCellCount ?? 0
        let cell = strip > 1 ? min(max(stripCellIndex, 0), strip - 1) : 0
        let key = "\(url.path)#\(maxPixelDimension)#strip\(strip)#c\(cell)" as NSString
        cacheLock.lock()
        if let hit = cache.object(forKey: key) {
            cacheLock.unlock()
            return hit
        }
        cacheLock.unlock()

        guard let src = CGImageSourceCreateWithURL(url as CFURL, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else { return nil }

        let cg: CGImage?
        if let n = stripCellCount, n > 1,
           let stripped = extractStripCell(from: src, stripCells: n, cellIndex: cell, maxPixelDimension: maxPixelDimension) {
            cg = stripped
        } else {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]
            cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
        }

        guard let cg else { return nil }
        cacheLock.lock()
        cache.setObject(cg, forKey: key, cost: cg.width * cg.height * 4)
        cacheLock.unlock()
        return cg
    }

    static func logicalFramePixelSize(url: URL, stripCellCount: Int? = nil) -> CGSize? {
        guard let sourceSize = sourcePixelSize(url: url) else { return nil }
        let cells = max(1, stripCellCount ?? 1)
        return CGSize(width: sourceSize.width / CGFloat(cells), height: sourceSize.height)
    }

    /// Только кэш, без декода (для мгновенной смены кадра без мигания).
    static func imageIfCached(
        url: URL,
        maxPixelDimension: Int,
        stripCellCount: Int? = nil,
        stripCellIndex: Int = 0
    ) -> CGImage? {
        let strip = stripCellCount ?? 0
        let cell = strip > 1 ? min(max(stripCellIndex, 0), strip - 1) : 0
        let key = "\(url.path)#\(maxPixelDimension)#strip\(strip)#c\(cell)" as NSString
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cache.object(forKey: key)
    }

    /// Прогрев кэша (низкий приоритет, с уступками планировщику — чтобы не забивать диск и UI).
    static func prefetch(frames: [GremlinSpriteFrameRef], displayHeight: CGFloat) {
        prefetch(frames: frames, displayHeight: displayHeight, priority: .utility)
    }

    static func prefetch(
        frames: [GremlinSpriteFrameRef],
        displayHeight: CGFloat,
        priority: TaskPriority
    ) {
        let maxPx = maxPixelDimension(forDisplayHeightPoints: displayHeight)
        Task.detached(priority: priority) {
            for (i, fr) in frames.enumerated() {
                let strip = fr.stripCellCount > 1 ? fr.stripCellCount : nil
                _ = cgImage(
                    url: fr.url,
                    maxPixelDimension: maxPx,
                    stripCellCount: strip,
                    stripCellIndex: fr.stripCellIndex
                )
                if i & 3 == 3 {
                    await Task.yield()
                }
            }
        }
    }

    /// Одна ячейка горизонтальной ленты; декод с прореживанием по полной ширине, кроп как в `GremlinSpriteStripDrawingView`.
    private static func extractStripCell(
        from src: CGImageSource,
        stripCells: Int,
        cellIndex: Int,
        maxPixelDimension: Int
    ) -> CGImage? {
        guard stripCells > 1 else { return nil }
        let idx = min(max(cellIndex, 0), stripCells - 1)
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let wAny = props[kCGImagePropertyPixelWidth],
              let hAny = props[kCGImagePropertyPixelHeight]
        else { return nil }

        let iw = (wAny as? NSNumber)?.intValue ?? (wAny as? Int) ?? 0
        let ih = (hAny as? NSNumber)?.intValue ?? (hAny as? Int) ?? 0
        guard iw > 0, ih > 0, iw > ih * 2 else { return nil }

        let subsample = max(1, min(32, iw / max(256, stripCells * 64)))
        let decodeOpts: [CFString: Any] = [
            kCGImageSourceSubsampleFactor: subsample,
            kCGImageSourceShouldCache: false
        ]
        guard let decoded = CGImageSourceCreateImageAtIndex(src, 0, decodeOpts as CFDictionary) else { return nil }

        let dw = decoded.width
        let dh = decoded.height
        guard dw > 0, dh > 0 else { return nil }

        let frameWIdeal = CGFloat(dw) / CGFloat(stripCells)
        let sx = Int(floor(CGFloat(idx) * frameWIdeal))
        let nextStart = idx + 1 < stripCells ? Int(floor(CGFloat(idx + 1) * frameWIdeal)) : dw
        let cw = max(1, nextStart - sx)
        guard let cell = decoded.cropping(to: CGRect(x: sx, y: 0, width: cw, height: dh)) else { return nil }
        return scaleToMaxDimension(cell, maxPx: maxPixelDimension)
    }

    private static func scaleToMaxDimension(_ image: CGImage, maxPx: Int) -> CGImage? {
        let iw = image.width
        let ih = image.height
        guard iw > 0, ih > 0 else { return image }
        let scale = min(1, CGFloat(maxPx) / CGFloat(max(iw, ih)))
        let tw = max(1, Int((CGFloat(iw) * scale).rounded(.down)))
        let th = max(1, Int((CGFloat(ih) * scale).rounded(.down)))
        guard tw != iw || th != ih else { return image }

        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: tw,
            height: th,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }

        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: tw, height: th))
        return ctx.makeImage() ?? image
    }

    static func clearMemoryCache() {
        cache.removeAllObjects()
    }

    private static func sourcePixelSize(url: URL) -> CGSize? {
        let key = url.path as NSString
        cacheLock.lock()
        if let cached = sourceSizeCache[key] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        guard let src = CGImageSourceCreateWithURL(url as CFURL, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary),
            let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        else { return nil }

        let width = ((props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue) ?? 0
        let height = ((props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue) ?? 0
        guard width > 0, height > 0 else { return nil }

        let size = CGSize(width: width, height: height)
        cacheLock.lock()
        sourceSizeCache[key] = size
        cacheLock.unlock()
        return size
    }
}
