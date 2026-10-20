import AppKit
import DocumentModel
import PinxelTestSupport
import Rendering
import Testing
@testable import EditorUI

@MainActor
struct ContextMenuTests {
    private let shape = Annotation(id: TestDocuments.id(1), kind: .shape(ShapeData(rect: CGRect(x: 100, y: 100, width: 50, height: 50), shape: .rectangle)),
                                   style: Style(stroke: nil, fill: .white, lineWidth: 0))

    private func makeCanvas(readOnly: Bool = false) -> CanvasView {
        let undo = UndoManager()
        undo.groupsByEvent = false
        let session = EditorSession(document: TestDocuments.document(annotations: [shape], size: PixelSize(width: 400, height: 300), scale: 1),
                                    assets: DictionaryAssetProvider([TestDocuments.background: TestImages.quadrants()]),
                                    undoManager: undo, isReadOnly: readOnly)
        let canvas = CanvasView(model: EditorModel(session: session))
        canvas.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        canvas.needsLayout = true
        canvas.layoutSubtreeIfNeeded()
        return canvas
    }

    /// Right-click on a point of the document.
    private func rightClick(_ canvas: CanvasView, at point: CGPoint) -> NSMenu? {
        // The view is flipped: the event carries window coordinates.
        let location = canvas.convert(canvas.viewPoint(fromDocument: point), to: nil)
        let event = NSEvent.mouseEvent(with: .rightMouseDown, location: location, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                       context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        return canvas.menu(for: event)
    }

    private func item(_ menu: NSMenu?, _ title: String) -> NSMenuItem? {
        menu?.items.first { $0.title == title }
    }

    @Test func rightClickSelectsTheObjectAndOffersTheArrangeCommands() throws {
        let canvas = makeCanvas()
        let menu = try #require(rightClick(canvas, at: CGPoint(x: 125, y: 125)))
        #expect(canvas.model.session.selection == [shape.id])
        for title in [CommandName.bringToFront, CommandName.bringForward, CommandName.sendBackward, CommandName.sendToBack, CommandName.duplicate, CommandName.lock, CommandName.delete] {
            #expect(item(menu, title)?.isEnabled == true, "\(title)")
        }
    }

    @Test func sendToBackFromTheMenuPutsTheObjectUnderTheCapture() throws {
        let canvas = makeCanvas()
        let menu = rightClick(canvas, at: CGPoint(x: 125, y: 125))
        let back = try #require(item(menu, CommandName.sendToBack))
        _ = (back.target as AnyObject?)?.perform(try #require(back.action), with: back)
        #expect(canvas.model.session.document.annotations.first?.id == shape.id)
        canvas.model.session.undoManager.undo()
        #expect(canvas.model.session.document.annotations.first?.id == TestDocuments.captureID)
    }

    @Test func rightClickOnTheCaptureSelectsIt() {
        let canvas = makeCanvas()
        _ = rightClick(canvas, at: CGPoint(x: 300, y: 250))
        #expect(canvas.model.session.selection == [TestDocuments.captureID])
    }

    @Test func rightClickOnASelectedObjectKeepsTheWholeSelection() {
        let canvas = makeCanvas()
        canvas.model.session.selection = [shape.id, TestDocuments.captureID]
        _ = rightClick(canvas, at: CGPoint(x: 125, y: 125))
        #expect(canvas.model.session.selection == [shape.id, TestDocuments.captureID])
    }

    @Test func outsideTheContentNothingIsEnabled() throws {
        let canvas = makeCanvas()
        let menu = try #require(rightClick(canvas, at: CGPoint(x: -100, y: -100)))
        #expect(canvas.model.session.selection.isEmpty)
        #expect(menu.items.allSatisfy { !$0.isEnabled })
    }

    @Test func aLockedObjectOffersUnlock() throws {
        let canvas = makeCanvas()
        canvas.model.session.selection = [shape.id]
        canvas.lockSelection(nil)
        let menu = rightClick(canvas, at: CGPoint(x: 125, y: 125))
        #expect(item(menu, CommandName.unlock)?.isEnabled == true)
        #expect(item(menu, CommandName.sendToBack)?.isEnabled == false)
    }

    @Test func readOnlyHasNoMenu() {
        #expect(rightClick(makeCanvas(readOnly: true), at: CGPoint(x: 125, y: 125)) == nil)
    }
}
