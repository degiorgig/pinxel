import Foundation

/// What the menus can do with the editor in front: which items are enabled and what Undo is called.
public struct EditorMenuState: Equatable, Sendable {
    public var hasEditor = false
    public var canEdit = false
    public var isEditingText = false
    public var hasSelection = false
    /// Selection with at least one unlocked object, in an editable document.
    public var hasEditableSelection = false
    public var hasLockedSelection = false
    public var hasUnlockedSelection = false
    public var canUndo = false
    public var canRedo = false
    public var undoActionName = ""
    public var redoActionName = ""
    /// `false` when another window (a sheet like Save or Export) has the keyboard: the edit items
    /// must reach its fields.
    public var editorIsKey = true

    /// No editor in front.
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

    /// Edit items with no editor in front (Preferences, Save panel) or while typing
    /// text go to the text fields: they stay enabled. Otherwise `condition` decides.
    public func allows(_ condition: Bool) -> Bool {
        !hasEditor || !editorIsKey || isEditingText || condition
    }

    /// "Undo Move" in the macOS form for the app's language; with no name, just "Undo".
    @MainActor public var undoTitle: String {
        showsActionName(undoActionName)
            ? UndoManager().undoMenuTitle(forUndoActionName: undoActionName)
            : String(localized: "Undo", bundle: .module, comment: "Edit menu")
    }

    @MainActor public var redoTitle: String {
        showsActionName(redoActionName)
            ? UndoManager().redoMenuTitle(forUndoActionName: redoActionName)
            : String(localized: "Redo", bundle: .module, comment: "Edit menu")
    }

    private func showsActionName(_ action: String) -> Bool {
        hasEditor && editorIsKey && !isEditingText && !action.isEmpty
    }
}
