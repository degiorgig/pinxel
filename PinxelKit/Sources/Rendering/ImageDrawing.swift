import CoreGraphics
import DocumentModel

enum ImageDrawing {
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    static func makeContext(width: Int, height: Int) -> CGContext? {
        guard width > 0, height > 0 else { return nil }
        return CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    /// Draws `image` in `rect` in an already flipped context (origin at top left).
    static func draw(_ image: CGImage, in rect: CGRect, context ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
        ctx.restoreGState()
    }

    /// Safe conversion to Int even for huge coordinates.
    static func clampedInt(_ value: CGFloat) -> Int {
        Int(max(-10_000_000, min(10_000_000, value)))
    }
}

extension RGBA {
    var cgColor: CGColor {
        CGColor(colorSpace: ImageDrawing.sRGB, components: [red, green, blue, alpha])!
    }
}
