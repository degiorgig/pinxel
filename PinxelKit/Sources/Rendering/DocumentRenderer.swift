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
    case invalidSize
    case contextCreationFailed
}

/// Unico percorso di disegno per canvas, miniature ed export.
public final class DocumentRenderer {
    private let effects = EffectCache()

    public init() {}

    /// Dimensioni della tela (immagine + padding) in pixel del documento.
    public func canvasSize(for document: PinxelDocument) -> CGSize {
        let image = document.imageSize
        let padding = document.canvasStyle.padding
        return CGSize(width: Double(image.width) + 2 * padding, height: Double(image.height) + 2 * padding)
    }

    /// Disegna il documento in `ctx`, il cui spazio utente è l'output in pixel con origine in basso a sinistra.
    public func render(_ document: PinxelDocument, assets: any AssetProvider, in ctx: CGContext, options: RenderOptions = RenderOptions()) throws {
        let canvas = canvasSize(for: document)
        let style = document.canvasStyle
        let contentRect = CGRect(x: style.padding, y: style.padding, width: Double(document.imageSize.width), height: Double(document.imageSize.height))

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

        let excluded = options.excludedAnnotationIDs
        var context: RenderContext!
        context = RenderContext(
            contentSize: document.imageSize,
            stepLabels: StepNumbering.labels(for: document.annotations),
            assets: assets,
            outputScale: options.outputScale,
            effects: effects,
            layers: { [unowned self] index, region in
                self.layers(below: index, region: region, document: document, excluded: excluded, context: context)
            }
        )
        // Il contenuto in un livello unico: l'ombra della tela segue la sua sagoma.
        ctx.saveGState()
        if let shadow = style.shadow {
            ShadowStyle.apply(shadow, to: ctx, outputScale: options.outputScale)
        }
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.translateBy(x: style.padding, y: style.padding)
        for (index, annotation) in document.annotations.enumerated() where !excluded.contains(annotation.id) {
            AnnotationRenderer.draw(annotation, index: index, in: ctx, context: context)
        }
        ctx.endTransparencyLayer()
        ctx.restoreGState()

        if let border = style.border, border.width > 0, !contentRect.isEmpty {
            ctx.setStrokeColor(border.color.cgColor)
            ctx.setLineWidth(border.width)
            ctx.setLineDash(phase: 0, lengths: [])
            ctx.stroke(contentRect.insetBy(dx: border.width / 2, dy: border.width / 2))
        }
    }

    /// Dimensioni dell'ultima immagine di livelli calcolata (per i test).
    private(set) var lastLayerSize: PixelSize?
    var effectCacheMisses: Int { effects.misses }

    /// La regione con le annotazioni sotto `index`, a 1 pixel per pixel del documento.
    /// La chiave dipende solo da ciò che tocca la regione: spostare un oggetto lontano non la invalida.
    private func layers(below index: Int, region: PixelRect, document: PinxelDocument,
                        excluded: Set<UUID>, context: RenderContext) -> (key: String, image: CGImage)? {
        let area = region.cgRect
        let below = document.annotations.prefix(index).enumerated().filter { _, annotation in
            !excluded.contains(annotation.id) && annotation.visualBounds.intersects(area)
        }
        // Il numero di uno step dipende dagli altri step: entra nella chiave.
        let key = "layers|\(region)|\(below.map { "\($0.offset):\(context.stepLabels[$0.element.id] ?? ""):\($0.element)" })"
        let image = effects.image(for: key) {
            guard let ctx = ImageDrawing.makeContext(width: region.width, height: region.height) else { return nil }
            lastLayerSize = PixelSize(width: region.width, height: region.height)
            ctx.translateBy(x: 0, y: CGFloat(region.height))
            ctx.scaleBy(x: 1, y: -1)
            ctx.translateBy(x: -CGFloat(region.x), y: -CGFloat(region.y))
            let flat = RenderContext(contentSize: context.contentSize, stepLabels: context.stepLabels, assets: context.assets,
                                     outputScale: 1, effects: context.effects, layers: context.layers)
            for (offset, annotation) in below {
                AnnotationRenderer.draw(annotation, index: offset, in: ctx, context: flat)
            }
            return ctx.makeImage()
        }
        return image.map { (key, $0) }
    }

    public func renderImage(_ document: PinxelDocument, assets: any AssetProvider, options: RenderOptions = RenderOptions()) throws -> CGImage {
        let canvas = canvasSize(for: document)
        let scaledWidth = canvas.width * options.outputScale
        let scaledHeight = canvas.height * options.outputScale
        let maxPixels = Double(PinxelDocument.maxImageSide * 4)
        guard canvas.width > 0, canvas.height > 0,
              scaledWidth.isFinite, scaledHeight.isFinite,
              scaledWidth > 0, scaledHeight > 0,
              scaledWidth <= maxPixels, scaledHeight <= maxPixels else { throw RenderError.invalidSize }
        // Un lato molto sottile ridotto (es. miniatura di una striscia) resta almeno di 1 pixel.
        let width = max(1, Int(scaledWidth.rounded()))
        let height = max(1, Int(scaledHeight.rounded()))
        guard let ctx = ImageDrawing.makeContext(width: width, height: height) else { throw RenderError.contextCreationFailed }
        try render(document, assets: assets, in: ctx, options: options)
        guard let image = ctx.makeImage() else { throw RenderError.contextCreationFailed }
        return image
    }
}
