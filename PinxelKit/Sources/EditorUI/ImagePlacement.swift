import CoreGraphics
import DocumentModel

public enum ImagePlacement {
    /// The image reduced so its longer side does not exceed `maxSide` (documents do not accept larger
    /// images and would not reopen); the same image if it already fits.
    public static func fitting(_ image: CGImage, maxSide: Int) -> CGImage? {
        let longest = max(image.width, image.height)
        guard longest > maxSide else { return image }
        let factor = Double(maxSide) / Double(longest)
        return resized(image, to: PixelSize(width: max(1, Int((Double(image.width) * factor).rounded())),
                                            height: max(1, Int((Double(image.height) * factor).rounded()))))
    }

    /// The image resampled to `size` pixels; the same image if it already has those dimensions.
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
        /// Box of the pasted image, in document pixels.
        public var rect: CGRect
        /// Capture size after the paste: larger than the current one if the image did not fit.
        public var imageSize: PixelSize
    }

    /// Where a pasted image goes, at the same density as the document (a Retina screenshot in a Retina capture
    /// keeps its pixels). With `adaptCanvas` the capture takes the image's dimensions, larger or smaller,
    /// and the image covers it entirely; otherwise the capture stays as it is and the image fits in it, centered on `center`.
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

    /// Box of an added image (dragged or ⌥⌘V), centered on `center`, at the document density;
    /// the canvas will adapt to it, so it is not pushed inside. Only the maximum side shrinks it.
    public static func centered(pixelSize: CGSize, imageScale: Double, documentScale: Double, center: CGPoint,
                                maxSide: Int = PinxelDocument.maxImageSide) -> CGRect {
        let factor = documentScale / max(imageScale, 1)
        var width = pixelSize.width * factor
        var height = pixelSize.height * factor
        let shrink = min(1, Double(maxSide) / max(width, 1), Double(maxSide) / max(height, 1))
        width = max(1, (width * shrink).rounded())
        height = max(1, (height * shrink).rounded())
        return CGRect(x: (center.x - width / 2).rounded(), y: (center.y - height / 2).rounded(), width: width, height: height)
    }
}
