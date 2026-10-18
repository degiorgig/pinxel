import AppKit
import DocumentModel
import PinxelTestSupport
import Rendering
import Testing
@testable import EditorUI

/// Comandi di zoom e spostamento sopra la tela: leggono lo zoom dal modello e agiscono sulla tela attraverso di esso.
@MainActor
struct ZoomControlsTests {
    private static var windows: [NSWindow] = []

    /// Immagine 2000×1500 in una finestra 800×600: al 100% si può spostare.
    private func makeCanvas() -> (CanvasView, NSWindow) {
        let size = PixelSize(width: 2000, height: 1500)
        let undo = UndoManager()
        undo.groupsByEvent = false
        let session = EditorSession(document: TestDocuments.document(annotations: [], size: size, scale: 1),
                                    assets: DictionaryAssetProvider([TestDocuments.background: TestImages.solid(width: 2000, height: 1500, red: 1, green: 1, blue: 1)]),
                                    undoManager: undo)
        let canvas = CanvasView(model: EditorModel(session: session))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = canvas
        Self.windows.append(window)
        canvas.needsLayout = true
        canvas.layoutSubtreeIfNeeded()
        return (canvas, window)
    }

    private func mouse(_ type: NSEvent.EventType, at location: NSPoint, in window: NSWindow) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: 1, windowNumber: window.windowNumber,
                                        context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
    }

    private func key(_ keyCode: UInt16, _ characters: String) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                                      characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode))
    }

    @Test func theModelShowsTheCanvasZoom() {
        let (canvas, _) = makeCanvas()
        #expect(canvas.model.zoom == canvas.viewport.zoom)
        #expect(canvas.model.zoom < 1) // adattata alla finestra
        canvas.zoomToActualSize(nil)
        #expect(canvas.model.zoom == 1)
        canvas.zoomIn(nil)
        #expect(canvas.model.zoom == 1.5)
    }

    @Test func theControlsReachTheCanvasThroughTheModel() {
        let (canvas, _) = makeCanvas()
        canvas.model.canvas?.zoomToActualSize(nil)
        canvas.model.canvas?.zoomOut(nil)
        #expect(canvas.viewport.zoom == 0.75)
        canvas.model.canvas?.zoomToFit(nil)
        #expect(canvas.model.zoom < 0.75)
    }

    @Test func inPanModeDraggingMovesTheViewInsteadOfDrawing() throws {
        let (canvas, window) = makeCanvas()
        canvas.zoomToActualSize(nil)
        canvas.model.tool = .shape
        canvas.model.isPanning = true
        let before = canvas.viewport.origin
        // Coordinate della finestra: origine in basso a sinistra; trascinare in alto a sinistra mostra la parte in basso a destra.
        canvas.mouseDown(with: try mouse(.leftMouseDown, at: NSPoint(x: 400, y: 300), in: window))
        canvas.mouseDragged(with: try mouse(.leftMouseDragged, at: NSPoint(x: 300, y: 400), in: window))
        canvas.mouseUp(with: try mouse(.leftMouseUp, at: NSPoint(x: 300, y: 400), in: window))
        #expect(canvas.viewport.origin == CGPoint(x: before.x - 100, y: before.y - 100))
        #expect(canvas.model.session.document.annotations.isEmpty)
        #expect(canvas.model.isPanning) // resta attiva finché non la si spegne
    }

    @Test func escapeOrAnotherToolLeavesPanMode() throws {
        let (canvas, _) = makeCanvas()
        canvas.model.isPanning = true
        canvas.keyDown(with: try key(53, "\u{1b}"))
        #expect(!canvas.model.isPanning)
        canvas.model.isPanning = true
        canvas.model.tool = .arrow
        #expect(!canvas.model.isPanning)
    }
}
