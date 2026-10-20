import CoreGraphics
import DocumentModel
import Foundation
import ImageIO
import Persistence

public enum ImageImportError: Error, Equatable {
    case unreadable
}

public enum ImageImport {
    /// New document from an image file (PNG, JPEG, HEIC, TIFF…): the image becomes the background, the file stays untouched.
    /// The scale comes from the DPI (144 dpi = 2x); the EXIF orientation is applied; beyond `maxImageSide` the image is shrunk.
    public static func contents(fromImageData data: Data) throws -> PinxelFileContents {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue, width > 0, height > 0 else {
            throw ImageImportError.unreadable
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(max(width, height), PinxelDocument.maxImageSide),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageImportError.unreadable
        }
        let dpi = (properties[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? 72
        let scale = PixelDensity.scale(pixelWidth: width, pointWidth: Double(width) * 72 / (dpi > 0 ? dpi : 72))
        return try CaptureDocumentBuilder.make(image: image, scale: scale, metadata: CaptureMetadata())
    }
}
