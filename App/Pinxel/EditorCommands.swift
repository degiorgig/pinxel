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
            Button("New") { AppEnvironment.shared.openBlank() }
                .keyboardShortcut("n")
            Button("New from Clipboard") { AppEnvironment.shared.openClipboard() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Open…") { NSDocumentController.shared.openDocument(nil) }
                .keyboardShortcut("o")
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save") { send(#selector(NSDocument.save(_:))) }
                .keyboardShortcut("s")
                .disabled(!state.canEdit)
            Button("Save As…") { send(#selector(NSDocument.saveAs(_:))) }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(!state.canEdit)
            Divider()
            Button("Export…") { send(#selector(PinxelFileDocument.exportImage(_:))) }
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
            Button("Cut") { send(#selector(NSText.cut(_:))) }
                .keyboardShortcut("x")
                .disabled(!state.allows(state.hasEditableSelection))
            // Senza selezione Copia copia l'immagine intera: sempre attiva.
            Button("Copy") { send(#selector(NSText.copy(_:))) }
                .keyboardShortcut("c")
            Button("Paste") { send(#selector(NSText.paste(_:))) }
                .keyboardShortcut("v")
                .disabled(!state.allows(state.canEdit))
            Button("Paste as Image") { send(#selector(EditorActions.pasteKeepingCanvas(_:))) }
                .keyboardShortcut("v", modifiers: [.command, .option])
                .disabled(!state.canEdit)
            Button("Delete") { send(#selector(NSText.delete(_:))) }
                .disabled(!state.allows(state.hasEditableSelection))
            Button("Select All") { send(#selector(NSText.selectAll(_:))) }
                .keyboardShortcut("a")
        }
        CommandGroup(after: .toolbar) {
            Button(stripVisible ? String(localized: "Hide Strip") : String(localized: "Show Strip")) { stripVisible.toggle() }
                .keyboardShortcut("l", modifiers: [.command, .control])
            Divider()
            Group {
                Button("Zoom In") { send(#selector(EditorActions.zoomIn(_:))) }
                    .keyboardShortcut("+")
                Button("Zoom Out") { send(#selector(EditorActions.zoomOut(_:))) }
                    .keyboardShortcut("-")
                Button("Zoom to Fit") { send(#selector(EditorActions.zoomToFit(_:))) }
                    .keyboardShortcut("0")
                Button("Actual Size") { send(#selector(EditorActions.zoomToActualSize(_:))) }
                    .keyboardShortcut("1")
            }
            .disabled(!state.hasEditor)
        }
        // Grassetto, corsivo e sottolineato sulle parole selezionate mentre si scrive sulla tela. Al posto del
        // menu Formato di sistema, i cui Più grande/Più piccolo (⌘+/⌘−) si scontrerebbero con lo zoom.
        CommandMenu("Format") {
            Group {
                Button("Bold") { send(#selector(PinxelTextView.toggleBoldface(_:))) }
                    .keyboardShortcut("b")
                Button("Italic") { send(#selector(PinxelTextView.toggleItalics(_:))) }
                    .keyboardShortcut("i")
                Button("Underline") { send(#selector(NSTextView.underline(_:))) }
                    .keyboardShortcut("u")
            }
            .disabled(!state.isEditingText)
        }
        CommandMenu("Image") {
            Group {
                Button("Crop") { focus.model?.tool = .crop }
                Button("Cut Out") { focus.model?.tool = .cutOut }
                Divider()
                Button("Resize Image…") { focus.model?.presentedSheet = .resizeImage }
                    .keyboardShortcut("r", modifiers: [.command, .option])
                Button("Border, Shadow and Padding…") { focus.model?.presentedSheet = .canvasStyle }
            }
            .disabled(!state.canEdit || state.isEditingText)
        }
        CommandMenu("Arrange") {
            Group {
                Button("Bring to Front") { send(#selector(EditorActions.bringToFront(_:))) }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                Button("Bring Forward") { send(#selector(EditorActions.bringForward(_:))) }
                    .keyboardShortcut("]")
                Button("Send Backward") { send(#selector(EditorActions.sendBackward(_:))) }
                    .keyboardShortcut("[")
                Button("Send to Back") { send(#selector(EditorActions.sendToBack(_:))) }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
                Divider()
                Button("Duplicate") { send(#selector(EditorActions.duplicateSelection(_:))) }
                    .keyboardShortcut("d")
            }
            .disabled(!state.hasEditableSelection)
            Button("Lock") { send(#selector(EditorActions.lockSelection(_:))) }
                .keyboardShortcut("l")
                .disabled(!state.hasUnlockedSelection)
            Button("Unlock") { send(#selector(EditorActions.unlockSelection(_:))) }
                .keyboardShortcut("l", modifiers: [.command, .option])
                .disabled(!state.hasLockedSelection)
        }
    }

    private func send(_ action: Selector) {
        NSApp.sendAction(action, to: nil, from: nil)
    }
}
