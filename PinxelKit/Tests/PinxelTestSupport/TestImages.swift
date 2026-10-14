import CoreGraphics
import Foundation

/// Immagini deterministiche per i test. Coordinate dei commenti: origine in alto a sinistra.
public enum TestImages {
    public static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    public static func makeContext(width: Int, height: Int) -> CGContext {
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
    }

    /// Quattro quadranti: in alto rosso | verde, in basso blu | giallo.
    public static func quadrants(width: Int = 400, height: Int = 300) -> CGImage {
        let ctx = makeContext(width: width, height: height)
        let w = CGFloat(width), h = CGFloat(height)
        // Il contesto bitmap ha origine in basso a sinistra: la metà superiore è y >= h/2.
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: h / 2, width: w / 2, height: h / 2))
        ctx.setFillColor(CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: w / 2, y: h / 2, width: w / 2, height: h / 2))
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w / 2, height: h / 2))
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: w / 2, y: 0, width: w / 2, height: h / 2))
        return ctx.makeImage()!
    }

    public static func solid(width: Int, height: Int, red: CGFloat, green: CGFloat, blue: CGFloat) -> CGImage {
        let ctx = makeContext(width: width, height: height)
        ctx.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    /// Rumore RGB opaco, deterministico (LCG), praticamente incomprimibile.
    public static func noise(width: Int, height: Int, seed: UInt64 = 42) -> CGImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        var state = seed
        bytes.withUnsafeMutableBufferPointer { buffer in
            var i = 0
            while i < buffer.count {
                for c in 0..<3 {
                    state = state &* 6364136223846793005 &+ 1442695040888963407
                    buffer[i + c] = UInt8(truncatingIfNeeded: state >> 56)
                }
                i += 4
            }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: sRGB,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
    }
}
