import AppKit
import DocumentModel
import PinxelTestSupport
import Rendering
import Testing
@testable import EditorUI

@MainActor
struct EditorMenuStateTests {
    private let free = Annotation(id: TestDocuments.id(1), kind: .shape(ShapeData(rect: CGRect(x: 0, y: 0, width: 50, height: 50), shape: .rectangle)))
    private var locked: Annotation {
        Annotation(id: TestDocuments.id(2), kind: .shape(ShapeData(rect: CGRect(x: 100, y: 0, width: 50, height: 50), shape: .rectangle)), isLocked: true)
    }

    private func makeModel(_ annotations: [Annotation], readOnly: Bool = false) -> EditorModel {
        let undo = UndoManager()
        undo.groupsByEvent = false
        return EditorModel(session: EditorSession(document: TestDocuments.document(annotations: annotations),
                                                  assets: DictionaryAssetProvider([:]), undoManager: undo, isReadOnly: readOnly))
    }

    @Test func withoutAnEditorEverythingPassesThrough() {
        let state = EditorMenuState()
        #expect(!state.hasEditor)
        #expect(state.allows(false))
        #expect(state.undoTitle == "Undo" && state.redoTitle == "Redo")
    }

    @Test func selectionAndLocksDecideTheArrangeItems() {
        let model = makeModel([free, locked])
        #expect(!EditorMenuState(model: model).hasSelection)
        #expect(!EditorMenuState(model: model).allows(false))
        model.session.selection = [free.id, locked.id]
        var state = EditorMenuState(model: model)
        #expect(state.hasEditableSelection && state.hasLockedSelection && state.hasUnlockedSelection)
        model.session.selection = [locked.id]
        state = EditorMenuState(model: model)
        #expect(state.hasSelection && !state.hasEditableSelection && state.hasLockedSelection && !state.hasUnlockedSelection)
    }

    @Test func readOnlyDocumentsCanEditNothing() {
        let model = makeModel([free, locked], readOnly: true)
        model.session.selection = [free.id, locked.id]
        let state = EditorMenuState(model: model)
        #expect(state.hasEditor && !state.canEdit)
        #expect(!state.hasEditableSelection && !state.hasLockedSelection)
    }

    @Test func undoAndRedoNameTheAction() {
        let model = makeModel([])
        model.session.perform(AddAnnotations([free], name: EditorTool.arrow.addCommandName))
        var state = EditorMenuState(model: model)
        #expect(state.canUndo && state.undoTitle == UndoManager().undoMenuTitle(forUndoActionName: EditorTool.arrow.addCommandName))
        model.session.undoManager.undo()
        state = EditorMenuState(model: model)
        #expect(state.canRedo && state.redoTitle == UndoManager().redoMenuTitle(forUndoActionName: EditorTool.arrow.addCommandName))
        #expect(!state.canUndo && state.undoTitle == "Undo")
    }

    @Test func editingTextPassesEverythingThroughToTheTextView() {
        let model = makeModel([free])
        model.editingText = RichText("x")
        let state = EditorMenuState(model: model)
        #expect(state.isEditingText && state.allows(false))
        #expect(state.undoTitle == "Undo")
    }

    @Test func commandEqualsZoomsIn() throws {
        let session = EditorSession(document: TestDocuments.document(annotations: [], size: PixelSize(width: 400, height: 300), scale: 1),
                                    assets: DictionaryAssetProvider([TestDocuments.background: TestImages.quadrants()]))
        let canvas = CanvasView(model: EditorModel(session: session))
        canvas.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        canvas.needsLayout = true
        canvas.layoutSubtreeIfNeeded()
        let before = canvas.viewport.zoom
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0,
                                                  context: nil, characters: "=", charactersIgnoringModifiers: "=", isARepeat: false, keyCode: 24))
        #expect(canvas.performKeyEquivalent(with: event))
        #expect(canvas.viewport.zoom > before)
    }
}
