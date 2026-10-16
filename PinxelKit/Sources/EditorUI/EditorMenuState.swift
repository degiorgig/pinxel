import Foundation

/// Cosa possono fare i menu con l'editor in primo piano: quali voci sono attive e come si chiama Annulla.
public struct EditorMenuState: Equatable, Sendable {
    public var hasEditor = false
    public var canEdit = false
    public var isEditingText = false
    public var hasSelection = false
    /// Selezione con almeno un oggetto non bloccato, in un documento modificabile.
    public var hasEditableSelection = false
    public var hasLockedSelection = false
    public var hasUnlockedSelection = false
    public var canUndo = false
    public var canRedo = false
    public var undoActionName = ""
    public var redoActionName = ""
    /// `false` quando un'altra finestra (un foglio come Salva o Esporta) ha la tastiera: le voci di modifica
    /// devono raggiungere i suoi campi.
    public var editorIsKey = true

    /// Nessun editor in primo piano.
    public init() {}

    @MainActor
    public init(model: EditorModel) {
        let session = model.session
        hasEditor = true
        canEdit = !session.isReadOnly
        isEditingText = model.editingText != nil
        let selected = session.selectedAnnotations
        hasSelection = !selected.isEmpty
        hasEditableSelection = canEdit && selected.contains { !$0.isLocked }
        hasLockedSelection = canEdit && selected.contains(where: \.isLocked)
        hasUnlockedSelection = hasEditableSelection
        canUndo = session.undoManager.canUndo
        canRedo = session.undoManager.canRedo
        undoActionName = session.undoManager.undoActionName
        redoActionName = session.undoManager.redoActionName
    }

    /// Le voci di modifica senza un editor in primo piano (Preferenze, pannello Salva) o durante la scrittura
    /// di un testo vanno ai campi di testo: restano attive. Altrimenti decide `condition`.
    public func allows(_ condition: Bool) -> Bool {
        !hasEditor || !editorIsKey || isEditingText || condition
    }

    public var undoTitle: String { title("Annulla", undoActionName) }
    public var redoTitle: String { title("Ripristina", redoActionName) }

    private func title(_ verb: String, _ action: String) -> String {
        guard hasEditor, editorIsKey, !isEditingText, let first = action.first else { return verb }
        return "\(verb) \(first.lowercased())\(action.dropFirst())"
    }
}
