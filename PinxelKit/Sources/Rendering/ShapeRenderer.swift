import CoreGraphics
import DocumentModel

enum ShapeRenderer {
    static func drawLine(_ line: LineGeometry, style: Style, in ctx: CGContext) {
        guard style.stroke != nil, style.lineWidth > 0 else { return }
        StrokeStyle.apply(style, to: ctx)
        ctx.move(to: line.start)
        ctx.addLine(to: line.end)
        ctx.strokePath()
    }

    static func drawArrow(_ data: ArrowData, style: Style, in ctx: CGContext) {
        guard let color = style.stroke, style.lineWidth > 0 else { return }
        let start = data.line.start
        let end = data.line.end
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0.5 else {
            drawLine(data.line, style: style, in: ctx)
            return
        }
        let ux = dx / length
        let uy = dy / length
        let headLength = min(max(style.lineWidth * 3, 10), length * 0.5)

        var shaftStart = start
        var shaftEnd = end
        if data.heads.start == .triangle {
            shaftStart = CGPoint(x: start.x + ux * headLength * 0.8, y: start.y + uy * headLength * 0.8)
        }
        if data.heads.end == .triangle {
            shaftEnd = CGPoint(x: end.x - ux * headLength * 0.8, y: end.y - uy * headLength * 0.8)
        }
        StrokeStyle.apply(style, to: ctx)
        ctx.move(to: shaftStart)
        ctx.addLine(to: shaftEnd)
        ctx.strokePath()

        ctx.setLineDash(phase: 0, lengths: [])
        drawHead(data.heads.end, tip: end, ux: ux, uy: uy, headLength: headLength, color: color, in: ctx)
        drawHead(data.heads.start, tip: start, ux: -ux, uy: -uy, headLength: headLength, color: color, in: ctx)
    }

    private static func drawHead(_ head: HeadStyle, tip: CGPoint, ux: CGFloat, uy: CGFloat, headLength: CGFloat, color: RGBA, in ctx: CGContext) {
        let halfWidth = headLength * 0.6
        let base = CGPoint(x: tip.x - ux * headLength, y: tip.y - uy * headLength)
        let left = CGPoint(x: base.x - uy * halfWidth, y: base.y + ux * halfWidth)
        let right = CGPoint(x: base.x + uy * halfWidth, y: base.y - ux * halfWidth)
        switch head {
        case .none:
            return
        case .triangle:
            ctx.setFillColor(color.cgColor)
            ctx.move(to: tip)
            ctx.addLine(to: left)
            ctx.addLine(to: right)
            ctx.closePath()
            ctx.fillPath()
        case .open:
            ctx.move(to: left)
            ctx.addLine(to: tip)
            ctx.addLine(to: right)
            ctx.strokePath()
        case .circle:
            let radius = headLength * 0.4
            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: CGRect(x: tip.x - radius, y: tip.y - radius, width: radius * 2, height: radius * 2))
        }
    }

    static func shapePath(_ shape: ShapeType, in rect: CGRect) -> CGPath {
        switch shape {
        case .rectangle:
            return CGPath(rect: rect, transform: nil)
        case .roundedRectangle(let cornerRadius):
            let radius = max(0, min(cornerRadius, min(rect.width, rect.height) / 2))
            return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        case .ellipse:
            return CGPath(ellipseIn: rect, transform: nil)
        }
    }

    static func drawShape(_ data: ShapeData, style: Style, in ctx: CGContext) {
        let rect = data.rect.standardized
        guard rect.width > 0, rect.height > 0 else { return }
        let path = shapePath(data.shape, in: rect)
        if let fill = style.fill {
            ctx.setFillColor(fill.cgColor)
            ctx.addPath(path)
            ctx.fillPath()
        }
        if style.stroke != nil, style.lineWidth > 0 {
            StrokeStyle.apply(style, to: ctx)
            ctx.addPath(path)
            ctx.strokePath()
        }
    }

    /// With `smoothing > 0` the points are joined by quadratic curves passing through the midpoints.
    static func smoothedPath(_ points: [CGPoint], smoothing: Double) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        if points.count == 1 {
            path.addLine(to: first)
            return path
        }
        if smoothing <= 0 || points.count < 3 {
            for point in points.dropFirst() { path.addLine(to: point) }
            return path
        }
        for i in 1..<(points.count - 1) {
            let mid = CGPoint(x: (points[i].x + points[i + 1].x) / 2, y: (points[i].y + points[i + 1].y) / 2)
            path.addQuadCurve(to: mid, control: points[i])
        }
        path.addLine(to: points[points.count - 1])
        return path
    }

    static func drawPen(_ data: PenData, style: Style, in ctx: CGContext) {
        guard style.stroke != nil, style.lineWidth > 0, !data.path.points.isEmpty else { return }
        StrokeStyle.apply(style, to: ctx)
        ctx.addPath(smoothedPath(data.path.points, smoothing: data.smoothing))
        ctx.strokePath()
    }

    static func drawHighlight(_ data: HighlightData, style: Style, in ctx: CGContext) {
        guard style.stroke != nil, style.lineWidth > 0, !data.path.points.isEmpty else { return }
        StrokeStyle.apply(style, to: ctx)
        ctx.addPath(smoothedPath(data.path.points, smoothing: 1))
        ctx.strokePath()
    }
}
