import CoreGraphics
import DocumentModel
import Foundation
import ImageIO
import Persistence

public enum ImageImportError: Error, Equatable {
    case unreadable
}

public enum ImageImport {
    /// Documento nuovo da un file immagine (PNG, JPEG, HEIC, TIFF…): l'immagine diventa lo sfondo, il file resta intatto.
    /// La scala viene dai DPI (144 dpi = 2x); l'orientamento EXIF è applicato; oltre `maxImageSide` l'immagine si riduce.
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
