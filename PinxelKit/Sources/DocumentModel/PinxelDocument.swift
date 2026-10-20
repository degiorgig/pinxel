import Foundation

/// Reference to an image inside the `.pinxel` archive (e.g. "background.png", "assets/<uuid>.png").
public struct ImageAssetRef: Codable, Hashable, Sendable {
    public var name: String

    public init(name: String) {
        self.name = name
    }
}

public enum ColorSpaceID: String, Codable, Sendable {
    case sRGB, displayP3
}

public struct Border: Codable, Equatable, Sendable {
    public var color: RGBA
    public var width: Double

    public init(color: RGBA, width: Double) {
        self.color = color
        self.width = width
    }
}

public struct CanvasStyle: Codable, Equatable, Sendable {
    /// Margin around the image, in document pixels.
    public var padding: Double
    public var backgroundColor: RGBA?
    public var border: Border?
    public var shadow: Shadow?

    public init(padding: Double = 0, backgroundColor: RGBA? = nil, border: Border? = nil, shadow: Shadow? = nil) {
        self.padding = padding
        self.backgroundColor = backgroundColor
        self.border = border
        self.shadow = shadow
    }
}

public struct CaptureMetadata: Codable, Equatable, Sendable {
    public var captureDate: Date
    public var appName: String?
    public var bundleIdentifier: String?
    public var windowTitle: String?
    public var url: String?

    public init(captureDate: Date = Date(), appName: String? = nil, bundleIdentifier: String? = nil, windowTitle: String? = nil, url: String? = nil) {
        self.captureDate = captureDate
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
        self.url = url
    }
}

public struct PinxelDocument: Codable, Equatable, Sendable {
    /// Canvas size in pixels: the rectangle enclosing the content (`FitCanvas`). Zero if there is nothing.
    public var canvasSize: PixelSize
    /// Pixels per point (2 on Retina).
    public var scale: Double
    public var colorSpace: ColorSpaceID
    /// Margin, color, border and shadow around the content.
    public var canvasStyle: CanvasStyle
    /// Order = z-order (index 0 = at the bottom). The capture is an image like the others.
    public var annotations: [Annotation]
    public var metadata: CaptureMetadata

    public init(
        canvasSize: PixelSize,
        scale: Double = 1,
        colorSpace: ColorSpaceID = .sRGB,
        canvasStyle: CanvasStyle = CanvasStyle(),
        annotations: [Annotation] = [],
        metadata: CaptureMetadata
    ) {
        self.canvasSize = canvasSize
        self.scale = scale
        self.colorSpace = colorSpace
        self.canvasStyle = canvasStyle
        self.annotations = annotations
        self.metadata = metadata
    }

    /// Content size (equal to the canvas): the name used by library, export and tools.
    public var imageSize: PixelSize { canvasSize }
}
