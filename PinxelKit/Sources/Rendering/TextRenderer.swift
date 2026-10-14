import CoreGraphics
import CoreText
import DocumentModel
import Foundation

enum TextRenderer {
    static func attributedString(_ text: RichText) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let paragraph = paragraphStyle(text.alignment)
        let base = CTFontCreateWithName(text.fontFamily as CFString, text.fontSize, nil)
        for run in text.runs where !run.text.isEmpty {
            var traits: CTFontSymbolicTraits = []
            if run.bold { traits.insert(.traitBold) }
            if run.italic { traits.insert(.traitItalic) }
            let font = traits.isEmpty ? base : (CTFontCreateCopyWithSymbolicTraits(base, text.fontSize, nil, traits, traits) ?? base)
            var attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): (run.color ?? text.color).cgColor,
                NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraph,
            ]
            if run.underline {
                attributes[NSAttributedString.Key(kCTUnderlineStyleAttributeName as String)] = NSNumber(value: CTUnderlineStyle.single.rawValue)
            }
            result.append(NSAttributedString(string: run.text, attributes: attributes))
        }
        return result
    }

    private static func paragraphStyle(_ alignment: RichTextAlignment) -> CTParagraphStyle {
        var value: CTTextAlignment = switch alignment {
        case .left: .left
        case .center: .center
        case .right: .right
        }
        return withUnsafeBytes(of: &value) { buffer in
            var setting = CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: buffer.baseAddress!)
            return CTParagraphStyleCreate(&setting, 1)
        }
    }

    /// Disegna il testo dall'alto verso il basso dentro `rect` (contesto capovolto del documento).
    static func draw(_ text: RichText, in rect: CGRect, inset: CGFloat, ctx: CGContext) {
        let frameRect = rect.standardized.insetBy(dx: inset, dy: inset)
        guard frameRect.width > 0, frameRect.height > 0 else { return }
        let string = attributedString(text)
        guard string.length > 0 else { return }
        let framesetter = CTFramesetterCreateWithAttributedString(string as CFAttributedString)
        let path = CGPath(rect: CGRect(origin: .zero, size: frameRect.size), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        ctx.saveGState()
        ctx.translateBy(x: frameRect.minX, y: frameRect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textMatrix = .identity
        CTFrameDraw(frame, ctx)
        ctx.restoreGState()
    }

    static func drawText(_ data: TextData, style: Style, in ctx: CGContext) {
        let rect = data.rect.standardized
        guard rect.width > 0, rect.height > 0 else { return }
        if let fill = style.fill {
            ctx.setFillColor(fill.cgColor)
            ctx.fill(rect)
        }
        if style.stroke != nil, style.lineWidth > 0 {
            StrokeStyle.apply(style, to: ctx)
            ctx.stroke(rect)
        }
        draw(data.text, in: rect, inset: 4, ctx: ctx)
    }

    static func calloutPath(_ data: CalloutData) -> CGPath {
        let rect = data.rect.standardized
        let radius = max(0, min(12, min(rect.width, rect.height) / 2))
        let bubble = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        let tip = data.tail.tip
        guard !rect.contains(tip) else { return bubble }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let dx = tip.x - center.x
        let dy = tip.y - center.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0, length.isFinite else { return bubble }
        let half = min(data.tail.baseWidth / 2, min(rect.width, rect.height) / 2)
        let px = -dy / length * half
        let py = dx / length * half
        let tail = CGMutablePath()
        tail.move(to: CGPoint(x: center.x + px, y: center.y + py))
        tail.addLine(to: tip)
        tail.addLine(to: CGPoint(x: center.x - px, y: center.y - py))
        tail.closeSubpath()
        return bubble.union(tail)
    }

    static func drawCallout(_ data: CalloutData, style: Style, in ctx: CGContext) {
        let rect = data.rect.standardized
        guard rect.width > 0, rect.height > 0 else { return }
        let path = calloutPath(data)
        ctx.setFillColor((style.fill ?? .white).cgColor)
        ctx.addPath(path)
        ctx.fillPath()
        if style.stroke != nil, style.lineWidth > 0 {
            StrokeStyle.apply(style, to: ctx)
            ctx.addPath(path)
            ctx.strokePath()
        }
        draw(data.text, in: rect, inset: 10, ctx: ctx)
    }

    static func drawStep(_ data: StepData, label: String, style: Style, in ctx: CGContext) {
        guard data.diameter > 0 else { return }
        let rect = CGRect(x: data.center.x - data.diameter / 2, y: data.center.y - data.diameter / 2, width: data.diameter, height: data.diameter)
        ctx.setFillColor((style.fill ?? .accentRed).cgColor)
        ctx.fillEllipse(in: rect)
        if style.stroke != nil, style.lineWidth > 0 {
            StrokeStyle.apply(style, to: ctx)
            ctx.strokeEllipse(in: rect.insetBy(dx: style.lineWidth / 2, dy: style.lineWidth / 2))
        }
        guard !label.isEmpty else { return }

        let fontSize = data.diameter * (label.count > 2 ? 0.38 : 0.5)
        let base = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let font = CTFontCreateCopyWithSymbolicTraits(base, fontSize, nil, .traitBold, .traitBold) ?? base
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): RGBA.white.cgColor,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: label, attributes: attributes) as CFAttributedString)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)

        ctx.saveGState()
        ctx.translateBy(x: data.center.x, y: data.center.y)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: -width / 2, y: -(ascent - descent) / 2)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}
