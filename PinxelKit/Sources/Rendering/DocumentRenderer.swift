import CoreGraphics
import DocumentModel
import Foundation

public protocol AssetProvider {
    func image(for ref: ImageAssetRef) -> CGImage?
}

public struct DictionaryAssetProvider: AssetProvider {
    public var images: [ImageAssetRef: CGImage]

    public init(_ images: [ImageAssetRef: CGImage]) {
        self.images = images
    }

    public func image(for ref: ImageAssetRef) -> CGImage? { images[ref] }
}

public struct RenderOptions: Sendable {
    /// Pixel di output per pixel del documento.
    public var outputScale: Double
    /// Annotazioni da non disegnare (es. il testo in modifica nell'editor).
    public var excludedAnnotationIDs: Set<UUID>
    /// Colore pieno sotto tutto (es. bianco per JPEG).
    public var matte: RGBA?

    public init(outputScale: Double = 1, excludedAnnotationIDs: Set<UUID> = [], matte: RGBA? = nil) {
        self.outputScale = outputScale
        self.excludedAnnotationIDs = excludedAnnotationIDs
        self.matte = matte
    }
}

public enum RenderError: Error, Equatable {
    case missingBackground
    case invalidSize
    case contextCreationFailed
}

/// Unico percorso di disegno per canvas, miniature ed export.
public final class DocumentRenderer {
    private var processedKey: String?
    private var processedImage: CGImage?
    private let effects = EffectCache()

    public init() {}

    /// Dimensioni della tela (immagine + padding) in pixel del documento.
    public func canvasSize(for document: PinxelDocument) -> CGSize {
        let image = document.imageSize
        let padding = document.canvasStyle.padding
        return CGSize(width: Double(image.width) + 2 * padding, height: Double(image.height) + 2 * padding)
    }

    public func processedBackground(for document: PinxelDocument, assets: any AssetProvider) throws -> CGImage {
        guard let original = assets.image(for: document.background) else { throw RenderError.missingBackground }
        let key = "\(ObjectIdentifier(original))|\(document.imageOperations)"
        if key == processedKey, let cached = processedImage { return cached }
        guard let processed = BackgroundProcessor.process(original, operations: document.imageOperations) else {
            throw RenderError.invalidSize
        }
        processedKey = key
        processedImage = processed
        effects.removeAll()
        return processed
    }

    /// Disegna il documento in `ctx`, il cui spazio utente è l'output in pixel con origine in basso a sinistra.
    public func render(_ document: PinxelDocument, assets: any AssetProvider, in ctx: CGContext, options: RenderOptions = RenderOptions()) throws {
        let background = try processedBackground(for: document, assets: assets)
        let canvas = canvasSize(for: document)
        let style = document.canvasStyle
        let imageRect = CGRect(x: style.padding, y: style.padding, width: Double(background.width), height: Double(background.height))

        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.scaleBy(x: options.outputScale, y: options.outputScale)
        ctx.translateBy(x: 0, y: canvas.height)
        ctx.scaleBy(x: 1, y: -1)

        let fullCanvas = CGRect(origin: .zero, size: canvas)
        if let matte = options.matte {
            ctx.setFillColor(matte.cgColor)
            ctx.fill(fullCanvas)
        }
        if let fill = style.backgroundColor {
            ctx.setFillColor(fill.cgColor)
            ctx.fill(fullCanvas)
        }

        ctx.saveGState()
        if let shadow = style.shadow {
            ShadowStyle.apply(shadow, to: ctx, outputScale: options.outputScale)
        }
        ImageDrawing.draw(background, in: imageRect, context: ctx)
        ctx.restoreGState()

        if let border = style.border, border.width > 0 {
            ctx.setStrokeColor(border.color.cgColor)
            ctx.setLineWidth(border.width)
            ctx.setLineDash(phase: 0, lengths: [])
            ctx.stroke(imageRect.insetBy(dx: border.width / 2, dy: border.width / 2))
        }

        let context = RenderContext(
            background: background,
            stepLabels: StepNumbering.labels(for: document.annotations),
            assets: assets,
            outputScale: options.outputScale,
            effects: effects
        )
        ctx.translateBy(x: style.padding, y: style.padding)
        for annotation in document.annotations where !options.excludedAnnotationIDs.contains(annotation.id) {
            AnnotationRenderer.draw(annotation, in: ctx, context: context)
        }
    }

    public func renderImage(_ document: PinxelDocument, assets: any AssetProvider, options: RenderOptions = RenderOptions()) throws -> CGImage {
        let canvas = canvasSize(for: document)
        let width = Int((canvas.width * options.outputScale).rounded())
        let height = Int((canvas.height * options.outputScale).rounded())
        guard width > 0, height > 0 else { throw RenderError.invalidSize }
        guard let ctx = ImageDrawing.makeContext(width: width, height: height) else { throw RenderError.contextCreationFailed }
        try render(document, assets: assets, in: ctx, options: options)
        guard let image = ctx.makeImage() else { throw RenderError.contextCreationFailed }
        return image
    }
}
