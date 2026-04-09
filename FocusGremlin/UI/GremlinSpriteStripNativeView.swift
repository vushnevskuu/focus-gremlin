import AppKit
import SwiftUI

/// Рисует **ровно один кадр** горизонтального листа через `CGImage.cropping` — без сдвигов SwiftUI `Image`, из‑за которых видны два кадра и «окно» из чёрного фона.
final class GremlinSpriteStripDrawingView: NSView {
    private var assetName = ""
    private var frameIndex = 0
    private var frameCount = 1
    private var displayHeightPoints: CGFloat = 120

    private static let imageCache = NSCache<NSString, NSImage>()

    override var isOpaque: Bool { false }
    override var isFlipped: Bool { true }

    func configure(
        imageName: String,
        frameIndex: Int,
        frameCount: Int,
        displayHeight: CGFloat
    ) {
        self.assetName = imageName
        self.frameIndex = frameIndex
        self.frameCount = max(1, frameCount)
        self.displayHeightPoints = displayHeight
        needsDisplay = true
    }

    private static func cachedImage(named: String) -> NSImage? {
        if let hit = imageCache.object(forKey: named as NSString) { return hit }
        guard let img = NSImage(named: named) else { return nil }
        imageCache.setObject(img, forKey: named as NSString)
        return img
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let img = Self.cachedImage(named: assetName),
              let cgFull = img.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return }

        let iw = cgFull.width
        let ih = cgFull.height
        guard ih > 0, frameCount > 0 else { return }

        let cellW = max(1, iw / frameCount)
        let idx = min(max(frameIndex, 0), frameCount - 1)
        let sx = idx * cellW
        guard let part = cgFull.cropping(to: CGRect(x: sx, y: 0, width: cellW, height: ih))
        else { return }

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        defer { ctx.restoreGState() }

        let alpha = part.alphaInfo
        let hasMeaningfulAlpha: Bool
        switch alpha {
        case .premultipliedLast, .premultipliedFirst, .last, .first, .alphaOnly:
            hasMeaningfulAlpha = true
        default:
            hasMeaningfulAlpha = false
        }
        // Чёрный фон типичных листов: «вычитаем» через screen, чтобы не было прямоугольника.
        ctx.setBlendMode(hasMeaningfulAlpha ? .normal : .screen)
        ctx.interpolationQuality = .none

        let r = bounds
        ctx.translateBy(x: 0, y: r.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(part, in: CGRect(x: 0, y: 0, width: r.width, height: r.height))
    }
}

struct GremlinSpriteStripRepresentable: NSViewRepresentable {
    var imageName: String
    var frameIndex: Int
    var frameCount: Int
    var displayHeight: CGFloat

    func makeNSView(context: Context) -> GremlinSpriteStripDrawingView {
        let v = GremlinSpriteStripDrawingView()
        v.configure(
            imageName: imageName,
            frameIndex: frameIndex,
            frameCount: frameCount,
            displayHeight: displayHeight
        )
        return v
    }

    func updateNSView(_ nsView: GremlinSpriteStripDrawingView, context: Context) {
        let idx = min(max(frameIndex, 0), max(0, frameCount - 1))
        nsView.configure(
            imageName: imageName,
            frameIndex: idx,
            frameCount: frameCount,
            displayHeight: displayHeight
        )
    }
}
