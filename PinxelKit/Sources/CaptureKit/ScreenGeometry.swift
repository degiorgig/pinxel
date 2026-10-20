import CoreGraphics

/// A screen in CoreGraphics global space (origin at the top left of the main screen, points).
public struct DisplayInfo: Equatable, Sendable {
    public let id: UInt32
    public let frame: CGRect
    /// Pixels per point.
    public let scale: Double

    public init(id: UInt32, frame: CGRect, scale: Double) {
        self.id = id
        self.frame = frame
        self.scale = scale
    }
}

/// A visible window, with a frame in CoreGraphics global space.
public struct WindowInfo: Equatable, Sendable, Identifiable {
    public let id: UInt32
    public let frame: CGRect
    public let title: String?
    public let appName: String?
    public let bundleIdentifier: String?

    public init(id: UInt32, frame: CGRect, title: String?, appName: String?, bundleIdentifier: String?) {
        self.id = id
        self.frame = frame
        self.title = title
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
    }
}

public enum ScreenGeometry {
    /// AppKit (origin at the bottom left of the main screen) → CoreGraphics (top left).
    public static func topLeft(fromAppKit rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// The conversion is symmetric.
    public static func appKit(fromTopLeft rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        topLeft(fromAppKit: rect, primaryHeight: primaryHeight)
    }

    public static func display(at point: CGPoint, in displays: [DisplayInfo]) -> DisplayInfo? {
        if let exact = displays.first(where: { $0.frame.contains(point) }) { return exact }
        // `contains` excludes the right and bottom edges: it assigns them to the adjacent screen.
        return displays.first { $0.frame.insetBy(dx: -1, dy: -1).contains(point) }
    }

    /// `windows` ordered from frontmost to backmost.
    public static func window(at point: CGPoint, in windows: [WindowInfo]) -> WindowInfo? {
        windows.first { $0.frame.contains(point) }
    }
}
