import AppKit
import EditorUI
import Library
import os

@MainActor
enum LibraryOpener {
    private static let logger = Logger(subsystem: "com.degiorgi.pinxel", category: "library")

    /// Click on a thumbnail: brings forward the window that already shows it, otherwise shows it in the same window.
    /// An untitled document with something in it first enters the library, so it is not lost.
    static func open(_ item: Library.LibraryItem, from window: NSWindow?, newWindow: Bool = false) {
        let library = AppEnvironment.shared.library
        let url = library.url(for: item).standardizedFileURL
        let existing = NSDocumentController.shared.documents.first { $0.fileURL?.standardizedFileURL == url }
        let controller = window?.windowController as? EditorWindowController
        guard !newWindow || existing != nil, let controller, let current = controller.document as? PinxelFileDocument else {
            if let existing { existing.showWindows() } else { DocumentOpener.open(url: url) }
            return
        }
        let decision = LibraryOpenDecision.decide(targetAlreadyOpen: existing != nil, current: content(of: current, controller: controller))
        logger.notice("open \(item.file, privacy: .public): \(String(describing: decision), privacy: .public)")
        switch decision {
        case .focusExisting:
            existing?.showWindows()
        case .replaceInWindow:
            // It saves where it is (if it has a file), then the new capture enters the same window.
            guard current.fileURL != nil else { return replace(current, in: controller, with: url, item: item) }
            current.autosave(withImplicitCancellability: false) { error in
                MainActor.assumeIsolated {
                    // If saving fails the window stays as it is: no edits are lost.
                    if let error {
                        _ = current.presentError(error)
                        return
                    }
                    replace(current, in: controller, with: url, item: item)
                }
            }
        case .keepInLibraryThenReplace:
            let date = current.editorModel?.session.document.metadata.captureDate ?? Date()
            let destination: URL
            do {
                destination = try library.store.newURL(for: date)
            } catch {
                _ = current.presentError(error)
                return
            }
            current.save(to: destination, ofType: "com.degiorgi.pinxel.document", for: .saveAsOperation) { error in
                MainActor.assumeIsolated {
                    if let error {
                        _ = current.presentError(error)
                        return
                    }
                    replace(current, in: controller, with: url, item: item)
                }
            }
        }
    }

    private static func content(of document: PinxelFileDocument, controller: EditorWindowController) -> WindowContent {
        if let url = document.fileURL {
            return AppEnvironment.shared.library.file(for: url) != nil ? .libraryItem : .otherFile
        }
        let blank = (controller.model.canvas as? CanvasView)?.isBlank ?? false
        return .untitled(blank: blank && !document.isDocumentEdited)
    }

    /// The window switches to the new document: frame, toolbar, panel and carousel stay, the canvas changes.
    private static func replace(_ current: PinxelFileDocument, in controller: EditorWindowController, with url: URL, item: Library.LibraryItem) {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: false) { document, _, error in
            MainActor.assumeIsolated {
                if let error {
                    _ = NSApp.presentError(error)
                    return
                }
                guard let next = document as? PinxelFileDocument, let model = next.makeEditorModel() else { return }
                current.removeWindowController(controller)
                current.close()
                next.addWindowController(controller)
                controller.show(model)
                controller.stripState.selection = [item.file]
                controller.synchronizeWindowTitleWithDocumentName()
            }
        }
    }
}
