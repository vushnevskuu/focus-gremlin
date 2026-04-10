import AppKit
import SwiftUI

/// Один кадр: файл из бандла + опциональная ячейка горизонтальной ленты (ImageIO, без полного разворачивания гигантских PNG).
final class GremlinDiscreteFrameImageView: NSView {
    private var displayHeight: CGFloat = 120
    private var configuredFrame: GremlinSpriteFrameRef?
    private var logicalPixelSize: CGSize?

    private var displayed: CGImage?
    private var loadGeneration = 0

    override var isOpaque: Bool { false }
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func configure(frame: GremlinSpriteFrameRef, displayHeight: CGFloat) {
        guard frame.stripCellCount >= 1 else {
            if configuredFrame == nil, self.displayHeight == displayHeight { return }
            configuredFrame = nil
            self.displayHeight = displayHeight
            logicalPixelSize = nil
            displayed = nil
            loadGeneration += 1
            invalidateIntrinsicContentSize()
            needsDisplay = true
            return
        }

        if configuredFrame == frame, self.displayHeight == displayHeight, displayed != nil {
            return
        }

        let metaChanged = configuredFrame?.url != frame.url
            || configuredFrame?.stripCellCount != frame.stripCellCount
            || self.displayHeight != displayHeight

        configuredFrame = frame
        self.displayHeight = displayHeight
        let strip = frame.stripCellCount > 1 ? frame.stripCellCount : nil
        let nextLogicalPixelSize = GremlinSpriteThumbnailLoader.logicalFramePixelSize(
            url: frame.url,
            stripCellCount: strip
        )
        let sizeChanged = logicalPixelSize != nextLogicalPixelSize
        logicalPixelSize = nextLogicalPixelSize

        if metaChanged || sizeChanged {
            displayed = nil
        }
        loadGeneration += 1
        let gen = loadGeneration
        let maxPx = GremlinSpriteThumbnailLoader.maxPixelDimension(forDisplayHeightPoints: displayHeight)
        let cellIdx = frame.stripCellIndex

        if let cached = GremlinSpriteThumbnailLoader.imageIfCached(
            url: frame.url,
            maxPixelDimension: maxPx,
            stripCellCount: strip,
            stripCellIndex: cellIdx
        ) {
            guard gen == loadGeneration else { return }
            displayed = cached
            invalidateIntrinsicContentSize()
            needsDisplay = true
            return
        }

        Task.detached(priority: .userInitiated) {
            let cg = GremlinSpriteThumbnailLoader.cgImage(
                url: frame.url,
                maxPixelDimension: maxPx,
                stripCellCount: strip,
                stripCellIndex: cellIdx
            )
            await MainActor.run { [weak self] in
                guard let self, gen == self.loadGeneration else { return }
                self.displayed = cg
                self.invalidateIntrinsicContentSize()
                self.needsDisplay = true
            }
        }

        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    override var intrinsicContentSize: NSSize {
        if let logicalPixelSize,
           logicalPixelSize.width > 0,
           logicalPixelSize.height > 0 {
            let scale = displayHeight / logicalPixelSize.height
            let width = logicalPixelSize.width * scale
            return NSSize(width: width, height: displayHeight)
        }
        guard let cg = displayed else {
            return NSSize(width: displayHeight, height: displayHeight)
        }
        let ih = max(1, cg.height)
        let scale = displayHeight / CGFloat(ih)
        let w = CGFloat(cg.width) * scale
        return NSSize(width: w, height: displayHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        NSBezierPath(rect: bounds).fill()

        guard let cg = displayed,
              let ctx = NSGraphicsContext.current?.cgContext
        else { return }

        let ih = max(1, cg.height)
        let iw = max(1, cg.width)
        let scale = bounds.height / CGFloat(ih)
        let dw = CGFloat(iw) * scale
        let dh = bounds.height

        ctx.saveGState()
        defer { ctx.restoreGState() }

        ctx.clip(to: bounds)
        ctx.interpolationQuality = .default
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        ctx.setBlendMode(.normal)

        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: dw, height: dh))
    }
}

struct GremlinDiscreteFrameImageRepresentable: NSViewRepresentable {
    var frame: GremlinSpriteFrameRef
    var displayHeight: CGFloat

    func makeNSView(context: Context) -> GremlinDiscreteFrameImageView {
        let v = GremlinDiscreteFrameImageView(frame: .zero)
        v.configure(frame: frame, displayHeight: displayHeight)
        return v
    }

    func updateNSView(_ nsView: GremlinDiscreteFrameImageView, context: Context) {
        nsView.configure(frame: frame, displayHeight: displayHeight)
    }
}
