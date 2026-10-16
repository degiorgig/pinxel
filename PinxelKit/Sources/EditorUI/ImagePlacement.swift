import CoreGraphics
import DocumentModel

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

    public struct Placement: Equatable, Sendable {
        /// Riquadro dell'immagine incollata, in pixel del documento.
        public var rect: CGRect
        /// Dimensioni della cattura dopo l'incolla: più grandi delle attuali se l'immagine non ci stava.
        public var imageSize: PixelSize
    }

    /// Dove va un'immagine incollata: alla stessa densità del documento (uno screenshot Retina in una cattura Retina
    /// mantiene i suoi pixel) e a grandezza piena. Se è più grande della cattura, la cattura si allarga per contenerla;
    /// altrimenti va centrata in `center` e tenuta dentro la cattura.
    public static func place(pixelSize: CGSize, imageScale: Double, documentScale: Double, center: CGPoint, imageSize: PixelSize,
                             maxSide: Int = PinxelDocument.maxImageSide) -> Placement {
        let factor = documentScale / max(imageScale, 1)
        var width = pixelSize.width * factor
        var height = pixelSize.height * factor
        let shrink = min(1, Double(maxSide) / max(width, 1), Double(maxSide) / max(height, 1))
        width = max(1, (width * shrink).rounded())
        height = max(1, (height * shrink).rounded())
        let canvas = PixelSize(width: max(imageSize.width, Int(width)), height: max(imageSize.height, Int(height)))
        let x = min(max((center.x - width / 2).rounded(), 0), Double(canvas.width) - width)
        let y = min(max((center.y - height / 2).rounded(), 0), Double(canvas.height) - height)
        return Placement(rect: CGRect(x: x, y: y, width: width, height: height), imageSize: canvas)
    }
}
