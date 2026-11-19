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
    /// Output pixels per document pixel.
    public var outputScale: Double
    /// Annotations not to draw (e.g. the text being edited in the editor).
    public var excludedAnnotationIDs: Set<UUID>
    /// Solid color under everything (e.g. white for JPEG).
    public var matte: RGBA?
    /// The first annotations, drawn as one bitmap at `flatteningScale` output pixels per document pixel instead of
    /// one by one (for PDF, where a vector page would keep the pixels under a blur or a cover).
    public var flattenedCount: Int
    public var flatteningScale: Double

    public init(outputScale: Double = 1, excludedAnnotationIDs: Set<UUID> = [], matte: RGBA? = nil,
                flattenedCount: Int = 0, flatteningScale: Double = 1) {
        self.outputScale = outputScale
        self.excludedAnnotationIDs = excludedAnnotationIDs
        self.matte = matte
        self.flattenedCount = flattenedCount
        self.flatteningScale = flatteningScale
    }
}

public enum RenderError: Error, Equatable {
    case invalidSize
    case contextCreationFailed
}

/// Single drawing path for canvas, thumbnails and export.
public final class DocumentRenderer {
    private let effects = EffectCache()

    public init() {}

    /// Size of the canvas (image + padding) in document pixels.
    public func canvasSize(for document: PinxelDocument) -> CGSize {
        let image = document.imageSize
        let padding = document.canvasStyle.padding
        return CGSize(width: Double(image.width) + 2 * padding, height: Double(image.height) + 2 * padding)
    }

    /// Draws the document into `ctx`, whose user space is the output in pixels with origin at bottom left.
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
        // The content in a single layer: the canvas shadow follows its silhouette.
        ctx.saveGState()
        // Only a shadow needs the layer: in a PDF a transparency group would also shift the colors of the capture.
        if let shadow = style.shadow {
            ShadowStyle.apply(shadow, to: ctx, outputScale: options.outputScale)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        ctx.translateBy(x: style.padding, y: style.padding)
        let flattened = min(max(options.flattenedCount, 0), document.annotations.count)
        if flattened > 0 {
            try drawFlattened(document.annotations.prefix(flattened), size: document.imageSize, scale: options.flatteningScale,
                              excluded: excluded, context: context, in: ctx)
        }
        for (index, annotation) in document.annotations.enumerated() where index >= flattened && !excluded.contains(annotation.id) {
            AnnotationRenderer.draw(annotation, index: index, in: ctx, context: context)
        }
        if style.shadow != nil { ctx.endTransparencyLayer() }
        ctx.restoreGState()

        if let border = style.border, border.width > 0, !contentRect.isEmpty {
            ctx.setStrokeColor(border.color.cgColor)
            ctx.setLineWidth(border.width)
            ctx.setLineDash(phase: 0, lengths: [])
            ctx.stroke(contentRect.insetBy(dx: border.width / 2, dy: border.width / 2))
        }
    }

    /// How many annotations, from the bottom, a PDF draws as one bitmap: up to the last one that hides what is below it
    /// (an image, a blur, a pixelation or a filled object). Everything above stays vector, so text remains selectable.
    public static func flattenedCountForPDF(_ document: PinxelDocument) -> Int {
        guard let last = document.annotations.lastIndex(where: { annotation in
            switch annotation.kind {
            case .image, .blur, .pixelate: true
            default: (annotation.style.fill?.alpha ?? 0) > 0
            }
        }) else { return 0 }
        return last + 1
    }

    /// Draws `annotations` into one bitmap of the content at `scale`, then places it in `ctx` (document space, y down).
    private func drawFlattened(_ annotations: ArraySlice<Annotation>, size: PixelSize, scale: Double, excluded: Set<UUID>,
                               context: RenderContext, in ctx: CGContext) throws {
        let width = Double(size.width) * scale
        let height = Double(size.height) * scale
        let maxPixels = Double(PinxelDocument.maxImageSide * 4)
        guard width >= 1, height >= 1, width <= maxPixels, height <= maxPixels else { throw RenderError.invalidSize }
        guard let bitmap = ImageDrawing.makeContext(width: Int(width.rounded()), height: Int(height.rounded())) else {
            throw RenderError.contextCreationFailed
        }
        bitmap.translateBy(x: 0, y: CGFloat(height.rounded()))
        bitmap.scaleBy(x: scale, y: -scale)
        let flat = RenderContext(contentSize: context.contentSize, stepLabels: context.stepLabels, assets: context.assets,
                                 outputScale: scale, effects: context.effects, layers: context.layers)
        for (index, annotation) in zip(annotations.indices, annotations) where !excluded.contains(annotation.id) {
            AnnotationRenderer.draw(annotation, index: index, in: bitmap, context: flat)
        }
        guard let image = bitmap.makeImage() else { throw RenderError.contextCreationFailed }
        ctx.saveGState()
        ctx.translateBy(x: 0, y: CGFloat(size.height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: Double(size.width), height: Double(size.height)))
        ctx.restoreGState()
    }

    /// Size of the last layers image computed (for tests).
    private(set) var lastLayerSize: PixelSize?
    var effectCacheMisses: Int { effects.misses }

    /// The region with the annotations below `index`, at 1 pixel per document pixel.
    /// The key depends only on what touches the region: moving a distant object does not invalidate it.
    private func layers(below index: Int, region: PixelRect, document: PinxelDocument,
                        excluded: Set<UUID>, context: RenderContext) -> (key: String, image: CGImage)? {
        let area = region.cgRect
        let below = document.annotations.prefix(index).enumerated().filter { _, annotation in
            !excluded.contains(annotation.id) && annotation.visualBounds.intersects(area)
        }
        // A step's number depends on the other steps: it goes into the key.
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
        // A very thin side after scaling down (e.g. a strip thumbnail) stays at least 1 pixel.
        let width = max(1, Int(scaledWidth.rounded()))
        let height = max(1, Int(scaledHeight.rounded()))
        guard let ctx = ImageDrawing.makeContext(width: width, height: height) else { throw RenderError.contextCreationFailed }
        try render(document, assets: assets, in: ctx, options: options)
        guard let image = ctx.makeImage() else { throw RenderError.contextCreationFailed }
        return image
    }
}
