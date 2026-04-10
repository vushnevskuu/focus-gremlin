import AppKit
import CoreGraphics
import Foundation
import ImageIO

/// Глобальные подсказки: каждый PNG может быть горизонтальной лентой из `n` кадров (кадр = `stripCellIndex`).
enum GremlinSpriteStripConfig {
    /// Если `nil`, широкие полосы не режем (только thumbnail целого файла).
    static var defaultStripCells: Int?
    static var cellsByFilename: [String: Int] = [:]
    static var horizontalFlipStripByFile: [String: Bool] = [:]

    static func apply(manifest: GremlinSpriteManifestFile) {
        defaultStripCells = manifest.stripCellsDefault
        cellsByFilename = manifest.stripCellsByFile ?? [:]
        horizontalFlipStripByFile = manifest.horizontalFlipStripByFile ?? [:]
    }

    static func shouldFlipStripHorizontally(filename: String) -> Bool {
        horizontalFlipStripByFile[filename] == true
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
    private static let stripCache = NSCache<NSString, CGImage>()
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
        // `v3`: кэш уменьшенной целой ленты + быстрый кроп ячейки без повторного декода огромного PNG на каждый кадр.
        let key = cellCacheKey(
            url: url,
            maxPixelDimension: maxPixelDimension,
            stripCellCount: strip,
            stripCellIndex: cell
        )
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
           let stripped = extractStripCell(
               from: src,
               url: url,
               stripCells: n,
               cellIndex: cell,
               maxPixelDimension: maxPixelDimension
           ) {
            cg = stripped
        } else {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension,
            kCGImageSourceCreateThumbnailWithTransform: false
        ]
            cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
        }

