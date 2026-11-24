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
    /// Annotations drawn together as one bitmap, at `flatteningScale` output pixels per document pixel, below the others
    /// (for PDF, where a vector page would keep whatever a later object hides). See `flattenedForPDF`.
    public var flattenedAnnotationIDs: Set<UUID>
    public var flatteningScale: Double
    /// Flattened annotations drawn again as vectors over the bitmap, where nothing hides them (see `pdfLayers`).
    public var redrawnAnnotationIDs: Set<UUID>

    public init(outputScale: Double = 1, excludedAnnotationIDs: Set<UUID> = [], matte: RGBA? = nil,
                flattenedAnnotationIDs: Set<UUID> = [], flatteningScale: Double = 1, redrawnAnnotationIDs: Set<UUID> = []) {
        self.outputScale = outputScale
        self.excludedAnnotationIDs = excludedAnnotationIDs
        self.matte = matte
        self.flattenedAnnotationIDs = flattenedAnnotationIDs
        self.flatteningScale = flatteningScale
        self.redrawnAnnotationIDs = redrawnAnnotationIDs
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
        let flattened = options.flattenedAnnotationIDs
        let redrawn = options.redrawnAnnotationIDs.intersection(flattened)
        if !flattened.isEmpty {
            try drawFlattened(document.annotations, ids: flattened, redrawn: redrawn, size: document.imageSize, scale: options.flatteningScale,
                              excluded: excluded, context: context, in: ctx)
        }
        for (index, annotation) in document.annotations.enumerated()
        where (!flattened.contains(annotation.id) || redrawn.contains(annotation.id)) && !excluded.contains(annotation.id) {
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

    /// How a PDF draws the annotations, so that nothing hidden in the picture is left in the file.
    public struct PDFLayers: Equatable, Sendable {
        /// Drawn together as one bitmap: whatever they hide is gone from the file.
        public var flattened: Set<UUID>
        /// Flattened ones drawn again as vectors over the bitmap: opaque marks with nothing above them that could hide
        /// them, so arrows and shapes stay sharp when zooming and text stays selectable. Their bitmap copy lies exactly
        /// under the vector one (without its shadow, which would darken twice).
        public var redrawn: Set<UUID>
    }

    public static func pdfLayers(_ document: PinxelDocument) -> PDFLayers {
        let annotations = document.annotations
        let flattened = flattenedForPDF(document)
        let bounds = annotations.map(\.visualBounds)
        let flatIndices = annotations.indices.filter { flattened.contains(annotations[$0].id) }
        let redrawn = flatIndices.filter { index in
            redrawable(annotations[index]) && !flatIndices.contains { above in
                above > index && !bounds[above].isNull && !bounds[index].isNull && bounds[above].intersects(bounds[index])
            }
        }
        return PDFLayers(flattened: flattened, redrawn: Set(redrawn.map { annotations[$0].id }))
    }

    /// The annotations a PDF draws as one bitmap: every object with something above it that can hide it, together with
    /// what hides it. Objects that overlap one of them from below join too, to keep the stacking order; the rest stays
    /// vector and is drawn above the bitmap, which it does not touch.
    public static func flattenedForPDF(_ document: PinxelDocument) -> Set<UUID> {
        let annotations = document.annotations
        let bounds = annotations.map(\.visualBounds)
        func overlap(_ a: Int, _ b: Int) -> Bool { !bounds[a].isNull && !bounds[b].isNull && bounds[a].intersects(bounds[b]) }
        var flat = Set<Int>()
        for upper in annotations.indices where hides(annotations[upper]) {
            for lower in 0..<upper where overlap(lower, upper) {
                flat.insert(lower)
                flat.insert(upper)
            }
        }
        // A vector object drawn after the bitmap must not belong below any of its contents.
        var changed = true
        while changed {
            changed = false
            for index in annotations.indices where !flat.contains(index) && flat.contains(where: { $0 > index && overlap(index, $0) }) {
                flat.insert(index)
                changed = true
            }
        }
        return Set(flat.map { annotations[$0].id })
    }

    /// Whether the annotation can cover what is below it. Opaque text can, with its glyphs too (a row of █ over a
    /// password); only see-through text without a box leaves it visible.
    private static func hides(_ annotation: Annotation) -> Bool {
        guard case .text = annotation.kind else { return true }
        let box = annotation.style.fill != nil || (annotation.style.stroke != nil && annotation.style.lineWidth > 0)
        return box || isOpaque(annotation)
    }

    /// Vector marks that look the same drawn once or twice: opaque, with no effect computed from what is below.
    private static func redrawable(_ annotation: Annotation) -> Bool {
        switch annotation.kind {
        case .arrow, .line, .shape, .text, .callout, .step, .pen: isOpaque(annotation)
        default: false
        }
    }

    private static func isOpaque(_ annotation: Annotation) -> Bool {
        let style = annotation.style
        var colors = [style.stroke, style.fill].compactMap { $0 }
        switch annotation.kind {
        case .text(let data): colors += [data.text.color] + data.text.runs.compactMap(\.color)
        case .callout(let data): colors += [data.text.color] + data.text.runs.compactMap(\.color)
        default: break
        }
        return style.opacity >= 1 && colors.allSatisfy { $0.alpha >= 1 }
    }

    /// Draws the annotations in `ids`, in their order, into one bitmap of the content at `scale`, then places it in `ctx`
    /// (document space, y down).
    private func drawFlattened(_ annotations: [Annotation], ids: Set<UUID>, redrawn: Set<UUID>, size: PixelSize, scale: Double,
                               excluded: Set<UUID>, context: RenderContext, in ctx: CGContext) throws {
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
        for (index, annotation) in annotations.enumerated() where ids.contains(annotation.id) && !excluded.contains(annotation.id) {
            var drawn = annotation
            // Its shadow comes with the vector copy drawn above.
            if redrawn.contains(annotation.id) { drawn.style.shadow = nil }
            AnnotationRenderer.draw(drawn, index: index, in: bitmap, context: flat)
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
