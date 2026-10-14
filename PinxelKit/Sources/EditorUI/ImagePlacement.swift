import CoreGraphics

public enum ImagePlacement {
    /// L'immagine ridotta perché il lato maggiore non superi `maxSide` (i documenti non accettano immagini più
    /// grandi e non si riaprirebbero); la stessa immagine se ci sta già.
    public static func fitting(_ image: CGImage, maxSide: Int) -> CGImage? {
        let longest = max(image.width, image.height)
        guard longest > maxSide else { return image }
        let factor = Double(maxSide) / Double(longest)
        let width = max(1, Int((Double(image.width) * factor).rounded()))
        let height = max(1, Int((Double(image.height) * factor).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    /// Riquadro di un'immagine incollata, in pixel del documento: alla stessa densità del documento
    /// (uno screenshot Retina in una cattura Retina mantiene i suoi pixel), ridotta entro l'80% della cattura,
    /// centrata in `center`.
    public static func rect(pixelSize: CGSize, imageScale: Double, documentScale: Double, center: CGPoint, imageSize: CGSize) -> CGRect {
        let factor = documentScale / max(imageScale, 1)
        var width = pixelSize.width * factor
        var height = pixelSize.height * factor
        let shrink = min(1, imageSize.width * 0.8 / max(width, 1), imageSize.height * 0.8 / max(height, 1))
        width = max(1, (width * shrink).rounded())
        height = max(1, (height * shrink).rounded())
        return CGRect(x: (center.x - width / 2).rounded(), y: (center.y - height / 2).rounded(), width: width, height: height)
    }
}
