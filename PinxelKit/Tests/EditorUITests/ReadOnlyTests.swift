import AppKit
import DocumentModel
import PinxelTestSupport
import Rendering
import Testing
@testable import EditorUI

@MainActor
struct ReadOnlyTests {
    private func makeModel() -> EditorModel {
        EditorModel(session: EditorSession(document: TestDocuments.document(annotations: [], size: PixelSize(width: 400, height: 300), scale: 1),
                                           assets: DictionaryAssetProvider([TestDocuments.background: TestImages.quadrants()]), isReadOnly: true))
    }

    @Test func readOnlyCanvasIgnoresCreationTools() {
        let canvas = CanvasView(model: makeModel())
        canvas.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        canvas.model.tool = .shape
        canvas.send(.down(CGPoint(x: 10, y: 10), [], clickCount: 1))
        canvas.send(.drag(CGPoint(x: 60, y: 60), []))
        canvas.send(.up(CGPoint(x: 60, y: 60), []))
        #expect(canvas.model.session.document.userAnnotations.isEmpty)
        #expect(canvas.model.session.selection.isEmpty)
        #expect(canvas.model.session.preview == nil)
    }

    @Test func readOnlyModelIgnoresToolKeys() {
        let model = makeModel()
        #expect(!model.selectTool(forKey: "r"))
        #expect(model.tool == .select)
    }
}
