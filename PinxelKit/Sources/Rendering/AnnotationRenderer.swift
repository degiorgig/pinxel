import CoreGraphics
import DocumentModel
import Foundation

struct RenderContext {
    /// Sfondo dopo le operazioni immagine, senza annotazioni (sorgente di sfocatura, pixel e lente).
    let background: CGImage
    let stepLabels: [UUID: String]
    let assets: any AssetProvider
    let outputScale: Double
    let effects: EffectCache
}

enum AnnotationRenderer {
    static func draw(_ annotation: Annotation, in ctx: CGContext, context: RenderContext) {
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
        // L'evidenziatore si fonde in multiply con lo sfondo: il livello va composto in multiply.
        if case .highlight = annotation.kind { ctx.setBlendMode(.multiply) }
        ctx.setAlpha(annotation.style.opacity)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        drawContent(annotation, in: ctx, context: context)
        ctx.endTransparencyLayer()
    }

    private static func drawContent(_ annotation: Annotation, in ctx: CGContext, context: RenderContext) {
        switch annotation.kind {
        default:
            break
        }
    }
}
