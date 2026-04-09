import AppKit
import CoreGraphics

/// Захват основного дисплея в JPEG **только в памяти** (без записи, пока не включён debug в настройках).
enum ScreenCaptureService {
    /// Возвращает сжатый JPEG или nil, если нет разрешения Screen Recording / сбой захвата.
    nonisolated static func captureMainDisplayJPEG(maxDimension: CGFloat = 768, quality: CGFloat = 0.52) -> Data? {
        guard CGPreflightScreenCaptureAccess() else { return nil }
        let displayID = CGMainDisplayID()
        guard let cgImage = CGDisplayCreateImage(displayID) else { return nil }

        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)
        guard w > 0, h > 0 else { return nil }

        let scale = min(1, maxDimension / max(w, h))
        let targetW = max(1, Int(w * scale))
        let targetH = max(1, Int(h * scale))

        let sourceImage = NSImage(cgImage: cgImage, size: NSSize(width: w, height: h))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: targetW,
            pixelsHigh: targetH,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: false,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        rep.size = NSSize(width: targetW, height: targetH)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        sourceImage.draw(
            in: NSRect(x: 0, y: 0, width: targetW, height: targetH),
            from: NSRect(x: 0, y: 0, width: w, height: h),
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }
}
