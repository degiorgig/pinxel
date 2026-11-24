import CoreGraphics

public enum QuickPreviewLayout {
    public static let margin: CGFloat = 20
    private static let spacing: CGFloat = 12

    /// How far each new round of the stack is moved from the corner, so the previews below it still show.
    public static let roundOffset: CGFloat = 28

    /// Previews are ordered from bottom to top and aligned to the right edge. One that would go past the top starts
    /// a new column to the left; when the columns reach the left edge, the stack starts again near the corner, over
    /// the oldest previews but moved up and left by `roundOffset` (cycling over four positions), so none is hidden
    /// entirely. Every preview stays on screen.
    public static func frames(for sizes: [CGSize], in screen: CGRect) -> [CGRect] {
        var round = 0
        var offset: CGFloat = 0
        var right = screen.maxX - margin
        var y = screen.minY + margin
        var columnWidth: CGFloat = 0
        return sizes.map { size in
            if columnWidth > 0, y + size.height > screen.maxY - margin {
                right -= columnWidth + spacing
                y = screen.minY + margin + offset
                columnWidth = 0
            }
            if right - size.width < screen.minX + margin {
                round += 1
                offset = CGFloat(round % 4) * roundOffset
                // On a small screen the moved round may not fit: then it starts from the corner itself.
                if screen.maxX - margin - offset - size.width < screen.minX + margin
                    || screen.minY + margin + offset + size.height > screen.maxY - margin {
                    offset = 0
                }
                right = screen.maxX - margin - offset
                y = screen.minY + margin + offset
                columnWidth = 0
            }
            let frame = CGRect(x: right - size.width, y: y, width: size.width, height: size.height)
            y = frame.maxY + spacing
            columnWidth = max(columnWidth, size.width)
            return frame
        }
    }
}
