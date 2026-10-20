import CoreGraphics
import DocumentModel

public enum BackgroundProcessor {
    /// Applies the operations in sequence; `nil` if an operation produces an empty image.
    public static func process(_ image: CGImage, operations: [ImageOperation]) -> CGImage? {
        var current = image
        for operation in operations {
            guard let next = apply(operation, to: current) else { return nil }
            current = next
        }
        return current
    }

    static func apply(_ operation: ImageOperation, to image: CGImage) -> CGImage? {
        let size = PixelSize(width: image.width, height: image.height)
        switch operation {
        case .crop(let rect):
            let clamped = rect.clamped(to: size)
            guard clamped.width > 0, clamped.height > 0 else { return nil }
            return image.cropping(to: clamped.cgRect)
        case .resize(let target):
            guard let ctx = ImageDrawing.makeContext(width: target.width, height: target.height) else { return nil }
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(origin: .zero, size: target.cgSize))
            return ctx.makeImage()
        case .cutOut(let cut):
            return cutOut(cut, from: image, size: size)
        case .extend:
            let result = operation.resultSize(from: size)
            guard let ctx = ImageDrawing.makeContext(width: result.width, height: result.height) else { return nil }
            // The context has its origin at the bottom left: the image goes at the top.
            ctx.draw(image, in: CGRect(x: 0, y: result.height - size.height, width: size.width, height: size.height))
            return ctx.makeImage()
        }
    }

    private static func cutOut(_ cut: CutOut, from image: CGImage, size: PixelSize) -> CGImage? {
        let start = cut.clampedStart(in: size)
        let length = cut.clampedLength(in: size)
        let result = ImageOperation.cutOut(cut).resultSize(from: size)
        guard let ctx = ImageDrawing.makeContext(width: result.width, height: result.height) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(result.height))
        ctx.scaleBy(x: 1, y: -1)

        let first: PixelRect
        let second: PixelRect
        let secondOrigin: CGPoint
        let seam: (CGPoint, CGPoint)
        switch cut.axis {
        case .horizontal:
            first = PixelRect(x: 0, y: 0, width: size.width, height: start)
            second = PixelRect(x: 0, y: start + length, width: size.width, height: size.height - start - length)
            secondOrigin = CGPoint(x: 0, y: start)
            seam = (CGPoint(x: 0, y: start), CGPoint(x: size.width, y: start))
        case .vertical:
            first = PixelRect(x: 0, y: 0, width: start, height: size.height)
            second = PixelRect(x: start + length, y: 0, width: size.width - start - length, height: size.height)
            secondOrigin = CGPoint(x: start, y: 0)
            seam = (CGPoint(x: start, y: 0), CGPoint(x: start, y: size.height))
        }
        if first.width > 0, first.height > 0, let part = image.cropping(to: first.cgRect) {
            ImageDrawing.draw(part, in: CGRect(x: 0, y: 0, width: first.width, height: first.height), context: ctx)
        }
        if second.width > 0, second.height > 0, let part = image.cropping(to: second.cgRect) {
            ImageDrawing.draw(part, in: CGRect(origin: secondOrigin, size: CGSize(width: second.width, height: second.height)), context: ctx)
        }
        if cut.edge == .zigzag, length > 0 {
            drawZigzag(from: seam.0, to: seam.1, in: ctx)
        }
        return ctx.makeImage()
    }

    private static func drawZigzag(from a: CGPoint, to b: CGPoint, in ctx: CGContext) {
        let horizontal = a.y == b.y
        let length = horizontal ? b.x - a.x : b.y - a.y
        let period: CGFloat = 12
        let amplitude: CGFloat = 4
        let path = CGMutablePath()
        path.move(to: a)
        var t: CGFloat = 0
        var up = true
        while t < length {
            t = min(t + period / 2, length)
            let offset = up ? -amplitude : amplitude
            path.addLine(to: horizontal ? CGPoint(x: a.x + t, y: a.y + offset) : CGPoint(x: a.x + offset, y: a.y + t))
            up.toggle()
        }
        ctx.setStrokeColor(CGColor(gray: 0.45, alpha: 1))
        ctx.setLineWidth(2)
        ctx.setLineJoin(.miter)
        ctx.addPath(path)
        ctx.strokePath()
    }
}
