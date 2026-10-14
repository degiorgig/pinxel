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

    /// Disegna `image` in `rect` in un contesto già capovolto (origine in alto a sinistra).
    static func draw(_ image: CGImage, in rect: CGRect, context ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
        ctx.restoreGState()
    }

    /// Conversione sicura a Int anche per coordinate enormi.
    static func clampedInt(_ value: CGFloat) -> Int {
        Int(max(-10_000_000, min(10_000_000, value)))
    }
}

extension RGBA {
    var cgColor: CGColor {
        CGColor(colorSpace: ImageDrawing.sRGB, components: [red, green, blue, alpha])!
    }
}
