import AppKit
import SwiftUI

/// Один кадр: файл из бандла + опциональная ячейка горизонтальной ленты (ImageIO, без полного разворачивания гигантских PNG).
final class GremlinDiscreteFrameImageView: NSView {
    private var displayHeight: CGFloat = 120
    private var configuredFrame: GremlinSpriteFrameRef?
    private var logicalPixelSize: CGSize?

    private var displayed: CGImage?
    /// Кадр, который реально попал в `displayed` (отличается от `configuredFrame` при гонках loadGeneration).
    private var appliedFrame: GremlinSpriteFrameRef?
    private var loadGeneration = 0
    /// Чтобы не вызывать invalidateIntrinsicContentSize на каждой смене кадра с тем же размером.
    private var lastReportedIntrinsic = NSSize(width: -1, height: -1)

    override var isOpaque: Bool { false }
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func configure(frame: GremlinSpriteFrameRef, displayHeight: CGFloat) {
        let previousFrame = configuredFrame
        guard frame.stripCellCount >= 1 else {
            if configuredFrame == nil, self.displayHeight == displayHeight { return }
            configuredFrame = nil
            self.displayHeight = displayHeight
            logicalPixelSize = nil
            displayed = nil
            appliedFrame = nil
            loadGeneration += 1
            lastReportedIntrinsic = NSSize(width: -1, height: -1)
            invalidateIntrinsicContentSizeIfNeeded()
            needsDisplay = true
            return
        }

        if appliedFrame == frame, self.displayHeight == displayHeight, displayed != nil {
            return
        }

        let metaChanged = configuredFrame?.url != frame.url
            || configuredFrame?.stripCellCount != frame.stripCellCount
            || self.displayHeight != displayHeight
        let frameChanged = previousFrame != frame || self.displayHeight != displayHeight

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
            appliedFrame = nil
            lastReportedIntrinsic = NSSize(width: -1, height: -1)
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
        ), gen == loadGeneration {
            displayed = cached
            appliedFrame = frame
            invalidateIntrinsicContentSizeIfNeeded()
            needsDisplay = true
            return
        }

        if frameChanged {
            displayed = nil
            appliedFrame = nil
            needsDisplay = true
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
                self.appliedFrame = frame
                self.invalidateIntrinsicContentSizeIfNeeded()
                self.needsDisplay = true
            }
        }

        invalidateIntrinsicContentSizeIfNeeded()
        needsDisplay = true
    }

    override var intrinsicContentSize: NSSize {
        computeIntrinsicContentSize()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        NSBezierPath(rect: bounds).fill()

        guard let cg = displayed,
              let ctx = NSGraphicsContext.current?.cgContext
        else { return }

        let ih = max(1, cg.height)
        let iw = max(1, cg.width)
        let bs = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let scale = bounds.height / CGFloat(ih)
        var dw = CGFloat(iw) * scale
        var dh = bounds.height
        var dx = max(0, (bounds.width - dw) * 0.5)
        dx = GremlinSpriteSheetGeometry.snapPointsToPixelGrid(dx, backingScale: bs)
        dw = GremlinSpriteSheetGeometry.snapPointsToPixelGrid(dw, backingScale: bs)
        dh = GremlinSpriteSheetGeometry.snapPointsToPixelGrid(dh, backingScale: bs)

        ctx.saveGState()
        defer { ctx.restoreGState() }

        ctx.clip(to: bounds)
        ctx.interpolationQuality = .none
        ctx.setAllowsAntialiasing(false)
        ctx.setShouldAntialias(false)
        ctx.setBlendMode(.normal)

        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)

        let fname = configuredFrame?.url.lastPathComponent ?? ""
        let flipX = GremlinSpriteStripConfig.shouldFlipStripHorizontally(filename: fname)
        if flipX {
            ctx.translateBy(x: dx + dw, y: 0)
            ctx.scaleBy(x: -1, y: 1)
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: dw, height: dh))
        } else {
            ctx.draw(cg, in: CGRect(x: dx, y: 0, width: dw, height: dh))
        }
    }

    private func invalidateIntrinsicContentSizeIfNeeded() {
        let n = computeIntrinsicContentSize()
        if abs(n.width - lastReportedIntrinsic.width) > 0.5 || abs(n.height - lastReportedIntrinsic.height) > 0.5 {
            lastReportedIntrinsic = n
            invalidateIntrinsicContentSize()
        }
    }

    private func computeIntrinsicContentSize() -> NSSize {
        if let logicalPixelSize,
           logicalPixelSize.width > 0,
           logicalPixelSize.height > 0 {
            let bs = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
            let vp = GremlinSpriteSheetGeometry.snappedDisplayViewportSize(
                logicalCell: logicalPixelSize,
                displayHeight: displayHeight,
                backingScale: bs
            )
            return NSSize(width: vp.width, height: vp.height)
        }
        guard let cg = displayed else {
            return NSSize(width: displayHeight, height: displayHeight)
        }
        let ih = max(1, cg.height)
        let scale = displayHeight / CGFloat(ih)
        let w = CGFloat(cg.width) * scale
        return NSSize(width: w, height: displayHeight)
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
