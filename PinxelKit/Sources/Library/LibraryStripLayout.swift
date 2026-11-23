import CoreGraphics

/// Height of the capture strip under the editor, which the user drags, and the thumbnails that fill it.
public enum LibraryStripLayout {
    public static let defaultHeight: Double = 140
    public static let minHeight: Double = 110
    public static let maxHeight: Double = 400
    /// What surrounds the thumbnails: filter bar, spacing, padding and room for the scroll bar.
    static let chrome: Double = 50
    /// Width over height of a thumbnail.
    static let aspect: Double = 14.0 / 9.0

    /// The height asked for, kept between the bounds and under `limit` (what the window leaves to the strip).
    public static func clampedHeight(_ height: Double, limit: Double = .infinity) -> Double {
        let upper = max(minHeight, min(maxHeight, limit))
        return min(max(height, minHeight), upper)
    }

    /// Thumbnails grow with the strip, so a taller one shows them whole and larger.
    public static func thumbnailSize(stripHeight: Double) -> CGSize {
        let height = clampedHeight(stripHeight) - chrome
        return CGSize(width: (height * aspect).rounded(), height: height)
    }
}
