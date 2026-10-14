import AppKit
import Persistence

@MainActor
enum DocumentOpener {
    static func open(_ contents: PinxelFileContents) {
        let document = PinxelFileDocument(contents: contents)
        NSDocumentController.shared.addDocument(document)
        document.makeWindowControllers()
        NSApp.setActivationPolicy(.regular)
        document.showWindows()
        NSApp.activate()
    }
}
