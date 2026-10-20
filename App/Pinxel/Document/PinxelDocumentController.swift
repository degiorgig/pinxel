import AppCore
import AppKit
import UniformTypeIdentifiers

/// Also opens images (PNG, JPEG, HEIC…): each becomes a new untitled document with the image
/// as its background, so the original file is never overwritten. `.pinxel` documents follow the normal path.
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
                NSLocalizedDescriptionKey: String(localized: "Can't open the image “\(url.lastPathComponent)”."),
                NSLocalizedRecoverySuggestionErrorKey: String(localized: "The file isn't a readable image or is damaged."),
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
