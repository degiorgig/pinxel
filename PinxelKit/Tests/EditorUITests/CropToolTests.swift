import AppKit
import DocumentModel
import PinxelTestSupport
import Rendering
import Testing
@testable import EditorUI

struct CropToolTests {
    private let size = PixelSize(width: 400, height: 300)
    private let shape = Annotation(id: TestDocuments.id(1), kind: .shape(ShapeData(rect: CGRect(x: 100, y: 100, width: 50, height: 50), shape: .rectangle)))

    private func controller() -> ToolController {
        let controller = ToolController()
        controller.tool = .crop
        controller.dragThreshold = 3
        controller.hitTolerance = 4
        return controller
    }

    private func drag(_ controller: ToolController, from start: CGPoint, to end: CGPoint, document: PinxelDocument) {
        _ = controller.handle(.down(start, [], clickCount: 1), document: document, selection: [])
        _ = controller.handle(.drag(CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2), []), document: document, selection: [])
        _ = controller.handle(.up(end, []), document: document, selection: [])
    }

    @Test func startsWithTheWholeImageAndForgetsItOnToolChange() {
        let tool = controller()
        #expect(tool.cropOverlay(imageSize: size) == CGRect(x: 0, y: 0, width: 400, height: 300))
        drag(tool, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 50, y: 50), document: TestDocuments.document(annotations: []))
        tool.tool = .select
        #expect(tool.cropOverlay(imageSize: size) == nil)
        tool.tool = .crop
        #expect(tool.cropRect == nil)
    }

    @Test func firstDragDrawsANewRectClampedToTheImage() {
        let tool = controller()
        drag(tool, from: CGPoint(x: 350, y: 250), to: CGPoint(x: 450, y: 350), document: TestDocuments.document(annotations: []))
        #expect(tool.cropRect == CGRect(x: 350, y: 250, width: 50, height: 50))
    }

    @Test func draggingInsideTheRectMovesItWithinTheImage() {
        let tool = controller()
        let document = TestDocuments.document(annotations: [])
        drag(tool, from: CGPoint(x: 50, y: 50), to: CGPoint(x: 150, y: 150), document: document)
        drag(tool, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 400, y: 100), document: document)
        #expect(tool.cropRect == CGRect(x: 300, y: 50, width: 100, height: 100))
    }

    @Test func handleResizesKeepingTheGrabOffset() {
        let tool = controller()
        let document = TestDocuments.document(annotations: [])
        drag(tool, from: CGPoint(x: 50, y: 50), to: CGPoint(x: 150, y: 150), document: document)
        drag(tool, from: CGPoint(x: 152, y: 152), to: CGPoint(x: 202, y: 182), document: document)
        #expect(tool.cropRect == CGRect(x: 50, y: 50, width: 150, height: 130))
    }

    @Test func enterAppliesTheCropAndUndoRestoresEverything() throws {
        let tool = controller()
        let original = TestDocuments.document(annotations: [shape])
        drag(tool, from: CGPoint(x: 50, y: 50), to: CGPoint(x: 150, y: 150), document: original)
        let result = tool.handle(.key(.enter, []), document: original, selection: [])
        // Il ritaglio serve i pixel: lo strumento lo chiede, la vista lo applica a tutto il contenuto.
        #expect(result.crop == PixelRect(x: 50, y: 50, width: 100, height: 100))
        #expect(result.command == nil)
        #expect(result.tool == .select && result.selection == [])
    }

    @Test func enterWithTheWholeImageOnlyLeavesTheTool() {
        let result = controller().handle(.key(.enter, []), document: TestDocuments.document(annotations: []), selection: [])
        #expect(result.command == nil && result.tool == .select)
    }

    @Test func escapeCancelsAndReturnsToSelect() {
        let tool = controller()
        let document = TestDocuments.document(annotations: [])
        drag(tool, from: CGPoint(x: 50, y: 50), to: CGPoint(x: 150, y: 150), document: document)
        let result = tool.handle(.key(.escape, []), document: document, selection: [])
        #expect(result.command == nil && result.tool == .select)
        #expect(tool.cropRect == nil)
    }

    @Test func pixelRectRoundsAndClamps() {
        #expect(CropGeometry.pixelRect(CGRect(x: -3.4, y: 10.6, width: 50.2, height: 20), imageSize: size) == PixelRect(x: 0, y: 11, width: 47, height: 20))
        #expect(CropGeometry.pixelRect(CGRect(x: 10, y: 10, width: 0.3, height: 0.3), imageSize: size) == nil)
    }

    @MainActor
    @Test func cropOnAPaddedRetinaCanvasCropsDocumentPixels() async throws {
        var document = TestDocuments.document(annotations: [], size: size, scale: 2)
        document.canvasStyle.padding = 20
        let undo = UndoManager()
        undo.groupsByEvent = false
        let session = EditorSession(document: document, assets: DictionaryAssetProvider([TestDocuments.background: TestImages.quadrants()]), undoManager: undo)
        let canvas = CanvasView(model: EditorModel(session: session))
        canvas.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        canvas.needsLayout = true
        canvas.layoutSubtreeIfNeeded()
        canvas.model.tool = .crop
        // Coordinate del documento: la conversione vista → documento con padding e scala è già coperta
        // da `mapsViewPointsWithPaddingAndRetinaScale`; qui conta che il ritaglio usi pixel del documento.
        canvas.send(.down(CGPoint(x: 100, y: 100), [], clickCount: 1))
        canvas.send(.drag(CGPoint(x: 150, y: 140), []))
        canvas.send(.up(CGPoint(x: 200, y: 180), []))
        let overlay = try #require(canvas.controller.cropOverlay(imageSize: session.document.imageSize))
        #expect(abs(Double(canvas.viewRect(fromDocument: overlay).width) - 100 * canvas.viewport.pointsPerPixel) < 0.001)
        canvas.send(.key(.enter, []))
        #expect(session.document.imageSize == PixelSize(width: 100, height: 80))
        #expect(canvas.model.tool == .select)
        try await Task.sleep(for: .milliseconds(50))
        #expect((canvas.accessibilityValue() as? String)?.contains("image: 100×80") == true)
    }
}
