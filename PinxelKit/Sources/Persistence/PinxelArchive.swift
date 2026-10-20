import DocumentModel
import Foundation
import Rendering

public struct PinxelManifest: Codable, Equatable, Sendable {
    public var format: String
    public var version: Int
    public var appVersion: String

    public init(format: String, version: Int, appVersion: String) {
        self.format = format
        self.version = version
        self.appVersion = appVersion
    }
}

public struct PinxelFileContents: Sendable {
    public var document: PinxelDocument
    /// Encoded bytes (PNG/HEIC) of every referenced image.
    public var images: [ImageAssetRef: Data]
    public var thumbnail: Data?
    /// The file is from a newer version: it must be opened read-only.
    public var isReadOnly: Bool

    public init(document: PinxelDocument, images: [ImageAssetRef: Data], thumbnail: Data? = nil, isReadOnly: Bool = false) {
        self.document = document
        self.images = images
        self.thumbnail = thumbnail
        self.isReadOnly = isReadOnly
    }

    public func assetProvider() throws -> DictionaryAssetProvider {
        var decoded: [ImageAssetRef: CGImage] = [:]
        for (ref, data) in images { decoded[ref] = try ImageCodec.decode(data) }
        return DictionaryAssetProvider(decoded)
    }
}

public enum PinxelArchiveError: Error, Equatable {
    case notAPinxelFile
    case invalidDocument(String)
    case missingAsset(String)
}

public enum PinxelArchive {
    public static let currentVersion = 2

    public static func requiredAssets(of document: PinxelDocument) -> [ImageAssetRef] {
        var refs: [ImageAssetRef] = []
        var seen: Set<ImageAssetRef> = []
        for annotation in document.annotations {
            if case .image(let data) = annotation.kind, seen.insert(data.asset).inserted { refs.append(data.asset) }
        }
        return refs
    }

    public static func write(document: PinxelDocument, images: [ImageAssetRef: Data], thumbnail: Data, appVersion: String) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var zip = ZipWriter()
        let manifest = PinxelManifest(format: "pinxel", version: currentVersion, appVersion: appVersion)
        try zip.add(name: "manifest.json", data: encoder.encode(manifest), method: .deflate)
        try zip.add(name: "document.json", data: encoder.encode(document), method: .deflate)
        for ref in requiredAssets(of: document) {
            guard let data = images[ref] else { throw PinxelArchiveError.missingAsset(ref.name) }
            try zip.add(name: ref.name, data: data, method: .store)
        }
        try zip.add(name: "thumbnail.png", data: thumbnail, method: .store)
        return try zip.finish()
    }

    /// Only the document, for the library index: does not read the images.
    public static func readDocument(_ data: Data, limits: ZipLimits = .default) throws -> PinxelDocument {
        try manifestAndDocument(ZipReader(data, limits: limits)).1
    }

    /// The thumbnail saved in the file, if any.
    public static func readThumbnail(_ data: Data) -> Data? {
        try? ZipReader(data).data(for: "thumbnail.png")
    }

    /// Manifest and document validated, without reading the images. A version 1 file also comes back as `legacy`.
    private static func manifestAndDocument(_ zip: ZipReader) throws -> (PinxelManifest, PinxelDocument, LegacyDocumentV1?) {
        let decoder = JSONDecoder()

        let manifest: PinxelManifest
        do {
            manifest = try decoder.decode(PinxelManifest.self, from: zip.data(for: "manifest.json"))
        } catch ZipError.missingEntry(_) {
            throw PinxelArchiveError.notAPinxelFile
        } catch is DecodingError {
            throw PinxelArchiveError.notAPinxelFile
        }
        guard manifest.format == "pinxel" else { throw PinxelArchiveError.notAPinxelFile }

        let json: Data
        do {
            json = try zip.data(for: "document.json")
        } catch ZipError.missingEntry(_) {
            throw PinxelArchiveError.invalidDocument("document.json missing")
        }
        if manifest.version < 2 {
            let legacy: LegacyDocumentV1
            do {
                legacy = try decoder.decode(LegacyDocumentV1.self, from: json)
            } catch {
                throw PinxelArchiveError.invalidDocument(String(describing: error))
            }
            if let reason = legacy.validationError() { throw PinxelArchiveError.invalidDocument(reason) }
            let document = legacy.converted(capture: legacy.background)
            if let reason = document.validationError() { throw PinxelArchiveError.invalidDocument(reason) }
            return (manifest, document, legacy)
        }
        let document: PinxelDocument
        do {
            document = try decoder.decode(PinxelDocument.self, from: json)
        } catch {
            throw PinxelArchiveError.invalidDocument(String(describing: error))
        }
        if let reason = document.validationError() { throw PinxelArchiveError.invalidDocument(reason) }
        return (manifest, document, nil)
    }

    public static func read(_ data: Data, limits: ZipLimits = .default) throws -> PinxelFileContents {
        let zip = try ZipReader(data, limits: limits)
        let (manifest, read, legacy) = try manifestAndDocument(zip)
        var document = read

        var images: [ImageAssetRef: Data] = [:]
        let limit = PinxelDocument.maxImageSide
        for ref in requiredAssets(of: document) {
            let data: Data
            do {
                data = try zip.data(for: ref.name)
            } catch ZipError.missingEntry(_) {
                throw PinxelArchiveError.missingAsset(ref.name)
            }
            // Header check: no decoding of huge or inconsistent images.
            guard let size = ImageCodec.pixelSize(of: data),
                  (1...limit).contains(size.width), (1...limit).contains(size.height) else {
                throw PinxelArchiveError.invalidDocument("invalid or too large image: \(ref.name)")
            }
            images[ref] = data
        }
        if let legacy {
            guard let backgroundData = images[legacy.background],
                  let size = ImageCodec.pixelSize(of: backgroundData), size == legacy.canvasSize else {
                throw PinxelArchiveError.invalidDocument("the background does not match the document size")
            }
            // With no operations the background stays the file it is; otherwise it is processed once and saved as PNG.
            if !legacy.imageOperations.isEmpty {
                guard let processed = BackgroundProcessor.process(try ImageCodec.decode(backgroundData), operations: legacy.imageOperations) else {
                    throw PinxelArchiveError.invalidDocument("the background cannot be processed")
                }
                let ref = ImageAssetRef(name: "assets/capture-v1.png")
                images[legacy.background] = nil
                images[ref] = try ImageCodec.encode(processed, type: .png)
                document = legacy.converted(capture: ref)
            }
        }
        let thumbnail = try? zip.data(for: "thumbnail.png")
        return PinxelFileContents(document: document, images: images, thumbnail: thumbnail, isReadOnly: manifest.version > currentVersion)
    }

    /// Tries to extract just the background from a damaged file.
    public static func recoverBackground(_ data: Data) -> Data? {
        guard let zip = try? ZipReader(data) else { return nil }
        for name in ["background.png", "background.heic"] {
            if let background = try? zip.data(for: name) { return background }
        }
        return nil
    }
}
