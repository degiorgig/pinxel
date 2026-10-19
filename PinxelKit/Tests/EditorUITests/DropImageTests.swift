import AppKit
import DocumentModel
import PinxelTestSupport
import Rendering
import Testing
@testable import EditorUI

@MainActor
struct DropImageTests {
    private func makeCanvas(readOnly: Bool = false) -> CanvasView {
        let undo = UndoManager()
        undo.groupsByEvent = false
        let session = EditorSession(document: TestDocuments.document(annotations: [], size: PixelSize(width: 400, height: 300), scale: 1),
                                    assets: DictionaryAssetProvider([TestDocuments.background: TestImages.quadrants()]),
                                    undoManager: undo, isReadOnly: readOnly)
        let canvas = CanvasView(model: EditorModel(session: session))
        canvas.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        canvas.needsLayout = true
        canvas.layoutSubtreeIfNeeded()
        return canvas
    }

    @Test func insertedImageBecomesAnAnnotationAndKeepsTheCanvas() throws {
        let canvas = makeCanvas()
        let image = NSImage(cgImage: TestImages.solid(width: 40, height: 20, red: 1, green: 0, blue: 0), size: NSSize(width: 40, height: 20))
        #expect(canvas.insertImage(image, centeredAt: nil))
        let session = canvas.model.session
        #expect(session.document.imageSize == PixelSize(width: 400, height: 300))
        let annotation = try #require(session.document.annotations.last)
        guard case .image(let data) = annotation.kind else { Issue.record("not an image"); return }
        #expect(data.rect.width == 40 && data.rect.height == 20)
        #expect(session.selection == [annotation.id])
    }

    @Test func readOnlyRefusesTheImage() {
        let canvas = makeCanvas(readOnly: true)
        let image = NSImage(cgImage: TestImages.solid(width: 4, height: 4, red: 1, green: 0, blue: 0), size: NSSize(width: 4, height: 4))
        #expect(!canvas.insertImage(image, centeredAt: nil))
        #expect(canvas.model.session.document.annotations.isEmpty)
    }

    @Test func canvasAcceptsImageDrags() {
        let types = makeCanvas().registeredDraggedTypes
        #expect(types.contains(.fileURL) && types.contains(.png))
    }
}

@MainActor
struct DropGrowsCanvasTests {
    private func makeCanvas() -> CanvasView {
        let undo = UndoManager()
        undo.groupsByEvent = false
        let session = EditorSession(document: TestDocuments.document(annotations: [], size: PixelSize(width: 400, height: 300), scale: 1),
                                    assets: DictionaryAssetProvider([TestDocuments.background: TestImages.quadrants()]),
                                    undoManager: undo)
        let canvas = CanvasView(model: EditorModel(session: session))
        canvas.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        canvas.needsLayout = true
        canvas.layoutSubtreeIfNeeded()
        return canvas
    }

    @Test func droppedImagePastTheEdgeGrowsTheCanvas() throws {
        let canvas = makeCanvas()
        let image = NSImage(cgImage: TestImages.solid(width: 200, height: 100, red: 1, green: 0, blue: 0), size: NSSize(width: 200, height: 100))
        // Centro sull'angolo in basso a destra dell'immagine: metà oggetto è fuori.
        let corner = canvas.viewPoint(fromDocument: CGPoint(x: 400, y: 300))
        #expect(canvas.insertImage(image, centeredAt: corner, growsCanvas: true))
        let session = canvas.model.session
        #expect(session.document.imageSize == PixelSize(width: 500, height: 350))
        let annotation = try #require(session.document.annotations.last)
        guard case .image(let data) = annotation.kind else { Issue.record("not an image"); return }
        #expect(data.rect == CGRect(x: 300, y: 250, width: 200, height: 100))
        // Un solo passo da annullare.
        session.undoManager.undo()
        #expect(session.document.imageSize == PixelSize(width: 400, height: 300))
        #expect(session.document.annotations.isEmpty)
    }

    @Test func droppedImagePastTheTopLeftIsMovedInside() throws {
        let canvas = makeCanvas()
        let image = NSImage(cgImage: TestImages.solid(width: 100, height: 80, red: 1, green: 0, blue: 0), size: NSSize(width: 100, height: 80))
        #expect(canvas.insertImage(image, centeredAt: canvas.viewPoint(fromDocument: .zero), growsCanvas: true))
        let session = canvas.model.session
        #expect(session.document.imageSize == PixelSize(width: 400, height: 300))
        let annotation = try #require(session.document.annotations.last)
        guard case .image(let data) = annotation.kind else { Issue.record("not an image"); return }
        #expect(data.rect == CGRect(x: 0, y: 0, width: 100, height: 80))
    }
}
