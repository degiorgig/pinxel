import AppKit
import DocumentModel
import PinxelTestSupport
import Rendering
import Testing
@testable import EditorUI

@MainActor
struct BlankCanvasTests {
    private func makeCanvas(_ document: PinxelDocument) -> CanvasView {
        let undo = UndoManager()
        undo.groupsByEvent = false
        let session = EditorSession(document: document, assets: DictionaryAssetProvider([TestDocuments.background: TestImages.quadrants()]), undoManager: undo)
        let canvas = CanvasView(model: EditorModel(session: session))
        canvas.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        canvas.layoutSubtreeIfNeeded()
        return canvas
    }

    /// Il documento di Nuovo: nessun oggetto, tela vuota.
    private var blank: PinxelDocument {
        PinxelDocument(canvasSize: PixelSize(width: 0, height: 0), scale: 1, metadata: CaptureMetadata())
    }

    @Test func aDocumentWithNothingOnItIsBlank() {
        #expect(makeCanvas(blank).isBlank)
    }

    @Test func aCaptureIsNotBlank() {
        #expect(!makeCanvas(TestDocuments.document(annotations: [])).isBlank)
    }

    @Test func drawingOnTheBlankDocumentMakesItNotBlank() {
        let canvas = makeCanvas(blank)
        let shape = Annotation(id: TestDocuments.id(1), kind: .shape(ShapeData(rect: CGRect(x: 10, y: 10, width: 40, height: 30), shape: .rectangle)))
        canvas.model.session.perform(AddAnnotations([shape]))
        #expect(!canvas.isBlank)
        // La tela si è adattata al rettangolo, tratto compreso.
        #expect(canvas.model.session.document.canvasSize == PixelSize(width: 44, height: 34))
    }

    @Test func aCanvasStyleMakesItNotBlank() {
        var styled = blank
        styled.canvasStyle.padding = 20
        #expect(!makeCanvas(styled).isBlank)
    }
}
