import CoreGraphics

public struct RGBA8: Equatable, Sendable, CustomStringConvertible {
    public var r: UInt8, g: UInt8, b: UInt8, a: UInt8
    public init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }
    public var description: String { "RGBA8(\(r), \(g), \(b), \(a))" }
}

/// Premultiplied RGBA8 pixels in sRGB; row 0 is the top one.
public struct PixelBuffer: Equatable {
    public let width: Int
    public let height: Int
    public let bytes: [UInt8]

    public init(_ image: CGImage) {
        width = image.width
        height = image.height
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        data.withUnsafeMutableBytes { buffer in
            let ctx = CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: TestImages.sRGB,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        bytes = data
    }

    public func pixel(x: Int, y: Int) -> RGBA8 {
        let i = (y * width + x) * 4
        return RGBA8(r: bytes[i], g: bytes[i + 1], b: bytes[i + 2], a: bytes[i + 3])
    }

    /// Fraction (0...1) of pixels with at least one channel differing by more than `channelTolerance`.
    /// Returns 1 if the dimensions differ.
    public func differingPixelFraction(from other: PixelBuffer, channelTolerance: Int = 8) -> Double {
        guard width == other.width, height == other.height else { return 1 }
        var differing = 0
        var i = 0
        while i < bytes.count {
            for c in 0..<4 where abs(Int(bytes[i + c]) - Int(other.bytes[i + c])) > channelTolerance {
                differing += 1
                break
            }
            i += 4
        }
        return Double(differing) / Double(max(width * height, 1))
    }
}
