import CoreGraphics
import DocumentModel
import Foundation

struct RenderContext {
    /// Content dimensions: effect regions stay inside.
    let contentSize: PixelSize
    let stepLabels: [UUID: String]
    let assets: any AssetProvider
    let outputScale: Double
    let effects: EffectCache
    /// Image of the region (document pixels) with everything beneath the annotation at the given index,
    /// with the key describing its content (for the effects cache).
    let layers: (Int, PixelRect) -> (key: String, image: CGImage)?
}

enum AnnotationRenderer {
    static func draw(_ annotation: Annotation, index: Int, in ctx: CGContext, context: RenderContext) {
        let bounds = annotation.bounds
        guard !bounds.isNull,
              bounds.minX.isFinite, bounds.minY.isFinite,
              bounds.width.isFinite, bounds.height.isFinite else { return }

        ctx.saveGState()
        defer { ctx.restoreGState() }
        if annotation.rotation != 0 {
            ctx.translateBy(x: bounds.midX, y: bounds.midY)
            ctx.rotate(by: annotation.rotation)
            ctx.translateBy(x: -bounds.midX, y: -bounds.midY)
        }
        if let shadow = annotation.style.shadow {
            ShadowStyle.apply(shadow, to: ctx, outputScale: context.outputScale)
        }
        // The highlighter blends in multiply with the background: the layer must be composited in multiply.
        if case .highlight = annotation.kind { ctx.setBlendMode(.multiply) }
        ctx.setAlpha(annotation.style.opacity)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        drawContent(annotation, index: index, in: ctx, context: context)
        ctx.endTransparencyLayer()
    }

    private static func drawContent(_ annotation: Annotation, index: Int, in ctx: CGContext, context: RenderContext) {
        let style = annotation.style
        switch annotation.kind {
        case .arrow(let data): ShapeRenderer.drawArrow(data, style: style, in: ctx)
        case .line(let data): ShapeRenderer.drawLine(data.line, style: style, in: ctx)
        case .shape(let data): ShapeRenderer.drawShape(data, style: style, in: ctx)
        case .pen(let data): ShapeRenderer.drawPen(data, style: style, in: ctx)
        case .highlight(let data): ShapeRenderer.drawHighlight(data, style: style, in: ctx)
        case .text(let data): TextRenderer.drawText(data, style: style, in: ctx)
        case .callout(let data): TextRenderer.drawCallout(data, style: style, in: ctx)
        case .step(let data): TextRenderer.drawStep(data, label: context.stepLabels[annotation.id] ?? "?", style: style, in: ctx)
        case .blur(let data): EffectRenderer.drawBlur(data, index: index, context: context, in: ctx)
        case .pixelate(let data): EffectRenderer.drawPixelate(data, index: index, context: context, in: ctx)
        case .magnifier(let data): EffectRenderer.drawMagnifier(data, index: index, style: style, context: context, in: ctx)
        case .image(let data): EffectRenderer.drawPlacedImage(data, context: context, in: ctx)
        case .unknown: break
        }
    }
}
