import Foundation

/// Riferimento a un'immagine dentro l'archivio `.pinxel` (es. "background.png", "assets/<uuid>.png").
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
    /// Margine attorno all'immagine, in pixel del documento.
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
    /// Immagine originale, mai modificata.
    public var background: ImageAssetRef
    /// Dimensioni in pixel dell'immagine originale.
    public var canvasSize: PixelSize
    /// Pixel per punto (2 su Retina).
    public var scale: Double
    public var colorSpace: ColorSpaceID
    public var imageOperations: [ImageOperation]
    public var canvasStyle: CanvasStyle
    /// Ordine = z-order (indice 0 = in fondo).
    public var annotations: [Annotation]
    public var metadata: CaptureMetadata

    public init(
        background: ImageAssetRef,
        canvasSize: PixelSize,
        scale: Double = 1,
        colorSpace: ColorSpaceID = .sRGB,
        imageOperations: [ImageOperation] = [],
        canvasStyle: CanvasStyle = CanvasStyle(),
        annotations: [Annotation] = [],
        metadata: CaptureMetadata
    ) {
        self.background = background
        self.canvasSize = canvasSize
        self.scale = scale
        self.colorSpace = colorSpace
        self.imageOperations = imageOperations
        self.canvasStyle = canvasStyle
        self.annotations = annotations
        self.metadata = metadata
    }

    /// Dimensioni dell'immagine dopo tutte le operazioni.
    public var imageSize: PixelSize {
        imageOperations.reduce(canvasSize) { size, operation in operation.resultSize(from: size) }
    }
}
