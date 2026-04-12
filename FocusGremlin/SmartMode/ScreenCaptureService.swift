import AppKit
import CoreGraphics

struct GremlinScreenCaptureTarget: Sendable {
    let displayID: CGDirectDisplayID
    let displayBounds: CGRect
    let cropRectInDisplayPoints: CGRect?
}

/// Захват основного дисплея в JPEG **только в памяти** (без записи, пока не включён debug в настройках).
enum ScreenCaptureService {
    /// Квадрат вокруг курсора на экране, где он сейчас (для VLM «что под указателем»).
    @MainActor
    static func cursorNeighborhoodCaptureTarget(halfExtent: CGFloat = 240) -> GremlinScreenCaptureTarget? {
        let p = NSEvent.mouseLocation
        guard let screen = screenContaining(point: p) else { return nil }
        let displayID = displayID(for: screen)
        let frame = screen.frame
        let rect = CGRect(
            x: p.x - halfExtent,
            y: p.y - halfExtent,
            width: halfExtent * 2,
            height: halfExtent * 2
        )
        let crop = rect.intersection(frame)
        guard !crop.isNull, crop.width > 48, crop.height > 48 else { return nil }
        return GremlinScreenCaptureTarget(
            displayID: displayID,
            displayBounds: frame,
            cropRectInDisplayPoints: crop
        )
    }

    @MainActor
    static func focusedWindowCaptureTarget(padding: CGFloat = 28) -> GremlinScreenCaptureTarget? {
        guard let snapshot = WindowContextProvider.frontmostWindowSnapshot(),
              let windowFrame = snapshot.frame
        else { return nil }

        let center = CGPoint(x: windowFrame.midX, y: windowFrame.midY)
        guard let screen = screenContaining(point: center) else { return nil }
        let displayID = displayID(for: screen)
        let padded = windowFrame.insetBy(dx: -padding, dy: -padding)
        let clamped = padded.intersection(screen.frame)
        let crop = clamped.isNull || clamped.width < 40 || clamped.height < 40 ? nil : clamped

        return GremlinScreenCaptureTarget(
            displayID: displayID,
            displayBounds: screen.frame,
            cropRectInDisplayPoints: crop
        )
    }

    /// Возвращает сжатый JPEG или nil, если нет разрешения Screen Recording / сбой захвата.
    nonisolated static func captureMainDisplayJPEG(maxDimension: CGFloat = 768, quality: CGFloat = 0.52) -> Data? {
        captureJPEG(target: nil, maxDimension: maxDimension, quality: quality)
    }

    nonisolated static func captureJPEG(
        target: GremlinScreenCaptureTarget?,
        maxDimension: CGFloat = 960,
        quality: CGFloat = 0.58
    ) -> Data? {
        // Не пробуем захват, пока пассивная проверка прав не зелёная, чтобы не дёргать системный prompt.
        guard PermissionGate.screenRecordingAuthorized else { return nil }
        let requestedDisplayID = target?.displayID ?? CGMainDisplayID()
        guard let rawImage = CGDisplayCreateImage(requestedDisplayID) ?? CGDisplayCreateImage(CGMainDisplayID()) else { return nil }

        let cgImage: CGImage = {
            guard let target,
                  let cropRect = target.cropRectInDisplayPoints,
                  let pixelCrop = pixelCropRect(
                    cropRectInDisplayPoints: cropRect,
                    displayBoundsInPoints: target.displayBounds,
                    imagePixelSize: CGSize(width: rawImage.width, height: rawImage.height)
                  ),
                  let cropped = rawImage.cropping(to: pixelCrop)
            else {
                return rawImage
            }
            return cropped
        }()

        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)
        guard w > 0, h > 0 else { return nil }

        let scale = min(1, maxDimension / max(w, h))
        let targetW = max(1, Int(w * scale))
        let targetH = max(1, Int(h * scale))

        let sourceImage = NSImage(cgImage: cgImage, size: NSSize(width: w, height: h))
        // 3 сэмпла + hasAlpha: false — иначе AppKit логирует «Inconsistent set of values…» и может сорвать поток.
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: targetW,
            pixelsHigh: targetH,
            bitsPerSample: 8,
            samplesPerPixel: 3,
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

    nonisolated static func pixelCropRect(
        cropRectInDisplayPoints: CGRect,
        displayBoundsInPoints: CGRect,
        imagePixelSize: CGSize
    ) -> CGRect? {
        guard imagePixelSize.width > 0, imagePixelSize.height > 0 else { return nil }
        let displayRect = displayBoundsInPoints.standardized
        let cropRect = cropRectInDisplayPoints.standardized.intersection(displayRect)
        guard !cropRect.isNull, cropRect.width > 1, cropRect.height > 1 else { return nil }

        let scaleX = imagePixelSize.width / displayRect.width
        let scaleY = imagePixelSize.height / displayRect.height

        let x = (cropRect.minX - displayRect.minX) * scaleX
        let y = imagePixelSize.height - ((cropRect.maxY - displayRect.minY) * scaleY)
        let width = cropRect.width * scaleX
        let height = cropRect.height * scaleY

        let raw = CGRect(x: x, y: y, width: width, height: height)
        let integral = CGRect(
            x: floor(raw.minX),
            y: floor(raw.minY),
            width: ceil(raw.width),
            height: ceil(raw.height)
        )
        let clamped = integral.intersection(CGRect(origin: .zero, size: imagePixelSize))
        guard !clamped.isNull, clamped.width > 1, clamped.height > 1 else { return nil }
        return clamped
    }

    @MainActor
    static func screenContaining(point: CGPoint) -> NSScreen? {
        let nsPoint = NSPoint(x: point.x, y: point.y)
        return NSScreen.screens.first { NSMouseInRect(nsPoint, $0.frame, false) } ?? NSScreen.main
    }

    @MainActor
    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return CGDirectDisplayID(number.uint32Value)
        }
        return CGMainDisplayID()
    }
}
