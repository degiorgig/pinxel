import AppKit
import AppCore
import DocumentModel
import EditorUI
import Persistence
import Rendering

extension Notification.Name {
    /// Un documento è stato scritto su disco; `object` è il suo URL. La libreria aggiorna miniatura e dimensioni.
    static let pinxelDocumentDidSave = Notification.Name("com.degiorgi.pinxel.documentDidSave")
}

@objc(PinxelFileDocument)
final class PinxelFileDocument: NSDocument {
    // NSDocument legge e scrive sul thread principale (canConcurrentlyReadDocuments e
    // canAsynchronouslyWrite sono false), ma i metodi non sono isolati.
    nonisolated(unsafe) private(set) var contents: PinxelFileContents?
    /// Creato con la finestra: da lì in poi il documento aggiornato è `editorModel.session.document`.
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
        // Ripristina, Versioni o file cambiato su disco: l'editor già aperto deve mostrare il contenuto riletto,
        // altrimenti il salvataggio successivo riscriverebbe quello vecchio.
        MainActor.assumeIsolated { editorModel?.session.replaceDocument(loaded.document) }
    }

    override func data(ofType typeName: String) throws -> Data {
        guard var contents else { throw CocoaError(.fileWriteUnknown) }
        let edited = MainActor.assumeIsolated { () -> (document: PinxelDocument, pasted: [ImageAssetRef: Data])? in
            guard let session = editorModel?.session else { return nil }
            // Dopo il salvataggio una nuova modifica deve essere un passo nuovo, o NSDocument non la vede.
            session.breakCoalescing()
            return (session.document, session.assets.addedData)
        }
        if let edited {
            contents.document = edited.document
            // Le immagini incollate entrano nell'archivio; `PinxelArchive.write` scrive solo quelle usate.
            contents.images.merge(edited.pasted) { current, _ in current }
        }
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

    // Il testo che si sta scrivendo sulla tela entra nel documento prima di salvare (anche in automatico)
    // e prima di decidere se chiedere di salvare alla chiusura.
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

    /// Il modello dell'editor per questo documento, senza finestra: serve anche per mostrarlo in una finestra già aperta.
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
            // Senza immagini il documento non si può mostrare: avvisa e chiudi, niente documenti senza finestra.
            presentError(error)
            perform(#selector(NSDocument.close), with: nil, afterDelay: 0)
            return nil
        }
    }

    /// Esporta… dal menu File (arriva qui dalla catena dei responder).
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
        case PinxelArchiveError.notAPinxelFile: reason = "Il file non è un documento Pinxel."
        case PinxelArchiveError.invalidDocument(let detail): reason = "Il documento è danneggiato (\(detail))."
        case PinxelArchiveError.missingAsset(let name): reason = "Nel documento manca l'immagine \(name)."
        default: reason = "Il file è danneggiato o illeggibile."
        }
        var info: [String: Any] = [NSLocalizedDescriptionKey: reason]
        if PinxelArchive.recoverBackground(data) != nil {
            info[NSLocalizedRecoverySuggestionErrorKey] = "L'immagine originale è integra: puoi aprirla in un documento nuovo."
            info[NSLocalizedRecoveryOptionsErrorKey] = ["Apri l'immagine", "Annulla"]
            info[NSRecoveryAttempterErrorKey] = RecoveryAttempter(data: data)
        }
        return NSError(domain: "com.degiorgi.pinxel", code: 2, userInfo: info)
    }
}
