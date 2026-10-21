import AppKit
import Persistence

@MainActor
enum DocumentOpener {
    /// Opens the contents in an untitled document; `name` is the proposed name (window and Save).
    @discardableResult
    static func open(_ contents: PinxelFileContents, name: String? = nil) -> NSDocument {
        let document = PinxelFileDocument(contents: contents)
        if let name { document.displayName = name }
        NSDocumentController.shared.addDocument(document)
        document.makeWindowControllers()
        NSApp.setActivationPolicy(.regular)
        document.showWindows()
        NSApp.activate()
        return document
    }

    /// Opens a file (for example a library capture): it saves itself where it is.
    /// Activates before opening: the file loads asynchronously, and an activation requested afterwards is no longer
    /// tied to the click, so macOS would leave the window behind the other apps.
    static func open(url: URL, completion: ((NSDocument?) -> Void)? = nil) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { document, _, error in
            if let error { NSApp.presentError(error) }
            completion?(document)
        }
    }
}
