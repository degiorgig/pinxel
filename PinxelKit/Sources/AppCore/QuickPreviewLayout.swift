import CoreGraphics

public enum QuickPreviewLayout {
    public static let margin: CGFloat = 20
    private static let spacing: CGFloat = 12

    /// Previews are ordered from bottom to top and aligned to the right edge.
    public static func frames(for sizes: [CGSize], in screen: CGRect) -> [CGRect] {
        var y = screen.minY + margin
        return sizes.map { size in
            let frame = CGRect(x: screen.maxX - margin - size.width, y: y, width: size.width, height: size.height)
            y = frame.maxY + spacing
            return frame
        }
    }
}
