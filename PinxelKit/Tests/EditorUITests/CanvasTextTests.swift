import AppKit
import DocumentModel
import PinxelTestSupport
import Rendering
import Testing
@testable import EditorUI

@MainActor
struct CanvasTextTests {
    private let text = Annotation(id: TestDocuments.id(1), kind: .text(TextData(
        rect: CGRect(x: 100, y: 100, width: 160, height: 40), text: RichText("Ciao"))), style: Style(stroke: nil, lineWidth: 0))

    private func makeCanvas(_ annotations: [Annotation] = [], scale: Double = 1, padding: Double = 0, readOnly: Bool = false) -> CanvasView {
        let size = PixelSize(width: 400, height: 300)
        var document = TestDocuments.document(annotations: annotations, size: size, scale: scale)
        document.canvasStyle.padding = padding
        let undo = UndoManager()
        undo.groupsByEvent = false
        let session = EditorSession(document: document,
                                    assets: DictionaryAssetProvider([TestDocuments.background: TestImages.solid(width: 400, height: 300, red: 1, green: 1, blue: 1)]),
                                    undoManager: undo, isReadOnly: readOnly)
        let canvas = CanvasView(model: EditorModel(session: session))
        // In una finestra, come nell'app: la text view diventa first responder e la digitazione resta una
        // sessione di modifica aperta (fuori da una finestra `didChangeText` la chiuderebbe subito).
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = canvas
        Self.windows.append(window)
        canvas.needsLayout = true
        canvas.layoutSubtreeIfNeeded()
        return canvas
    }

    private static var windows: [NSWindow] = []

    private func type(_ string: String, in canvas: CanvasView) {
        guard let editor = canvas.textEditor else { Issue.record("no editor"); return }
        editor.textView.string = string
        editor.textView.didChangeText()
    }

    @Test func doubleClickOpensAnEditorOverTheText() throws {
        let canvas = makeCanvas([text])
        canvas.send(.down(CGPoint(x: 150, y: 120), [], clickCount: 2))
        let editor = try #require(canvas.textEditor)
        #expect(editor.container.superview === canvas)
        #expect(editor.textView.string == "Ciao")
        #expect(canvas.model.editingText?.plainText == "Ciao")
        #expect(canvas.model.session.selection == [text.id])
    }

    @Test func editorFrameFollowsPaddingAndRetinaScale() throws {
        let canvas = makeCanvas([text], scale: 2, padding: 20)
        canvas.beginTextEditing(TextEditRequest(annotation: text, isNew: false))
        let editor = try #require(canvas.textEditor)
        let origin = canvas.viewPoint(fromDocument: CGPoint(x: 100, y: 100))
        #expect(editor.container.frame.origin == origin)
        #expect(abs(editor.container.frame.width - 160 * canvas.viewport.pointsPerPixel) < 0.001)
        #expect(editor.container.bounds.size == CGSize(width: 160, height: 40))
    }

    @Test func typingThenFinishingIsOneUndoStep() {
        let canvas = makeCanvas()
        canvas.model.tool = .text
        canvas.send(.down(CGPoint(x: 50, y: 50), [], clickCount: 1))
        canvas.send(.up(CGPoint(x: 50, y: 50), []))
        type("Ciao Pinxel", in: canvas)
        canvas.finishTextEditing()
        #expect(canvas.textEditor == nil)
        let session = canvas.model.session
        #expect(session.document.annotations.count == 1)
        #expect(session.document.annotations[0].richText?.plainText == "Ciao Pinxel")
        #expect(session.selection == [session.document.annotations[0].id])
        session.undoManager.undo()
        #expect(session.document.annotations.isEmpty)
        #expect(!session.undoManager.canUndo)
    }

    @Test func emptyNewTextLeavesNothing() {
        let canvas = makeCanvas()
        canvas.model.tool = .callout
        canvas.send(.down(CGPoint(x: 50, y: 50), [], clickCount: 1))
        canvas.send(.up(CGPoint(x: 50, y: 50), []))
        canvas.finishTextEditing()
        #expect(canvas.model.session.document.annotations.isEmpty)
        #expect(!canvas.model.session.undoManager.canUndo)
    }

    @Test func clickingTheCanvasFinishesEditingAndDoesNothingElse() {
        let canvas = makeCanvas([text])
        canvas.beginTextEditing(TextEditRequest(annotation: text, isNew: false))
        type("Altro", in: canvas)
        // La posizione non conta: con un testo in modifica qualsiasi clic sulla tela chiude la modifica.
        let event = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 10, y: 10), modifierFlags: [], timestamp: 0,
                                       windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        canvas.mouseDown(with: event)
        #expect(canvas.textEditor == nil)
        #expect(canvas.model.session.document.annotations[0].richText?.plainText == "Altro")
        #expect(canvas.model.session.selection == [text.id])
    }

    @Test func switchingToolFinishesEditing() async throws {
        let canvas = makeCanvas([text])
        canvas.beginTextEditing(TextEditRequest(annotation: text, isNew: false))
        type("Cambiato", in: canvas)
        canvas.model.tool = .arrow
        try await Task.sleep(for: .milliseconds(50))
        #expect(canvas.textEditor == nil)
        #expect(canvas.model.session.document.annotations[0].richText?.plainText == "Cambiato")
    }

    @Test func inspectorChangesWhileTypingGoToTheEditor() throws {
        let canvas = makeCanvas([text])
        canvas.beginTextEditing(TextEditRequest(annotation: text, isNew: false))
        canvas.model.updateText(name: "Dimensione testo") { $0.fontSize = 40 }
        let editor = try #require(canvas.textEditor)
        #expect(editor.richText.fontSize == 40)
        #expect(canvas.model.editingText?.fontSize == 40)
        #expect(!canvas.model.session.undoManager.canUndo)
        canvas.finishTextEditing()
        #expect(canvas.model.session.document.annotations[0].richText?.fontSize == 40)
    }

    @Test func readOnlyDoubleClickDoesNotEdit() {
        let canvas = makeCanvas([text], readOnly: true)
        canvas.send(.down(CGPoint(x: 150, y: 120), [], clickCount: 2))
        #expect(canvas.textEditor == nil)
    }

    @Test func growingTextGrowsTheFrame() throws {
        let canvas = makeCanvas([text])
        canvas.beginTextEditing(TextEditRequest(annotation: text, isNew: false))
        type("una riga\ndue righe\ntre righe\nquattro righe", in: canvas)
        let editor = try #require(canvas.textEditor)
        #expect(editor.frame.height > 40)
        canvas.finishTextEditing()
        #expect((canvas.model.session.document.annotations[0].textRect?.height ?? 0) > 40)
    }
}
