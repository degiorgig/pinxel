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
        session.perform(UpdateAnnotations(name: CommandName.move, before: [capture], after: [AnnotationGeometry.moved(capture, by: CGSize(width: -150, height: -50))]))
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

    @Test func panningASmallOffCentreCanvasDoesNotRecenterIt() {
        // After a fit the small canvas stays where it was: the first scroll must not make it jump to the center.
        var viewport = Viewport(documentScale: 1, zoom: 1, origin: CGPoint(x: 30, y: 40))
        viewport.pan(by: CGSize(width: 5, height: 5), canvasSize: CGSize(width: 100, height: 100), in: CGSize(width: 1000, height: 800))
        #expect(viewport.origin == CGPoint(x: 30, y: 40))
    }

    @Test func panningALargeCanvasStillMovesWithinItsEdges() {
        var viewport = Viewport(documentScale: 1, zoom: 1, origin: CGPoint(x: -100, y: 20))
        viewport.pan(by: CGSize(width: -50, height: 0), canvasSize: CGSize(width: 2000, height: 100), in: CGSize(width: 1000, height: 800))
        #expect(viewport.origin == CGPoint(x: -150, y: 20))
    }

    /// Moves the capture to the left: the canvas fits and stays small, off-center.
    private func moveCaptureLeft(_ canvas: CanvasView) throws {
        let session = canvas.model.session
        let capture = try #require(session.document.annotations.first { $0.id == TestDocuments.captureID })
        session.perform(UpdateAnnotations(name: CommandName.move, before: [capture], after: [AnnotationGeometry.moved(capture, by: CGSize(width: -150, height: -50))]))
    }

    @Test func zoomingAfterAFitKeepsThePointUnderTheAnchor() throws {
        let canvas = makeCanvas()
        try moveCaptureLeft(canvas)
        let center = CGPoint(x: canvas.bounds.midX, y: canvas.bounds.midY)
        let before = canvas.documentPoint(fromView: center)
        canvas.zoomOut(nil)
        let after = canvas.documentPoint(fromView: center)
        // The shrunken canvas still fits in the view: no jump to the center.
        #expect(abs(after.x - before.x) < 0.5 && abs(after.y - before.y) < 0.5)
    }

    @Test func theTextEditorFollowsItsTextWhenTheCanvasAdapts() throws {
        let canvas = makeCanvas()
        let text = Annotation(id: TestDocuments.id(2), kind: .text(TextData(rect: CGRect(x: 50, y: 50, width: 120, height: 40), text: RichText("Ciao"))))
        canvas.model.session.perform(AddAnnotations([text]))
        canvas.beginTextEditing(TextEditRequest(annotation: text, isNew: false))
        try moveCaptureLeft(canvas)
        // The box is laid out again on every layout (window resized, zoom): that is where the offset showed.
        canvas.needsLayout = true
        canvas.layoutSubtreeIfNeeded()
        let editor = try #require(canvas.textEditor)
        let current = try #require(canvas.model.session.document.annotations.first { $0.id == text.id }?.textRect)
        let expected = canvas.viewRect(fromDocument: current)
        #expect(abs(editor.container.frame.minX - expected.minX) < 0.5 && abs(editor.container.frame.minY - expected.minY) < 0.5)
        canvas.finishTextEditing()
    }

    @Test func aNewTextIsAddedWhereItWasStartedAfterTheCanvasAdapts() throws {
        // The step sits 250×150 pixels to the right and below the text: after the fit the distance stays the same.
        let canvas = makeCanvas()
        let text = Annotation(id: TestDocuments.id(3), kind: .text(TextData(rect: CGRect(x: 50, y: 50, width: 120, height: 40), text: RichText(""))))
        canvas.beginTextEditing(TextEditRequest(annotation: text, isNew: true))
        try moveCaptureLeft(canvas)
        canvas.textEditor?.textView.insertText("Ciao", replacementRange: NSRange(location: 0, length: 0))
        canvas.finishTextEditing()
        let document = canvas.model.session.document
        let added = try #require(document.annotations.first { $0.id == text.id }?.textRect)
        guard case .step(let step) = document.annotations.first(where: { $0.id == TestDocuments.id(1) })?.kind else { Issue.record("no step"); return }
        #expect(step.center.x - added.minX == 250 && step.center.y - added.minY == 150)
    }
}
