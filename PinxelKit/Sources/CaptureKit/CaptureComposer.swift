import CoreGraphics

/// Image of a screen taken at capture start, at its native pixels.
public struct FrozenDisplay: Sendable {
    public let info: DisplayInfo
    public let image: CGImage

    public init(info: DisplayInfo, image: CGImage) {
        self.info = info
        self.image = image
    }
}

public enum CaptureComposer {
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// Crops `rect` (global points, origin at top left) from the frozen images.
    /// The result uses the largest scale among the screens touched; areas outside the screens stay transparent.
    public static func compose(_ rect: CGRect, from displays: [FrozenDisplay]) -> (image: CGImage, scale: Double)? {
        let requested = rect.standardized
        guard requested.width >= 1, requested.height >= 1 else { return nil }
        let touched = displays.filter { $0.info.frame.intersects(requested) }
        guard let scale = touched.map(\.info.scale).max() else { return nil }
        // Align the selection to the pixel grid: with fractional coordinates the image would be resampled (blurred).
        let minX = (requested.minX * scale).rounded(.down) / scale
        let minY = (requested.minY * scale).rounded(.down) / scale
        let maxX = (requested.maxX * scale).rounded(.up) / scale
        let maxY = (requested.maxY * scale).rounded(.up) / scale
        let selection = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

        let width = Int((selection.width * scale).rounded())
        let height = Int((selection.height * scale).rounded())
        guard width > 0, height > 0,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        // Space in global points with origin at the selection's top left.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: scale, y: -scale)
        ctx.translateBy(x: -selection.minX, y: -selection.minY)
        for display in touched {
            let frame = display.info.frame
            ctx.saveGState()
            ctx.translateBy(x: frame.minX, y: frame.maxY)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(display.image, in: CGRect(origin: .zero, size: frame.size))
            ctx.restoreGState()
        }
        guard let image = ctx.makeImage() else { return nil }
        return (image, scale)
    }
}
