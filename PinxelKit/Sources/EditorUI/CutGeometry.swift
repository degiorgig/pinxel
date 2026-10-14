import CoreGraphics
import DocumentModel

public enum CutGeometry {
    /// Fascia minima, in pixel: sotto questa un trascinamento è un clic.
    public static let minimumLength = 2

    /// Fascia da togliere trascinando da `start` a `end`: un trascinamento soprattutto verticale toglie righe
    /// (fascia orizzontale), uno orizzontale toglie colonne. `nil` se troppo corta o se toglierebbe tutto.
    public static func cut(from start: CGPoint, to end: CGPoint, imageSize: PixelSize, edge: CutEdge) -> CutOut? {
        let axis: Axis = abs(end.y - start.y) >= abs(end.x - start.x) ? .horizontal : .vertical
        let a = axis == .horizontal ? start.y : start.x
        let b = axis == .horizontal ? end.y : end.x
        let limit = Double(axis == .horizontal ? imageSize.height : imageSize.width)
        let low = Int(max(0, min(a, b)).rounded())
        let high = Int(min(limit, max(a, b)).rounded())
        let length = high - low
        guard length >= minimumLength, length < Int(limit) else { return nil }
        return CutOut(axis: axis, start: low, length: length, edge: edge)
    }
}
