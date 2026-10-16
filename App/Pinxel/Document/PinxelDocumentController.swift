import AppCore
import AppKit
import UniformTypeIdentifiers

/// Apre anche le immagini (PNG, JPEG, HEIC…): ognuna diventa un documento nuovo senza titolo con l'immagine
/// come sfondo, così il file originale non viene mai sovrascritto. I documenti `.pinxel` seguono la via normale.
@MainActor
final class PinxelDocumentController: NSDocumentController {
    override func openDocument(withContentsOf url: URL, display displayDocument: Bool,
                               completionHandler: @escaping (NSDocument?, Bool, (any Error)?) -> Void) {
        guard Self.isPlainImage(url) else {
            super.openDocument(withContentsOf: url, display: displayDocument, completionHandler: completionHandler)
            return
        }
        let name = url.deletingPathExtension().lastPathComponent
        do {
            let contents = try ImageImport.contents(fromImageData: try Data(contentsOf: url))
            let document = DocumentOpener.open(contents, name: name)
            noteNewRecentDocumentURL(url)
            completionHandler(document, false, nil)
        } catch {
            completionHandler(nil, false, NSError(domain: "com.degiorgi.pinxel", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Impossibile aprire l'immagine «\(url.lastPathComponent)».",
                NSLocalizedRecoverySuggestionErrorKey: "Il file non è un'immagine leggibile o è danneggiato.",
                NSUnderlyingErrorKey: error,
            ]))
        }
    }

    static func isPlainImage(_ url: URL) -> Bool {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType) ?? UTType(filenameExtension: url.pathExtension)
        guard let type else { return false }
        return type.conforms(to: .image) && !type.conforms(to: UTType("com.degiorgi.pinxel.document") ?? .data)
    }
}
