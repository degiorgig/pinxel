import AppKit
import DocumentModel
import Foundation
import PinxelTestSupport
import Rendering
import Testing
@testable import EditorUI

/// Defects found by plan 4's final review.
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

    // 1. Save, Export, drag and close must see the text still being edited.
    @Test func pendingTextIsCommittedBeforeTheDocumentIsRead() {
        let (canvas, _) = makeCanvas([text])
        canvas.beginTextEditing(TextEditRequest(annotation: text, isNew: false))
        type("Errore 42", in: canvas)
        canvas.model.commitTextEditing()
        #expect(canvas.textEditor == nil)
        #expect(canvas.model.session.document.userAnnotations[0].richText?.plainText == "Errore 42")
    }

    // 2. Style and quick styles changed while typing a new callout reach the bubble.
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

    // 3. A click outside the text, coming from the window, ends the edit and does nothing else.
    @Test func clickAwayThroughTheWindowOnlyFinishesEditing() throws {
        let (canvas, window) = makeCanvas([text])
        canvas.model.tool = .text
        canvas.send(.down(CGPoint(x: 150, y: 120), [], clickCount: 1))
        canvas.send(.up(CGPoint(x: 150, y: 120), []))
        type("Cambiato", in: canvas)
        // Window in front: as in the app, the click goes through `NSWindow.sendEvent`, which moves the focus.
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

    // 4. With a sheet (Save, Export, Resize) in front, the edit commands go to its fields.
    @Test func editItemsPassThroughWhenAnotherWindowIsKey() {
        let (canvas, _) = makeCanvas([text])
        var state = EditorMenuState(model: canvas.model)
        #expect(!state.allows(false))
        state.editorIsKey = false
        #expect(state.allows(false))
        #expect(state.undoTitle == "Undo")
    }

    // 5. Cutting and pasting a pasted image brings it back.
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

    // 6. A pasted image larger than the documents' limit is reduced (or the file would not reopen).
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

    // 7. The Format menu bolds only the selected words (without clashing with zoom).
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
