import CoreGraphics
import DocumentModel
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageCodecError: Error, Equatable {
    case encodingFailed(String)
    case decodingFailed
}

public enum ImageCodec {
    /// Oltre questa dimensione il PNG dello sfondo viene sostituito da HEIC.
    public static let heicThreshold = 20 * 1024 * 1024

    public static func encode(_ image: CGImage, type: UTType, quality: Double? = nil) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, type.identifier as CFString, 1, nil) else {
            throw ImageCodecError.encodingFailed(type.identifier)
        }
        var properties: [CFString: Any] = [:]
        if let quality { properties[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImageCodecError.encodingFailed(type.identifier) }
        return data as Data
    }

    public static func decode(_ data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ImageCodecError.decodingFailed
        }
        return image
    }

    /// Dimensioni dichiarate dall'immagine, lette dall'intestazione senza decodificarla.
    public static func pixelSize(of data: Data) -> PixelSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return PixelSize(width: width, height: height)
    }

    /// PNG; HEIC se il PNG supera `heicThreshold` e il sistema sa codificare HEIC.
    public static func encodeBackground(_ image: CGImage) throws -> (ref: ImageAssetRef, data: Data) {
        let png = try encode(image, type: .png)
        if png.count > heicThreshold, let heic = try? encode(image, type: .heic, quality: 0.9) {
            return (ImageAssetRef(name: "background.heic"), heic)
        }
        return (ImageAssetRef(name: "background.png"), png)
    }
}
