import AppKit
import DocumentModel
import PinxelTestSupport
import Rendering
import Testing
@testable import EditorUI

@MainActor
struct CanvasViewTests {
    private let blue = Annotation(
        id: TestDocuments.id(1),
        kind: .shape(ShapeData(rect: CGRect(x: 100, y: 100, width: 50, height: 50), shape: .rectangle)),
        style: Style(stroke: nil, fill: RGBA(red: 0, green: 0, blue: 1), lineWidth: 0)
    )

    private func makeCanvas(_ annotations: [Annotation] = [], size: PixelSize = PixelSize(width: 400, height: 300),
                            scale: Double = 1, padding: Double = 0, readOnly: Bool = false) -> CanvasView {
        var document = TestDocuments.document(annotations: annotations, size: size, scale: scale)
        document.canvasStyle.padding = padding
        let background = TestImages.solid(width: size.width, height: size.height, red: 1, green: 1, blue: 1)
        let undo = UndoManager()
        undo.groupsByEvent = false
        let session = EditorSession(document: document, assets: DictionaryAssetProvider([TestDocuments.background: background]),
                                    undoManager: undo, isReadOnly: readOnly)
        let canvas = CanvasView(model: EditorModel(session: session))
        canvas.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        canvas.needsLayout = true
        canvas.layoutSubtreeIfNeeded()
        canvas.pasteboard = NSPasteboard(name: NSPasteboard.Name("com.degiorgi.pinxel.tests.\(UUID().uuidString)"))
        return canvas
    }

    private func dragDocument(_ canvas: CanvasView, from start: CGPoint, to end: CGPoint) {
        canvas.send(.down(start, [], clickCount: 1))
        canvas.send(.drag(CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2), []))
        canvas.send(.drag(end, []))
        canvas.send(.up(end, []))
    }

    @Test func fitsAndCentersOnFirstLayout() {
        let canvas = makeCanvas()
        #expect(canvas.viewport.zoom == 1)
        #expect(canvas.documentPoint(fromView: CGPoint(x: 200, y: 150)) == .zero)
    }

    @Test func mapsViewPointsWithPaddingAndRetinaScale() {
        let canvas = makeCanvas(size: PixelSize(width: 800, height: 600), scale: 2, padding: 20)
        #expect(canvas.viewport.pointsPerPixel == 0.5)
        #expect(canvas.documentPoint(fromView: CGPoint(x: 205, y: 155)) == CGPoint(x: 10, y: 10))
    }

    @Test func drawsAnnotationsAtTheirDocumentPosition() throws {
        let canvas = makeCanvas([blue])
        let rep = try #require(canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds))
        canvas.cacheDisplay(in: canvas.bounds, to: rep)
        let factor = Double(rep.pixelsWide) / canvas.bounds.width
        let inside = try #require(rep.colorAt(x: Int(325 * factor), y: Int(275 * factor))?.usingColorSpace(.sRGB))
        #expect(inside.blueComponent > 0.9 && inside.redComponent < 0.1)
        let outside = try #require(rep.colorAt(x: Int(250 * factor), y: Int(200 * factor))?.usingColorSpace(.sRGB))
        #expect(outside.redComponent > 0.9 && outside.blueComponent > 0.9)
    }

    @Test func dragWithTheSelectToolMovesAsOneUndoableStep() {
        let canvas = makeCanvas([blue])
        dragDocument(canvas, from: CGPoint(x: 125, y: 125), to: CGPoint(x: 165, y: 125))
        let session = canvas.model.session
        #expect(session.document.annotations.first?.bounds.minX == 140)
        #expect(session.preview == nil)
        session.undoManager.undo()
        #expect(session.document.annotations.first?.bounds.minX == 100)
    }

    @Test func shapeToolCreatesAndSelectsTheNewShape() {
        let canvas = makeCanvas()
        canvas.model.tool = .shape
        dragDocument(canvas, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 90, y: 60))
        let session = canvas.model.session
        #expect(session.document.annotations.count == 1)
        #expect(session.selection == Set(session.document.annotations.map(\.id)))
    }

    @Test func readOnlyCanvasOnlySelects() {
        let canvas = makeCanvas([blue], readOnly: true)
        dragDocument(canvas, from: CGPoint(x: 125, y: 125), to: CGPoint(x: 165, y: 125))
        canvas.send(.key(.delete, []))
        let session = canvas.model.session
        #expect(session.document.annotations == [blue])
        #expect(session.selection == [blue.id])
        #expect(session.preview == nil)
    }

    @Test func copyWithoutSelectionPutsTheCompositeOnThePasteboard() throws {
        let canvas = makeCanvas([blue])
        canvas.copy(nil)
        let data = try #require(canvas.pasteboard.data(forType: .png))
        #expect(NSBitmapImageRep(data: data)?.pixelsWide == 400)
        #expect(canvas.pasteboard.data(forType: .tiff) != nil)
        #expect(canvas.pasteboard.data(forType: NSPasteboard.PasteboardType(AnnotationClipboard.typeIdentifier)) == nil)
    }

    @Test func copyAndPasteSelectionAddsAnOffsetCopy() throws {
        let canvas = makeCanvas([blue])
        let session = canvas.model.session
        session.selection = [blue.id]
        canvas.copy(nil)
        #expect(canvas.pasteboard.data(forType: NSPasteboard.PasteboardType(AnnotationClipboard.typeIdentifier)) != nil)
        let crop = try #require(canvas.pasteboard.data(forType: .png).flatMap(NSBitmapImageRep.init(data:)))
        #expect(crop.pixelsWide == 66)
        canvas.paste(nil)
        #expect(session.document.annotations.count == 2)
        let pasted = try #require(session.selectedAnnotations.first)
        #expect(pasted.id != blue.id)
        #expect(pasted.bounds.origin == CGPoint(x: 110, y: 110))
        #expect(session.undoManager.undoActionName == "Incolla")
    }

    @Test func toolShortcutKeyChangesTheTool() throws {
        let canvas = makeCanvas()
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                                  context: nil, characters: "r", charactersIgnoringModifiers: "r", isARepeat: false, keyCode: 15))
        canvas.keyDown(with: event)
        #expect(canvas.model.tool == .shape)
    }

    @Test func zoomActionsStepAndFitRestores() {
        let canvas = makeCanvas()
        canvas.zoomIn(nil)
        #expect(canvas.viewport.zoom == 1.5)
        canvas.zoomToActualSize(nil)
        #expect(canvas.viewport.zoom == 1)
        canvas.zoomOut(nil)
        canvas.zoomToFit(nil)
        #expect(canvas.viewport.zoom == 1)
        #expect(canvas.documentPoint(fromView: CGPoint(x: 200, y: 150)) == .zero)
    }

    @Test func arrangeWithoutChangeAddsNoUndo() {
        let canvas = makeCanvas([blue])
        canvas.model.session.selection = [blue.id]
        canvas.bringToFront(nil)
        #expect(!canvas.model.session.undoManager.canUndo)
    }

    @Test func duplicateAndLockMenuActions() {
        let canvas = makeCanvas([blue])
        let session = canvas.model.session
        session.selection = [blue.id]
        canvas.duplicateSelection(nil)
        #expect(session.document.annotations.count == 2)
        #expect(session.selectedAnnotations.first?.bounds.origin == CGPoint(x: 110, y: 110))
        canvas.lockSelection(nil)
        #expect(session.selectedAnnotations.first?.isLocked == true)
        canvas.unlockSelection(nil)
        #expect(session.selectedAnnotations.first?.isLocked == false)
    }
}
