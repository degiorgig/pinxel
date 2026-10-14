import AppKit
import AppCore
import DocumentModel
import Persistence
import Rendering

@objc(PinxelFileDocument)
final class PinxelFileDocument: NSDocument {
    // NSDocument legge sul thread principale (canConcurrentlyReadDocuments è false), ma `read(from:)` non è isolato.
    nonisolated(unsafe) private(set) var contents: PinxelFileContents?

    convenience init(contents: PinxelFileContents) {
        self.init()
        self.contents = contents
        fileType = "com.degiorgi.pinxel.document"
    }

    override class var autosavesInPlace: Bool { true }

    override func read(from data: Data, ofType typeName: String) throws {
        do {
            contents = try PinxelArchive.read(data)
        } catch {
            throw Self.userError(for: error, data: data)
        }
    }

    override func data(ofType typeName: String) throws -> Data {
        guard let contents else { throw CocoaError(.fileWriteUnknown) }
        guard !contents.isReadOnly else {
            throw NSError(domain: "com.degiorgi.pinxel", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Questo documento è stato creato da una versione più recente di Pinxel e si può solo leggere.",
            ])
        }
        let assets = try contents.assetProvider()
        let thumbnail = try Thumbnailer.make(contents.document, assets: assets)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        return try PinxelArchive.write(document: contents.document, images: contents.images, thumbnail: thumbnail, appVersion: version)
    }

    override func makeWindowControllers() {
        MainActor.assumeIsolated {
            guard let contents else { return }
            do {
                let image = try DocumentRenderer().renderImage(contents.document, assets: try contents.assetProvider())
                addWindowController(ViewerWindowController(image: image, scale: contents.document.scale))
            } catch {
                presentError(error)
            }
        }
    }

    nonisolated private static func userError(for error: Error, data: Data) -> NSError {
        let reason: String
        switch error {
        case PinxelArchiveError.notAPinxelFile: reason = "Il file non è un documento Pinxel."
        case PinxelArchiveError.invalidDocument(let detail): reason = "Il documento è danneggiato (\(detail))."
        case PinxelArchiveError.missingAsset(let name): reason = "Nel documento manca l'immagine \(name)."
        default: reason = "Il file è danneggiato o illeggibile."
        }
        var info: [String: Any] = [NSLocalizedDescriptionKey: reason]
        if PinxelArchive.recoverBackground(data) != nil {
            info[NSLocalizedRecoverySuggestionErrorKey] = "L'immagine originale è integra e si può recuperare."
        }
        return NSError(domain: "com.degiorgi.pinxel", code: 2, userInfo: info)
    }
}
