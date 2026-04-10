import CoreGraphics
import Foundation

/// Ровная сетка по sprite sheet: одинаковый **логический** размер ячейки для всех кадров.
/// Целочисленный кроп по сетке уменьшает bleed соседних кадров при последующем масштабировании.
enum GremlinSpriteSheetGeometry {
    /// Логический размер одной ячейки в пикселях исходника (`columns`×`rows` на весь лист).
    static func uniformCellSize(source: CGSize, columns: Int, rows: Int = 1) -> CGSize {
        let c = CGFloat(max(1, columns))
        let r = CGFloat(max(1, rows))
        return CGSize(width: source.width / c, height: source.height / r)
    }

    /// Пиксельный прямоугольник ячейки в **одной горизонтальной строке** (y = 0, высота = высота листа).
    /// Ширина базовой ячейки = `sourceWidth / columns` (целочисленное деление); остаток ширины уходит в последний кадр.
    static func horizontalStripCellPixelRect(
        cellIndex: Int,
        columns: Int,
        sourcePixelWidth: Int,
        sourcePixelHeight: Int
    ) -> (x: Int, y: Int, width: Int, height: Int) {
        let cols = max(1, columns)
        let idx = min(max(cellIndex, 0), cols - 1)
        let iw = max(1, sourcePixelWidth)
        let ih = max(1, sourcePixelHeight)
        let baseW = iw / cols
        let sx = baseW * idx
        let sw = idx == cols - 1 ? max(1, iw - sx) : max(1, baseW)
        return (sx, 0, sw, ih)
    }

    /// Привязка к сетке точек экрана (убирает субпиксельный crawl при `drawImage`).
    static func snapPointsToPixelGrid(_ value: CGFloat, backingScale: CGFloat) -> CGFloat {
        guard backingScale > 0 else { return value }
        return (value * backingScale).rounded() / backingScale
    }

    /// Фиксированный размер «окна» кадра на экране: заданная высота, ширина из пропорций логической ячейки.
    static func displayViewportSize(logicalCell: CGSize, displayHeight: CGFloat) -> CGSize {
        guard logicalCell.height > 0, logicalCell.width > 0 else {
            return CGSize(width: displayHeight, height: displayHeight)
        }
        let scale = displayHeight / logicalCell.height
        return CGSize(width: logicalCell.width * scale, height: displayHeight)
    }

    /// Viewport в поинтах, выровненный по пикселям при заданном `backingScale` (retina).
    static func snappedDisplayViewportSize(logicalCell: CGSize, displayHeight: CGFloat, backingScale: CGFloat) -> CGSize {
        let raw = displayViewportSize(logicalCell: logicalCell, displayHeight: displayHeight)
        return CGSize(
            width: snapPointsToPixelGrid(raw.width, backingScale: backingScale),
            height: snapPointsToPixelGrid(raw.height, backingScale: backingScale)
        )
    }
}
