import AppKit
import DocumentModel
import PinxelTestSupport
import Rendering
import Testing
@testable import EditorUI

@MainActor
struct EditorMinorsTests {
    private let shape = Annotation(id: TestDocuments.id(1), kind: .shape(ShapeData(rect: CGRect(x: 100, y: 100, width: 50, height: 50), shape: .rectangle)),
                                   style: Style(stroke: .accentRed, fill: .black, lineWidth: 4))
    private let arrow = Annotation(id: TestDocuments.id(2), kind: .arrow(ArrowData(line: LineGeometry(start: CGPoint(x: 0, y: 250), end: CGPoint(x: 80, y: 250)))))

    private func makeCanvas(_ annotations: [Annotation]) -> CanvasView {
        let undo = UndoManager()
        undo.groupsByEvent = false
        let session = EditorSession(document: TestDocuments.document(annotations: annotations, size: PixelSize(width: 400, height: 300), scale: 1),
                                    assets: DictionaryAssetProvider([TestDocuments.background: TestImages.quadrants()]), undoManager: undo)
        let canvas = CanvasView(model: EditorModel(session: session))
        canvas.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        canvas.pasteboard = NSPasteboard(name: NSPasteboard.Name("com.degiorgi.pinxel.tests.\(UUID().uuidString)"))
        return canvas
    }

    @Test func aGestureOnAChangedDocumentIsCancelled() {
        let controller = ToolController()
        let before = TestDocuments.document(annotations: [shape])
        _ = controller.handle(.down(CGPoint(x: 125, y: 125), [], clickCount: 1), document: before, selection: [shape.id])
        let after = TestDocuments.document(annotations: [])
        let drag = controller.handle(.drag(CGPoint(x: 160, y: 125), []), document: after, selection: [])
        #expect(drag.preview == nil && !controller.isGestureActive)
        #expect(controller.handle(.up(CGPoint(x: 160, y: 125), []), document: after, selection: []).command == nil)
    }

    @Test func keysAreIgnoredDuringADrag() {
        let controller = ToolController()
        let document = TestDocuments.document(annotations: [shape])
        _ = controller.handle(.down(CGPoint(x: 125, y: 125), [], clickCount: 1), document: document, selection: [shape.id])
        _ = controller.handle(.drag(CGPoint(x: 160, y: 125), []), document: document, selection: [shape.id])
        #expect(controller.handle(.key(.delete, []), document: document, selection: [shape.id]).command == nil)
        #expect(controller.handle(.key(.left, []), document: document, selection: [shape.id]).nudge == nil)
    }

    @Test func escapeDuringAMarqueeRestoresTheSelection() {
        let controller = ToolController()
        let document = TestDocuments.document(annotations: [shape, arrow])
        _ = controller.handle(.down(CGPoint(x: 300, y: 20), [.shift], clickCount: 1), document: document, selection: [arrow.id])
        let marquee = controller.handle(.drag(CGPoint(x: 90, y: 160), [.shift]), document: document, selection: [arrow.id])
        #expect(marquee.selection == [arrow.id, shape.id])
        #expect(controller.handle(.key(.escape, []), document: document, selection: [arrow.id, shape.id]).selection == [arrow.id])
    }

    @Test func sliderPreviewIsClearedWhenNothingChanges() {
        let canvas = makeCanvas([shape])
        let model = canvas.model
        model.session.selection = [shape.id]
        model.previewStyle(\.lineWidth, 10)
        #expect(model.session.preview != nil)
        model.setStyle(\.lineWidth, 4)
        #expect(model.session.preview == nil)
        #expect(!model.session.undoManager.canUndo)
    }

    @Test func cutCopiesOnlyWhatItDeletes() throws {
        var locked = arrow
        locked.isLocked = true
        let canvas = makeCanvas([shape, locked])
        canvas.model.session.selection = [shape.id, locked.id]
        canvas.cut(nil)
        let data = try #require(canvas.pasteboard.data(forType: CanvasView.annotationsType))
        #expect(try AnnotationClipboard.decode(data).map(\.id) == [shape.id])
        #expect(canvas.model.session.document.annotations.map(\.id) == [locked.id])
    }

    @Test func spacePanEndsWhenFocusIsLost() throws {
        let canvas = makeCanvas([])
        let space = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                                  context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49))
        canvas.keyDown(with: space)
        #expect(canvas.spaceHeld)
        _ = canvas.resignFirstResponder()
        #expect(!canvas.spaceHeld)
    }

    @Test func pastingTwiceMovesEachCopyFurther() throws {
        let canvas = makeCanvas([shape])
        canvas.model.session.selection = [shape.id]
        canvas.copy(nil)
        canvas.paste(nil)
        canvas.paste(nil)
        let minXs = canvas.model.session.document.annotations.map(\.bounds.minX)
        #expect(minXs == [100, 110, 120])
    }

    @Test func fillToggleOnlyChangesKindsWithAFill() {
        let text = Annotation(id: TestDocuments.id(3), kind: .text(TextData(rect: CGRect(x: 0, y: 0, width: 80, height: 30), text: RichText("a"))),
                              style: Style(stroke: nil, lineWidth: 0))
        var plain = shape
        plain.style.fill = nil
        let canvas = makeCanvas([plain, arrow, text])
        let model = canvas.model
        model.session.selection = [plain.id, arrow.id, text.id]
        model.setFill(true)
        let annotations = model.session.document.annotations
        #expect(annotations[0].style.fill == .accentRed)
        #expect(annotations[1].style.fill == nil)
        #expect(annotations[2].style.fill == .white)
    }
}