        guard let cg else { return nil }
        cacheLock.lock()
        cache.setObject(cg, forKey: key, cost: cg.width * cg.height * 4)
        cacheLock.unlock()
        return cg
    }

    static func logicalFramePixelSize(url: URL, stripCellCount: Int? = nil, rows: Int = 1) -> CGSize? {
        guard let sourceSize = sourcePixelSize(url: url) else { return nil }
        let cols = max(1, stripCellCount ?? 1)
        return GremlinSpriteSheetGeometry.uniformCellSize(source: sourceSize, columns: cols, rows: rows)
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
        let key = cellCacheKey(
            url: url,
            maxPixelDimension: maxPixelDimension,
            stripCellCount: strip,
            stripCellIndex: cell
        )
        cacheLock.lock()
        if let hit = cache.object(forKey: key) {
            cacheLock.unlock()
            return hit
        }
        let cachedStrip = strip > 1 ? stripCache.object(
            forKey: stripCacheKey(url: url, maxPixelDimension: maxPixelDimension, stripCellCount: strip)
        ) : nil
        cacheLock.unlock()

        guard let cachedStrip, strip > 1,
              let cellImage = cropStripCell(
                  from: cachedStrip,
                  stripCells: strip,
                  cellIndex: cell,
                  maxPixelDimension: maxPixelDimension
              )
        else { return nil }

        cacheLock.lock()
        cache.setObject(cellImage, forKey: key, cost: cellImage.width * cellImage.height * 4)
        cacheLock.unlock()
        return cellImage
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
        url: URL,
        stripCells: Int,
        cellIndex: Int,
        maxPixelDimension: Int
    ) -> CGImage? {
        guard stripCells > 1 else { return nil }
        let idx = min(max(cellIndex, 0), stripCells - 1)
        guard let decodedStrip = stripThumbnail(
            url: url,
            source: src,
            stripCells: stripCells,
            maxPixelDimension: maxPixelDimension
        ) else { return nil }
        return cropStripCell(
            from: decodedStrip,
            stripCells: stripCells,
            cellIndex: idx,
            maxPixelDimension: maxPixelDimension
        )
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

        ctx.interpolationQuality = .none
        ctx.setAllowsAntialiasing(false)
        ctx.setShouldAntialias(false)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: tw, height: th))
        return ctx.makeImage() ?? image
    }

    static func clearMemoryCache() {
        cache.removeAllObjects()
        stripCache.removeAllObjects()
    }

    private static func stripThumbnail(
        url: URL,
        source: CGImageSource,
        stripCells: Int,
        maxPixelDimension: Int
    ) -> CGImage? {
        let key = stripCacheKey(url: url, maxPixelDimension: maxPixelDimension, stripCellCount: stripCells)
        cacheLock.lock()
        if let hit = stripCache.object(forKey: key) {
            cacheLock.unlock()
            return hit
        }
        cacheLock.unlock()

        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let wAny = props[kCGImagePropertyPixelWidth],
              let hAny = props[kCGImagePropertyPixelHeight]
        else { return nil }

        let width = (wAny as? NSNumber)?.intValue ?? (wAny as? Int) ?? 0
        let height = (hAny as? NSNumber)?.intValue ?? (hAny as? Int) ?? 0
        guard width > 0, height > 0, stripCells > 1 else { return nil }

        let targetSize = stripThumbnailTargetPixelSize(
            sourcePixelWidth: width,
            sourcePixelHeight: height,
            stripCells: stripCells,
            targetCellMaxPixelDimension: maxPixelDimension
        )
        let stripMaxDimension = max(targetSize.width, targetSize.height)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: stripMaxDimension,
            kCGImageSourceCreateThumbnailWithTransform: false,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let normalized = scaleToExactSize(decoded, width: targetSize.width, height: targetSize.height) ?? decoded

        cacheLock.lock()
        stripCache.setObject(normalized, forKey: key, cost: normalized.width * normalized.height * 4)
        cacheLock.unlock()
        return normalized
    }

    private static func cropStripCell(
        from decodedStrip: CGImage,
        stripCells: Int,
        cellIndex: Int,
        maxPixelDimension: Int
    ) -> CGImage? {
        guard stripCells > 1 else { return decodedStrip }
        let rect = GremlinSpriteSheetGeometry.horizontalStripCellPixelRect(
            cellIndex: min(max(cellIndex, 0), stripCells - 1),
            columns: stripCells,
            sourcePixelWidth: decodedStrip.width,
            sourcePixelHeight: decodedStrip.height
        )
        guard let cell = decodedStrip.cropping(to: CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height))
        else { return nil }
        return scaleToMaxDimension(cell, maxPx: maxPixelDimension)
    }

    private static func stripThumbnailTargetPixelSize(
        sourcePixelWidth: Int,
        sourcePixelHeight: Int,
        stripCells: Int,
        targetCellMaxPixelDimension: Int
    ) -> (width: Int, height: Int) {
        let sourceCellWidth = CGFloat(sourcePixelWidth) / CGFloat(max(stripCells, 1))
        let sourceCellHeight = CGFloat(sourcePixelHeight)
        let sourceCellMax = max(sourceCellWidth, sourceCellHeight)
        guard sourceCellMax > 0 else {
            let side = max(1, targetCellMaxPixelDimension)
            return (width: side * max(stripCells, 1), height: side)
        }

        let targetCell = CGFloat(max(1, targetCellMaxPixelDimension))
        var scale = min(1, targetCell / sourceCellMax)
        var targetCellWidth = max(1, Int((sourceCellWidth * scale).rounded()))
        let maxCellWidthForStripLimit = max(1, 16_384 / max(stripCells, 1))
        if targetCellWidth > maxCellWidthForStripLimit {
            targetCellWidth = maxCellWidthForStripLimit
            scale = CGFloat(targetCellWidth) / max(sourceCellWidth, 1)
        }
        let targetCellHeight = max(1, Int((sourceCellHeight * scale).rounded()))
        return (
            width: targetCellWidth * max(stripCells, 1),
            height: targetCellHeight
        )
    }

    private static func scaleToExactSize(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0 else { return image }
        guard image.width != width || image.height != height else { return image }

        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }

        ctx.interpolationQuality = .none
        ctx.setAllowsAntialiasing(false)
        ctx.setShouldAntialias(false)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage() ?? image
    }

    private static func cellCacheKey(
        url: URL,
        maxPixelDimension: Int,
        stripCellCount: Int,
        stripCellIndex: Int
    ) -> NSString {
        "\(url.path)#\(maxPixelDimension)#strip\(stripCellCount)#c\(stripCellIndex)#v4" as NSString
    }

    private static func stripCacheKey(
        url: URL,
        maxPixelDimension: Int,
        stripCellCount: Int
    ) -> NSString {
        "\(url.path)#\(maxPixelDimension)#strip\(stripCellCount)#stripThumb#v4" as NSString
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
