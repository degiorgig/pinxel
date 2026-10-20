import CoreGraphics
import DocumentModel

public enum CutGeometry {
    /// Minimum band, in pixels: below this a drag is a click.
    public static let minimumLength = 2

    /// Band to remove by dragging from `start` to `end`: a mostly vertical drag removes rows
    /// (horizontal band), a horizontal one removes columns. `nil` if too short or if it would remove everything.
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
