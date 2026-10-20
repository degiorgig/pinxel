import AppKit
import AppCore
import DocumentModel
import EditorUI
import Persistence
import Rendering

extension Notification.Name {
    /// A document was written to disk; `object` is its URL. The library updates thumbnail and dimensions.
    static let pinxelDocumentDidSave = Notification.Name("com.degiorgi.pinxel.documentDidSave")
}

@objc(PinxelFileDocument)
final class PinxelFileDocument: NSDocument {
    // NSDocument reads and writes on the main thread (canConcurrentlyReadDocuments and
    // canAsynchronouslyWrite are false), but the methods are not isolated.
    nonisolated(unsafe) private(set) var contents: PinxelFileContents?
    /// Created with the window: from then on the updated document is `editorModel.session.document`.
    nonisolated(unsafe) private(set) var editorModel: EditorModel?

    convenience init(contents: PinxelFileContents) {
        self.init()
        self.contents = contents
        fileType = "com.degiorgi.pinxel.document"
    }

    override class var autosavesInPlace: Bool { true }

    override func canAsynchronouslyWrite(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType) -> Bool {
        false
    }

    override func read(from data: Data, ofType typeName: String) throws {
        let loaded: PinxelFileContents
        do {
            loaded = try PinxelArchive.read(data)
        } catch {
            throw Self.userError(for: error, data: data)
        }
        contents = loaded
        // Revert, Versions or file changed on disk: the already open editor must show the re-read content,
        // otherwise the next save would rewrite the old one.
        MainActor.assumeIsolated { editorModel?.session.replaceDocument(loaded.document) }
    }

    override func data(ofType typeName: String) throws -> Data {
        guard var contents else { throw CocoaError(.fileWriteUnknown) }
        let edited = MainActor.assumeIsolated { () -> (document: PinxelDocument, pasted: [ImageAssetRef: Data])? in
            guard let session = editorModel?.session else { return nil }
            // After saving, a new change must be a new step, or NSDocument does not see it.
            session.breakCoalescing()
            return (session.document, session.assets.addedData)
        }
        if let edited {
            contents.document = edited.document
            // Pasted images enter the archive; `PinxelArchive.write` writes only the ones in use.
            contents.images.merge(edited.pasted) { current, _ in current }
        }
        guard !contents.isReadOnly else {
            throw NSError(domain: "com.degiorgi.pinxel", code: 1, userInfo: [
                NSLocalizedDescriptionKey: String(localized: "This document was created by a newer version of Pinxel and can only be viewed."),
            ])
        }
        let assets = try contents.assetProvider()
        let thumbnail = try Thumbnailer.make(contents.document, assets: assets)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        return try PinxelArchive.write(document: contents.document, images: contents.images, thumbnail: thumbnail, appVersion: version)
    }

    // The text being written on the canvas enters the document before saving (even automatically)
    // and before deciding whether to ask to save on close.
    override func save(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
                       completionHandler: @escaping (Error?) -> Void) {
        MainActor.assumeIsolated { editorModel?.commitTextEditing() }
        super.save(to: url, ofType: typeName, for: saveOperation) { error in
            if error == nil { NotificationCenter.default.post(name: .pinxelDocumentDidSave, object: url) }
            completionHandler(error)
        }
    }

    override func canClose(withDelegate delegate: Any, shouldClose shouldCloseSelector: Selector?, contextInfo: UnsafeMutableRawPointer?) {
        MainActor.assumeIsolated { editorModel?.commitTextEditing() }
        super.canClose(withDelegate: delegate, shouldClose: shouldCloseSelector, contextInfo: contextInfo)
    }

    override func makeWindowControllers() {
        MainActor.assumeIsolated {
            guard let model = makeEditorModel() else { return }
            addWindowController(EditorWindowController(model: model))
        }
    }

    /// The editor model for this document, without a window: also used to show it in an already open window.
    @MainActor
    func makeEditorModel() -> EditorModel? {
        if let editorModel { return editorModel }
        guard let contents else { return nil }
        do {
            let session = EditorSession(
                document: contents.document,
                assets: try contents.assetProvider(),
                undoManager: undoManager ?? UndoManager(),
                isReadOnly: contents.isReadOnly
            )
            let model = EditorModel(session: session)
            editorModel = model
            return model
        } catch {
            // Without images the document cannot be shown: warn and close, no documents without a window.
            presentError(error)
            perform(#selector(NSDocument.close), with: nil, afterDelay: 0)
            return nil
        }
    }

    /// Export… from the File menu (arrives here through the responder chain).
    @objc func exportImage(_ sender: Any?) {
        MainActor.assumeIsolated {
            guard let model = editorModel, let window = windowControllers.first?.window else { return }
            model.commitTextEditing()
            let session = model.session
            let name = displayName ?? "Pinxel"
            Task { await ExportPanel.run(document: session.document, assets: session.assets, suggestedName: name, window: window) }
        }
    }

    nonisolated private static func userError(for error: Error, data: Data) -> NSError {
        let reason: String
        switch error {
        case PinxelArchiveError.notAPinxelFile: reason = String(localized: "The file isn't a Pinxel document.")
        case PinxelArchiveError.invalidDocument(let detail): reason = String(localized: "The document is damaged (\(detail)).")
        case PinxelArchiveError.missingAsset(let name): reason = String(localized: "The image \(name) is missing from the document.")
        default: reason = String(localized: "The file is damaged or unreadable.")
        }
        var info: [String: Any] = [NSLocalizedDescriptionKey: reason]
        if PinxelArchive.recoverBackground(data) != nil {
            info[NSLocalizedRecoverySuggestionErrorKey] = String(localized: "The original image is intact: you can open it in a new document.")
            info[NSLocalizedRecoveryOptionsErrorKey] = [String(localized: "Open Image"), String(localized: "Cancel")]
            info[NSRecoveryAttempterErrorKey] = RecoveryAttempter(data: data)
        }
        return NSError(domain: "com.degiorgi.pinxel", code: 2, userInfo: info)
    }
}
