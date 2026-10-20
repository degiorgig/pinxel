import CoreGraphics
import DocumentModel

enum StrokeStyle {
    static func apply(_ style: Style, to ctx: CGContext) {
        ctx.setLineWidth(style.lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        if let stroke = style.stroke { ctx.setStrokeColor(stroke.cgColor) }
        switch style.dash {
        case .solid: ctx.setLineDash(phase: 0, lengths: [])
        case .dashed: ctx.setLineDash(phase: 0, lengths: [style.lineWidth * 3, style.lineWidth * 2])
        case .dotted: ctx.setLineDash(phase: 0, lengths: [0.01, style.lineWidth * 2])
        }
    }
}

enum ShadowStyle {
    /// Core Graphics shadows ignore the CTM: offset and blur are in output pixels,
    /// and y is inverted because the document context is flipped.
    static func apply(_ shadow: Shadow, to ctx: CGContext, outputScale: Double) {
        ctx.setShadow(
            offset: CGSize(width: shadow.offset.width * outputScale, height: -shadow.offset.height * outputScale),
            blur: shadow.blur * outputScale,
            color: shadow.color.cgColor
        )
    }
}
