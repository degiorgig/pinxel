import CoreGraphics

public enum QuickPreviewLayout {
    public static let margin: CGFloat = 20
    private static let spacing: CGFloat = 12

    /// Previews are ordered from bottom to top and aligned to the right edge. One that would go past the top starts
    /// a new column to the left, so every preview stays on screen.
    public static func frames(for sizes: [CGSize], in screen: CGRect) -> [CGRect] {
        var right = screen.maxX - margin
        var y = screen.minY + margin
        var columnWidth: CGFloat = 0
        return sizes.map { size in
            if columnWidth > 0, y + size.height > screen.maxY - margin {
                right -= columnWidth + spacing
                y = screen.minY + margin
                columnWidth = 0
            }
            let frame = CGRect(x: right - size.width, y: y, width: size.width, height: size.height)
            y = frame.maxY + spacing
            columnWidth = max(columnWidth, size.width)
            return frame
        }
    }
}
