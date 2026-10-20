import CoreGraphics

/// Calculations for the scrolling-capture area and panel. Global coordinates in points, origin at top left.
public enum ScrollCaptureGeometry {
    public static let minimumHeight: CGFloat = 100
    /// Maximum memory for the longest possible image.
    public static let byteBudget = 1 << 30

    /// The area limited to its screen, narrowed to whole pixels and, if needed, in width for the memory budget.
    /// `nil` if it stays shorter than `minimumHeight`.
    public static func prepare(_ rect: CGRect, on display: DisplayInfo, maxHeight: Int) -> (rect: CGRect, narrowed: Bool)? {
        let visible = rect.standardized.intersection(display.frame)
        guard !visible.isNull else { return nil }
        let clipped = wholePixels(visible, on: display)
        guard clipped.height >= minimumHeight else { return nil }
        let maxWidth = (Double(byteBudget / (max(maxHeight, 1) * 4)) / display.scale).rounded(.down)
        guard clipped.width > maxWidth else { return (clipped, false) }
        return (CGRect(x: clipped.minX, y: clipped.minY, width: maxWidth, height: clipped.height), true)
    }

    /// The largest rectangle made of whole screen pixels inside `rect`: with half-pixel edges the last captured row
    /// would pick up a bit of what lies just outside, like the area's frame.
    static func wholePixels(_ rect: CGRect, on display: DisplayInfo) -> CGRect {
        let scale = display.scale, origin = display.frame.origin
        let minX = ((rect.minX - origin.x) * scale).rounded(.up), maxX = ((rect.maxX - origin.x) * scale).rounded(.down)
        let minY = ((rect.minY - origin.y) * scale).rounded(.up), maxY = ((rect.maxY - origin.y) * scale).rounded(.down)
        return CGRect(x: origin.x + minX / scale, y: origin.y + minY / scale,
                      width: max(0, maxX - minX) / scale, height: max(0, maxY - minY) / scale)
    }

    /// Panel outside the area: below, above, right, left; if there is no room, at the bottom right inside the screen
    /// (the capture excludes Pinxel's windows anyway).
    public static func panelFrame(size: CGSize, around rect: CGRect, in screen: CGRect, gap: CGFloat = 12) -> CGRect {
        func clampX(_ x: CGFloat) -> CGFloat { min(max(x, screen.minX), screen.maxX - size.width) }
        func clampY(_ y: CGFloat) -> CGFloat { min(max(y, screen.minY), screen.maxY - size.height) }
        let centeredX = clampX(rect.midX - size.width / 2)
        if rect.maxY + gap + size.height <= screen.maxY {
            return CGRect(origin: CGPoint(x: centeredX, y: rect.maxY + gap), size: size)
        }
        if rect.minY - gap - size.height >= screen.minY {
            return CGRect(origin: CGPoint(x: centeredX, y: rect.minY - gap - size.height), size: size)
        }
        if rect.maxX + gap + size.width <= screen.maxX {
            return CGRect(origin: CGPoint(x: rect.maxX + gap, y: clampY(rect.minY)), size: size)
        }
        if rect.minX - gap - size.width >= screen.minX {
            return CGRect(origin: CGPoint(x: rect.minX - gap - size.width, y: clampY(rect.minY)), size: size)
        }
        return CGRect(origin: CGPoint(x: screen.maxX - size.width - gap, y: screen.maxY - size.height - gap), size: size)
    }
}
