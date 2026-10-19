import AppKit
import EditorUI
import SwiftUI

/// Menu dell'editor. Le voci inviano azioni alla catena dei responder (tela, finestra o documento in primo
/// piano); lo stato di `EditorFocus` disattiva quelle che non possono fare nulla e dà il nome ad Annulla.
/// Senza editor in primo piano, o mentre si scrive un testo, le voci di modifica restano attive per i campi di testo.
struct EditorCommands: Commands {
    @ObservedObject private var focus = EditorFocus.shared
    @AppStorage("libraryStripVisible") private var stripVisible = true

    var body: some Commands {
        let state = focus.state
        CommandGroup(replacing: .newItem) {
            Button("Nuovo") { AppEnvironment.shared.openBlank() }
                .keyboardShortcut("n")
            Button("Nuova dagli appunti") { AppEnvironment.shared.openClipboard() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Apri…") { NSDocumentController.shared.openDocument(nil) }
                .keyboardShortcut("o")
        }
        CommandGroup(replacing: .saveItem) {
            Button("Salva") { send(#selector(NSDocument.save(_:))) }
                .keyboardShortcut("s")
                .disabled(!state.canEdit)
            Button("Salva con nome…") { send(#selector(NSDocument.saveAs(_:))) }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(!state.canEdit)
            Divider()
            Button("Esporta…") { send(#selector(PinxelFileDocument.exportImage(_:))) }
                .keyboardShortcut("e")
                .disabled(!state.hasEditor)
        }
        CommandGroup(replacing: .undoRedo) {
            Button(state.undoTitle) { send(Selector(("undo:"))) }
                .keyboardShortcut("z")
                .disabled(!state.allows(state.canUndo))
            Button(state.redoTitle) { send(Selector(("redo:"))) }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!state.allows(state.canRedo))
        }
        CommandGroup(replacing: .pasteboard) {
            Button("Taglia") { send(#selector(NSText.cut(_:))) }
                .keyboardShortcut("x")
                .disabled(!state.allows(state.hasEditableSelection))
            // Senza selezione Copia copia l'immagine intera: sempre attiva.
            Button("Copia") { send(#selector(NSText.copy(_:))) }
                .keyboardShortcut("c")
            Button("Incolla") { send(#selector(NSText.paste(_:))) }
                .keyboardShortcut("v")
                .disabled(!state.allows(state.canEdit))
            Button("Incolla senza adattare la tela") { send(#selector(EditorActions.pasteKeepingCanvas(_:))) }
                .keyboardShortcut("v", modifiers: [.command, .option])
                .disabled(!state.canEdit)
            Button("Elimina") { send(#selector(NSText.delete(_:))) }
                .disabled(!state.allows(state.hasEditableSelection))
            Button("Seleziona tutto") { send(#selector(NSText.selectAll(_:))) }
                .keyboardShortcut("a")
        }
        CommandGroup(after: .toolbar) {
            Button(stripVisible ? "Nascondi carosello" : "Mostra carosello") { stripVisible.toggle() }
                .keyboardShortcut("l", modifiers: [.command, .control])
            Divider()
            Group {
                Button("Ingrandisci") { send(#selector(EditorActions.zoomIn(_:))) }
                    .keyboardShortcut("+")
                Button("Riduci") { send(#selector(EditorActions.zoomOut(_:))) }
                    .keyboardShortcut("-")
                Button("Adatta alla finestra") { send(#selector(EditorActions.zoomToFit(_:))) }
                    .keyboardShortcut("0")
                Button("Dimensioni reali") { send(#selector(EditorActions.zoomToActualSize(_:))) }
                    .keyboardShortcut("1")
            }
            .disabled(!state.hasEditor)
        }
        // Grassetto, corsivo e sottolineato sulle parole selezionate mentre si scrive sulla tela. Al posto del
        // menu Formato di sistema, i cui Più grande/Più piccolo (⌘+/⌘−) si scontrerebbero con lo zoom.
        CommandMenu("Formato") {
            Group {
                Button("Grassetto") { send(#selector(PinxelTextView.toggleBoldface(_:))) }
                    .keyboardShortcut("b")
                Button("Corsivo") { send(#selector(PinxelTextView.toggleItalics(_:))) }
                    .keyboardShortcut("i")
                Button("Sottolineato") { send(#selector(NSTextView.underline(_:))) }
                    .keyboardShortcut("u")
            }
            .disabled(!state.isEditingText)
        }
        CommandMenu("Immagine") {
            Group {
                Button("Ritaglia") { focus.model?.tool = .crop }
                Button("Taglia e ricuci") { focus.model?.tool = .cutOut }
                Divider()
                Button("Ridimensiona immagine…") { focus.model?.presentedSheet = .resizeImage }
                    .keyboardShortcut("r", modifiers: [.command, .option])
                Button("Bordo, ombra e margini…") { focus.model?.presentedSheet = .canvasStyle }
            }
            .disabled(!state.canEdit || state.isEditingText)
        }
        CommandMenu("Disponi") {
            Group {
                Button("Porta in primo piano") { send(#selector(EditorActions.bringToFront(_:))) }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                Button("Porta avanti") { send(#selector(EditorActions.bringForward(_:))) }
                    .keyboardShortcut("]")
                Button("Porta indietro") { send(#selector(EditorActions.sendBackward(_:))) }
                    .keyboardShortcut("[")
                Button("Porta in fondo") { send(#selector(EditorActions.sendToBack(_:))) }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
                Divider()
                Button("Duplica") { send(#selector(EditorActions.duplicateSelection(_:))) }
                    .keyboardShortcut("d")
            }
            .disabled(!state.hasEditableSelection)
            Button("Blocca") { send(#selector(EditorActions.lockSelection(_:))) }
                .keyboardShortcut("l")
                .disabled(!state.hasUnlockedSelection)
            Button("Sblocca") { send(#selector(EditorActions.unlockSelection(_:))) }
                .keyboardShortcut("l", modifiers: [.command, .option])
                .disabled(!state.hasLockedSelection)
        }
    }

    private func send(_ action: Selector) {
        NSApp.sendAction(action, to: nil, from: nil)
    }
}
