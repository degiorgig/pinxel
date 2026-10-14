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
    /// Le ombre di Core Graphics ignorano la CTM: offset e blur vanno in pixel di output,
    /// e la y è invertita perché il contesto del documento è capovolto.
    static func apply(_ shadow: Shadow, to ctx: CGContext, outputScale: Double) {
        ctx.setShadow(
            offset: CGSize(width: shadow.offset.width * outputScale, height: -shadow.offset.height * outputScale),
            blur: shadow.blur * outputScale,
            color: shadow.color.cgColor
        )
    }
}
