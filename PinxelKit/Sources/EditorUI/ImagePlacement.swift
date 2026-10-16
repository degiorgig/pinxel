import CoreGraphics
import DocumentModel

public enum ImagePlacement {
    /// L'immagine ridotta perché il lato maggiore non superi `maxSide` (i documenti non accettano immagini più
    /// grandi e non si riaprirebbero); la stessa immagine se ci sta già.
    public static func fitting(_ image: CGImage, maxSide: Int) -> CGImage? {
        let longest = max(image.width, image.height)
        guard longest > maxSide else { return image }
        let factor = Double(maxSide) / Double(longest)
        return resized(image, to: PixelSize(width: max(1, Int((Double(image.width) * factor).rounded())),
                                            height: max(1, Int((Double(image.height) * factor).rounded()))))
    }

    /// L'immagine ricampionata a `size` pixel; la stessa immagine se ha già quelle dimensioni.
    public static func resized(_ image: CGImage, to size: PixelSize) -> CGImage? {
        guard image.width != size.width || image.height != size.height else { return image }
        let width = size.width, height = size.height
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
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

    /// Dove va un'immagine incollata, alla stessa densità del documento (uno screenshot Retina in una cattura Retina
    /// mantiene i suoi pixel). Con `adaptCanvas` la cattura prende le dimensioni dell'immagine, più grande o più piccola,
    /// e l'immagine la copre tutta; altrimenti la cattura resta com'è e l'immagine ci entra, centrata in `center`.
    public static func place(pixelSize: CGSize, imageScale: Double, documentScale: Double, center: CGPoint, imageSize: PixelSize,
                             adaptCanvas: Bool, maxSide: Int = PinxelDocument.maxImageSide) -> Placement {
        let factor = documentScale / max(imageScale, 1)
        var width = pixelSize.width * factor
        var height = pixelSize.height * factor
        let limit = adaptCanvas ? CGSize(width: maxSide, height: maxSide) : imageSize.cgSize
        let shrink = min(1, limit.width / max(width, 1), limit.height / max(height, 1))
        width = max(1, (width * shrink).rounded())
        height = max(1, (height * shrink).rounded())
        if adaptCanvas {
            return Placement(rect: CGRect(x: 0, y: 0, width: width, height: height), imageSize: PixelSize(width: Int(width), height: Int(height)))
        }
        let x = min(max((center.x - width / 2).rounded(), 0), Double(imageSize.width) - width)
        let y = min(max((center.y - height / 2).rounded(), 0), Double(imageSize.height) - height)
        return Placement(rect: CGRect(x: x, y: y, width: width, height: height), imageSize: imageSize)
    }
}
