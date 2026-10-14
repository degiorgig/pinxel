import CoreGraphics

/// Immagine di uno schermo scattata all'avvio della cattura, ai suoi pixel nativi.
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

    /// Ritaglia `rect` (punti globali, origine in alto a sinistra) dalle immagini congelate.
    /// Il risultato usa la scala massima tra gli schermi toccati; le zone fuori dagli schermi restano trasparenti.
    public static func compose(_ rect: CGRect, from displays: [FrozenDisplay]) -> (image: CGImage, scale: Double)? {
        let selection = rect.standardized
        guard selection.width >= 1, selection.height >= 1 else { return nil }
        let touched = displays.filter { $0.info.frame.intersects(selection) }
        guard let scale = touched.map(\.info.scale).max() else { return nil }

        let width = Int((selection.width * scale).rounded())
        let height = Int((selection.height * scale).rounded())
        guard width > 0, height > 0,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        // Spazio in punti globali con origine in alto a sinistra della selezione.
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
