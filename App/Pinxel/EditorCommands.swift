import AppKit
import EditorUI
import SwiftUI

/// Menu dell'editor. Le voci inviano azioni alla catena dei responder: risponde la tela, la finestra
/// o il documento in primo piano; senza editor aperto non succede nulla.
struct EditorCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .saveItem) {
            Button("Salva") { send(#selector(NSDocument.save(_:))) }
                .keyboardShortcut("s")
            Button("Salva con nome…") { send(#selector(NSDocument.saveAs(_:))) }
                .keyboardShortcut("s", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .undoRedo) {
            Button("Annulla") { send(Selector(("undo:"))) }
                .keyboardShortcut("z")
            Button("Ripristina") { send(Selector(("redo:"))) }
                .keyboardShortcut("z", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .pasteboard) {
            Button("Taglia") { send(#selector(NSText.cut(_:))) }
                .keyboardShortcut("x")
            Button("Copia") { send(#selector(NSText.copy(_:))) }
                .keyboardShortcut("c")
            Button("Incolla") { send(#selector(NSText.paste(_:))) }
                .keyboardShortcut("v")
            Button("Elimina") { send(#selector(NSText.delete(_:))) }
            Button("Seleziona tutto") { send(#selector(NSText.selectAll(_:))) }
                .keyboardShortcut("a")
        }
        CommandGroup(after: .toolbar) {
            Button("Ingrandisci") { send(#selector(EditorActions.zoomIn(_:))) }
                .keyboardShortcut("+")
            Button("Riduci") { send(#selector(EditorActions.zoomOut(_:))) }
                .keyboardShortcut("-")
            Button("Adatta alla finestra") { send(#selector(EditorActions.zoomToFit(_:))) }
                .keyboardShortcut("0")
            Button("Dimensioni reali") { send(#selector(EditorActions.zoomToActualSize(_:))) }
                .keyboardShortcut("1")
        }
        CommandMenu("Disponi") {
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
            Button("Blocca") { send(#selector(EditorActions.lockSelection(_:))) }
                .keyboardShortcut("l")
            Button("Sblocca") { send(#selector(EditorActions.unlockSelection(_:))) }
                .keyboardShortcut("l", modifiers: [.command, .option])
        }
    }

    private func send(_ action: Selector) {
        NSApp.sendAction(action, to: nil, from: nil)
    }
}
