import AppKit
import DocumentModel
import PinxelTestSupport
import Rendering
import Testing
@testable import EditorUI

@MainActor
struct CanvasShiftTests {
    func makeCanvas() -> CanvasView {
        let undo = UndoManager()
        undo.groupsByEvent = false
        let step = Annotation(id: TestDocuments.id(1), kind: .step(StepData(center: CGPoint(x: 300, y: 200), diameter: 20, label: StepLabel())),
                              style: Style(stroke: nil, fill: .accentRed))
        let session = EditorSession(document: TestDocuments.document(annotations: [step], size: PixelSize(width: 400, height: 300), scale: 1),
                                    assets: DictionaryAssetProvider([TestDocuments.background: TestImages.quadrants()]), undoManager: undo)
        let canvas = CanvasView(model: EditorModel(session: session))
        canvas.frame = NSRect(x: 0, y: 0, width: 1000, height: 800)
        canvas.needsLayout = true
        canvas.layoutSubtreeIfNeeded()
        return canvas
    }

    func stepCenter(_ canvas: CanvasView) -> CGPoint? {
        guard case .step(let data) = canvas.model.session.document.annotations.first(where: { $0.id == TestDocuments.id(1) })?.kind else { return nil }
        return canvas.viewPoint(fromDocument: data.center)
    }

    @Test func movingTheCaptureLeftKeepsOtherObjectsInPlace() throws {
        let canvas = makeCanvas()
        let before = try #require(stepCenter(canvas))
        let session = canvas.model.session
        let capture = try #require(session.document.annotations.first { $0.id == TestDocuments.captureID })
        session.perform(UpdateAnnotations(name: "Sposta", before: [capture], after: [AnnotationGeometry.moved(capture, by: CGSize(width: -150, height: -50))]))
        canvas.layoutSubtreeIfNeeded()
        let after = try #require(stepCenter(canvas))
        #expect(abs(after.x - before.x) < 0.5 && abs(after.y - before.y) < 0.5)
        session.undoManager.undo()
        canvas.layoutSubtreeIfNeeded()
        let undone = try #require(stepCenter(canvas))
        #expect(abs(undone.x - before.x) < 0.5 && abs(undone.y - before.y) < 0.5)
    }

    @Test func keepInViewDoesNotRecenterAVisibleCanvas() {
        var viewport = Viewport(documentScale: 1, zoom: 1, origin: CGPoint(x: 30, y: 40))
        viewport.keepInView(canvasSize: CGSize(width: 100, height: 100), in: CGSize(width: 1000, height: 800))
        #expect(viewport.origin == CGPoint(x: 30, y: 40))
    }

    @Test func keepInViewBringsBackACanvasThatLeftTheView() {
        var viewport = Viewport(documentScale: 1, zoom: 1, origin: CGPoint(x: 990, y: 40))
        viewport.keepInView(canvasSize: CGSize(width: 100, height: 100), in: CGSize(width: 1000, height: 800))
        #expect(viewport.origin == CGPoint(x: 1000 - 100 - 20, y: 40))
    }
}
