import AppKit
import SwiftUI

/// Рисует **один дискретный кадр** спрайт-листа: кроп по пикселям лучшего bitmap-репрезентации, без «прокрутки» полосы.
final class GremlinSpriteStripDrawingView: NSView {
    private var assetName = ""
    private var frameIndex = 0
    private var frameCount = 1

    private static let imageCache = NSCache<NSString, NSImage>()

    override var isOpaque: Bool { false }
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    func configure(
        imageName: String,
        frameIndex: Int,
        frameCount: Int,
        displayHeight: CGFloat
    ) {
        self.assetName = imageName
        self.frameIndex = frameIndex
        self.frameCount = max(1, frameCount)
        _ = displayHeight
        needsDisplay = true
    }

    private static func cachedImage(named: String) -> NSImage? {
        if let hit = imageCache.object(forKey: named as NSString) { return hit }
        guard let img = NSImage(named: named) else { return nil }
        imageCache.setObject(img, forKey: named as NSString)
        return img
    }

    /// Берём самый широкий `NSBitmapImageRep`, иначе fallback `cgImage`.
    private static func rasterCGImage(from image: NSImage) -> CGImage? {
        var best: NSBitmapImageRep?
        var bestW = 0
        for case let bmp as NSBitmapImageRep in image.representations {
            if bmp.pixelsWide > bestW {
                bestW = bmp.pixelsWide
                best = bmp
            }
        }
        if let best, let cg = best.cgImage { return cg }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        NSBezierPath(rect: bounds).fill()

        guard let img = Self.cachedImage(named: assetName),
              let cgFull = Self.rasterCGImage(from: img)
        else { return }

        let iw = cgFull.width
        let ih = cgFull.height
        guard ih > 0, frameCount > 0 else { return }

        let idx = min(max(frameIndex, 0), frameCount - 1)
        let frameWIdeal = CGFloat(iw) / CGFloat(frameCount)
        let sx = Int(floor(CGFloat(idx) * frameWIdeal))
        let nextStart = idx + 1 < frameCount ? Int(floor(CGFloat(idx + 1) * frameWIdeal)) : iw
        let cw = max(1, nextStart - sx)

        guard let part = cgFull.cropping(to: CGRect(x: sx, y: 0, width: cw, height: ih))
        else { return }

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        defer { ctx.restoreGState() }

        // Спрайты с прозрачным фоном (PNG + alpha) — только обычное наложение.
        // Режим `.screen` для «вычитания» чёрного портит нормальные ассеты с альфой.
        ctx.setBlendMode(.normal)
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
        let v = GremlinSpriteStripDrawingView(frame: .zero)
        updateNSView(v, context: context)
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
