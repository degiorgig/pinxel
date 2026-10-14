import CoreGraphics

/// Uno schermo nello spazio globale di CoreGraphics (origine in alto a sinistra del principale, punti).
public struct DisplayInfo: Equatable, Sendable {
    public let id: UInt32
    public let frame: CGRect
    /// Pixel per punto.
    public let scale: Double

    public init(id: UInt32, frame: CGRect, scale: Double) {
        self.id = id
        self.frame = frame
        self.scale = scale
    }
}

/// Una finestra visibile, con frame nello spazio globale di CoreGraphics.
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
    /// AppKit (origine in basso a sinistra del principale) → CoreGraphics (in alto a sinistra).
    public static func topLeft(fromAppKit rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// La conversione è simmetrica.
    public static func appKit(fromTopLeft rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        topLeft(fromAppKit: rect, primaryHeight: primaryHeight)
    }

    public static func display(at point: CGPoint, in displays: [DisplayInfo]) -> DisplayInfo? {
        if let exact = displays.first(where: { $0.frame.contains(point) }) { return exact }
        // `contains` esclude i bordi destro e inferiore: li assegna allo schermo adiacente.
        return displays.first { $0.frame.insetBy(dx: -1, dy: -1).contains(point) }
    }

    /// `windows` in ordine dalla più in primo piano alla più in fondo.
    public static func window(at point: CGPoint, in windows: [WindowInfo]) -> WindowInfo? {
        windows.first { $0.frame.contains(point) }
    }
}
