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
        #expect(canvas.model.session.document.userAnnotations.isEmpty)
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

    @Test func droppedImagePastTheRightEdgeGrowsTheCanvas() throws {
        let canvas = makeCanvas()
        let image = NSImage(cgImage: TestImages.solid(width: 200, height: 100, red: 1, green: 0, blue: 0), size: NSSize(width: 200, height: 100))
        // Center on the bottom-right corner of the capture: half the object is outside.
        let corner = canvas.viewPoint(fromDocument: CGPoint(x: 400, y: 300))
        #expect(canvas.insertImage(image, centeredAt: corner))
        let session = canvas.model.session
        #expect(session.document.imageSize == PixelSize(width: 500, height: 350))
        let annotation = try #require(session.document.annotations.last)
        guard case .image(let data) = annotation.kind else { Issue.record("not an image"); return }
        #expect(data.rect == CGRect(x: 300, y: 250, width: 200, height: 100))
        // A single step to undo.
        session.undoManager.undo()
        #expect(session.document.imageSize == PixelSize(width: 400, height: 300))
        #expect(session.document.userAnnotations.isEmpty)
    }

    @Test func droppedImagePastTheTopLeftGrowsTheCanvasThatWay() throws {
        let canvas = makeCanvas()
        let image = NSImage(cgImage: TestImages.solid(width: 100, height: 80, red: 1, green: 0, blue: 0), size: NSSize(width: 100, height: 80))
        #expect(canvas.insertImage(image, centeredAt: canvas.viewPoint(fromDocument: .zero)))
        let session = canvas.model.session
        // The object sticks out 50×40 at the top left: the canvas grows that way and the capture moves down and to the right.
        #expect(session.document.imageSize == PixelSize(width: 450, height: 340))
        let annotation = try #require(session.document.annotations.last)
        guard case .image(let data) = annotation.kind else { Issue.record("not an image"); return }
        #expect(data.rect == CGRect(x: 0, y: 0, width: 100, height: 80))
        guard case .image(let capture) = session.document.annotations[0].kind else { Issue.record("no capture"); return }
        #expect(capture.rect == CGRect(x: 50, y: 40, width: 400, height: 300))
        session.undoManager.undo()
        #expect(session.document.imageSize == PixelSize(width: 400, height: 300))
        guard case .image(let back) = session.document.annotations[0].kind else { Issue.record("no capture"); return }
        #expect(back.rect == CGRect(x: 0, y: 0, width: 400, height: 300))
    }
}
