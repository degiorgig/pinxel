import AppKit
import Testing
@testable import EditorUI
import DocumentModel
import PinxelTestSupport

@MainActor
struct EditorUICatalogTests {
    @Test func catalogIsComplete() throws {
        #expect(try CatalogValidation.problems(inCatalogAt: Catalogs.url(module: "EditorUI")) == [])
    }

    @Test func toolTitlesAreEnglishInTests() {
        #expect(EditorTool.cutOut.title == "Cut Out")
        #expect(EditorTool.arrow.addCommandName == "Add Arrow")
    }

    @Test func undoTitleUsesTheSystemFormat() {
        var state = EditorMenuState()
        state.hasEditor = true
        state.undoActionName = CommandName.move
        #expect(state.undoTitle == UndoManager().undoMenuTitle(forUndoActionName: CommandName.move))
    }
}
