import AppKit
import DocumentModel
import Foundation
import PinxelTestSupport
import Rendering
import Testing
@testable import EditorUI

/// Difetti trovati dalla revisione finale del piano 4.
@MainActor
struct FinalReviewFixTests {
    private let text = Annotation(id: TestDocuments.id(1), kind: .text(TextData(
        rect: CGRect(x: 100, y: 100, width: 160, height: 40), text: RichText("Ciao"))), style: Style(stroke: nil, lineWidth: 0))

    private static var windows: [NSWindow] = []

    private func makeCanvas(_ annotations: [Annotation] = []) -> (CanvasView, NSWindow) {
        let undo = UndoManager()
        undo.groupsByEvent = false
        let session = EditorSession(document: TestDocuments.document(annotations: annotations, size: PixelSize(width: 400, height: 300), scale: 1),
                                    assets: DictionaryAssetProvider([TestDocuments.background: TestImages.quadrants()]), undoManager: undo)
        let canvas = CanvasView(model: EditorModel(session: session))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = canvas
        Self.windows.append(window)
        canvas.needsLayout = true
        canvas.layoutSubtreeIfNeeded()
        canvas.pasteboard = NSPasteboard(name: NSPasteboard.Name("com.degiorgi.pinxel.tests.\(UUID().uuidString)"))
        return (canvas, window)
    }

    private func type(_ string: String, in canvas: CanvasView) {
        canvas.textEditor?.textView.string = string
        canvas.textEditor?.textView.didChangeText()
    }

    private func pngData(width: Int, height: Int) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }

    // 1. Salva, Esporta, trascina e chiudi devono vedere il testo ancora in modifica.
    @Test func pendingTextIsCommittedBeforeTheDocumentIsRead() {
        let (canvas, _) = makeCanvas([text])
        canvas.beginTextEditing(TextEditRequest(annotation: text, isNew: false))
        type("Errore 42", in: canvas)
        canvas.model.commitTextEditing()
        #expect(canvas.textEditor == nil)
        #expect(canvas.model.session.document.userAnnotations[0].richText?.plainText == "Errore 42")
    }

    // 2. Stile e stili rapidi cambiati mentre si scrive un callout nuovo arrivano al fumetto.
    @Test func styleChangesWhileTypingANewCalloutReachTheBubble() {
        let (canvas, _) = makeCanvas()
        canvas.model.tool = .callout
        canvas.send(.down(CGPoint(x: 50, y: 50), [], clickCount: 1))
        canvas.send(.up(CGPoint(x: 50, y: 50), []))
        type("Qui", in: canvas)
        canvas.model.setStyle(\.fill, .highlightYellow)
        canvas.model.applyQuickStyle(Style(stroke: .black, fill: .highlightYellow, lineWidth: 7))
        canvas.finishTextEditing()
        let created = canvas.model.session.document.userAnnotations.first
        #expect(created?.style.fill == .highlightYellow)
        #expect(created?.style.lineWidth == 7)
    }

    // 3. Un clic fuori dal testo, arrivato dalla finestra, chiude la modifica e non fa altro.
    @Test func clickAwayThroughTheWindowOnlyFinishesEditing() throws {
        let (canvas, window) = makeCanvas([text])
        canvas.model.tool = .text
        canvas.send(.down(CGPoint(x: 150, y: 120), [], clickCount: 1))
        canvas.send(.up(CGPoint(x: 150, y: 120), []))
        type("Cambiato", in: canvas)
        // Finestra in primo piano: come nell'app, il clic passa da `NSWindow.sendEvent`, che sposta il fuoco.
        window.makeKeyAndOrderFront(nil)
        let location = NSPoint(x: 20, y: 20)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: 1,
                                                        windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
            window.sendEvent(event)
        }
        #expect(canvas.textEditor == nil)
        #expect(canvas.model.session.document.userAnnotations.count == 1)
        #expect(canvas.model.session.document.userAnnotations[0].richText?.plainText == "Cambiato")
    }

    // 4. Con un foglio (Salva, Esporta, Ridimensiona) in primo piano le voci di modifica vanno ai suoi campi.
    @Test func editItemsPassThroughWhenAnotherWindowIsKey() {
        let (canvas, _) = makeCanvas([text])
        var state = EditorMenuState(model: canvas.model)
        #expect(!state.allows(false))
        state.editorIsKey = false
        #expect(state.allows(false))
        #expect(state.undoTitle == "Undo")
    }

    // 5. Tagliare e incollare un'immagine incollata la riporta.
    @Test func cutAndPasteOfAPastedImageBringsItBack() throws {
        let (canvas, _) = makeCanvas()
        canvas.pasteboard.clearContents()
        canvas.pasteboard.setData(pngData(width: 40, height: 20), forType: .png)
        canvas.pasteKeepingCanvas(nil)
        let session = canvas.model.session
        let pasted = try #require(session.document.userAnnotations.first)
        session.selection = [pasted.id]
        canvas.cut(nil)
        #expect(session.document.userAnnotations.isEmpty)
        canvas.paste(nil)
        guard case .image(let data) = session.document.userAnnotations.first?.kind else { Issue.record("no image back"); return }
        guard case .image(let original) = pasted.kind else { return }
        #expect(data.asset == original.asset)
    }

    // 6. Un'immagine incollata più grande del limite dei documenti viene ridotta (o il file non si riaprirebbe).
    @Test func oversizedImagesAreScaledDownToTheLimit() throws {
        let image = TestImages.solid(width: 400, height: 50, red: 1, green: 0, blue: 0)
        let fitted = try #require(ImagePlacement.fitting(image, maxSide: 100))
        #expect(fitted.width == 100 && fitted.height == 13)
        let small = TestImages.solid(width: 40, height: 20, red: 1, green: 0, blue: 0)
        #expect(ImagePlacement.fitting(small, maxSide: 100) === small)
    }

    @Test func pastingAnImageWiderThanTheLimitStoresAScaledCopy() throws {
        let (canvas, _) = makeCanvas()
        canvas.pasteboard.clearContents()
        canvas.pasteboard.setData(pngData(width: PinxelDocument.maxImageSide + 232, height: 2), forType: .png)
        canvas.pasteKeepingCanvas(nil)
        guard case .image(let data) = canvas.model.session.document.userAnnotations.first?.kind else { Issue.record("no image"); return }
        let stored = try #require(canvas.model.session.assets.image(for: data.asset))
        #expect(stored.width <= PinxelDocument.maxImageSide)
    }

    // 7. Il menu Formato mette in grassetto solo le parole selezionate (senza scontrarsi con lo zoom).
    @Test func boldToggleChangesOnlyTheSelectedRange() throws {
        let view = PinxelTextView(usingTextLayoutManager: false)
        view.isRichText = true
        view.textStorage?.setAttributedString(RichTextBridge.attributedString(RichText("Ciao mondo")))
        view.setSelectedRange(NSRange(location: 0, length: 4))
        view.toggleBoldface(nil)
        let bold = try #require(view.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        let plain = try #require(view.textStorage?.attribute(.font, at: 6, effectiveRange: nil) as? NSFont)
        #expect(bold.fontDescriptor.symbolicTraits.contains(.bold))
        #expect(!plain.fontDescriptor.symbolicTraits.contains(.bold))
        view.toggleBoldface(nil)
        let again = try #require(view.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(!again.fontDescriptor.symbolicTraits.contains(.bold))
    }
}
