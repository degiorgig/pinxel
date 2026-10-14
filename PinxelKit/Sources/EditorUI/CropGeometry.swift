import CoreGraphics
import DocumentModel

/// Riquadro del ritaglio mentre lo si disegna, sposta o ridimensiona. Coordinate del documento.
public enum CropGeometry {
    public enum DragMode: Equatable, Sendable {
        case new, move, resize(Handle)
    }

    /// Riquadro dopo aver trascinato da `start` a `point`; resta sempre dentro `image`.
    public static func dragged(_ mode: DragMode, from start: CGPoint, to point: CGPoint, original: CGRect,
                               image: CGRect, keepAspect: Bool) -> CGRect {
        switch mode {
        case .new:
            let anchor = clamp(start, to: image)
            var corner = clamp(point, to: image)
            if keepAspect { corner = clamp(AnnotationGeometry.squared(from: anchor, to: corner), to: image) }
            return CGRect.bounding([anchor, corner])
        case .move:
            var rect = original.offsetBy(dx: point.x - start.x, dy: point.y - start.y)
            rect.origin.x = min(max(rect.minX, image.minX), image.maxX - rect.width)
            rect.origin.y = min(max(rect.minY, image.minY), image.maxY - rect.height)
            return rect
        case .resize(let handle):
            // La maniglia segue il puntatore mantenendo la distanza da dove è stata presa.
            let handlePoint = HitTesting.boxPoint(handle, of: original)
            let dragged = clamp(CGPoint(x: handlePoint.x + point.x - start.x, y: handlePoint.y + point.y - start.y), to: image)
            let rect = AnnotationGeometry.frame(anchor: HitTesting.boxPoint(handle.opposite, of: original), dragged: dragged,
                                                handle: handle, old: original, keepAspect: keepAspect && handle.isCorner)
            return rect.intersection(image)
        }
    }

    /// Pixel interi dentro l'immagine; `nil` se il riquadro è più piccolo di un pixel.
    public static func pixelRect(_ rect: CGRect, imageSize: PixelSize) -> PixelRect? {
        let r = rect.standardized
        guard r.minX.isFinite, r.minY.isFinite, r.maxX.isFinite, r.maxY.isFinite else { return nil }
        let minX = Int(r.minX.rounded()), minY = Int(r.minY.rounded())
        let maxX = Int(r.maxX.rounded()), maxY = Int(r.maxY.rounded())
        let pixel = PixelRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).clamped(to: imageSize)
        return pixel.width >= 1 && pixel.height >= 1 ? pixel : nil
    }

    private static func clamp(_ point: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(x: min(max(point.x, rect.minX), rect.maxX), y: min(max(point.y, rect.minY), rect.maxY))
    }
}
