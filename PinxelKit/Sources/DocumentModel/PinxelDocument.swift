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
    /// Dimensioni della tela in pixel: il rettangolo che racchiude il contenuto (`FitCanvas`). Zero se non c'è niente.
    public var canvasSize: PixelSize
    /// Pixel per punto (2 su Retina).
    public var scale: Double
    public var colorSpace: ColorSpaceID
    /// Margine, colore, bordo e ombra intorno al contenuto.
    public var canvasStyle: CanvasStyle
    /// Ordine = z-order (indice 0 = in fondo). La cattura è un'immagine come le altre.
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

    /// Dimensioni del contenuto (uguali alla tela): il nome che usano libreria, esportazione e strumenti.
    public var imageSize: PixelSize { canvasSize }
}
