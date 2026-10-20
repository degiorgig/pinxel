import CoreGraphics

public enum MagnifierPlacement {
    /// Box of a new lens's magnification: the source scaled by `zoom`, to the right of the source
    /// (to the left if it does not fit), vertically centered and inside the image whenever possible.
    public static func target(for source: CGRect, zoom: Double, imageSize: CGSize, gap: Double = 24) -> CGRect {
        let s = source.standardized
        let size = CGSize(width: s.width * zoom, height: s.height * zoom)
        var x = s.maxX + gap
        if x + size.width > imageSize.width { x = s.minX - gap - size.width }
        if x < 0 { x = max(0, min(imageSize.width - size.width, s.midX - size.width / 2)) }
        let y = max(0, min(s.midY - size.height / 2, imageSize.height - size.height))
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}
