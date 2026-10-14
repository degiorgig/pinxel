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
    /// Byte codificati (PNG/HEIC) di ogni immagine referenziata, sfondo incluso.
    public var images: [ImageAssetRef: Data]
    public var thumbnail: Data?
    /// Il file è di una versione più recente: va aperto in sola lettura.
    public var isReadOnly: Bool

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
    public static let currentVersion = 1

    public static func requiredAssets(of document: PinxelDocument) -> [ImageAssetRef] {
        var refs = [document.background]
        var seen: Set<ImageAssetRef> = [document.background]
        for annotation in document.annotations {
            if case .image(let data) = annotation.kind, seen.insert(data.asset).inserted {
                refs.append(data.asset)
            }
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

    public static func read(_ data: Data, limits: ZipLimits = .default) throws -> PinxelFileContents {
        let zip = try ZipReader(data, limits: limits)
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

        let document: PinxelDocument
        do {
            document = try decoder.decode(PinxelDocument.self, from: zip.data(for: "document.json"))
        } catch let error as ZipError {
            if case .missingEntry = error { throw PinxelArchiveError.invalidDocument("document.json missing") }
            throw error
        } catch {
            throw PinxelArchiveError.invalidDocument(String(describing: error))
        }

        var images: [ImageAssetRef: Data] = [:]
        for ref in requiredAssets(of: document) {
            do {
                images[ref] = try zip.data(for: ref.name)
            } catch ZipError.missingEntry(_) {
                throw PinxelArchiveError.missingAsset(ref.name)
            }
        }
        let thumbnail = try? zip.data(for: "thumbnail.png")
        return PinxelFileContents(document: document, images: images, thumbnail: thumbnail, isReadOnly: manifest.version > currentVersion)
    }

    /// Prova a estrarre solo lo sfondo da un file danneggiato.
    public static func recoverBackground(_ data: Data) -> Data? {
        guard let zip = try? ZipReader(data) else { return nil }
        for name in ["background.png", "background.heic"] {
            if let background = try? zip.data(for: name) { return background }
        }
        return nil
    }
}
