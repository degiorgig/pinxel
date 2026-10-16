import AppKit
import DocumentModel
import PinxelTestSupport
import Rendering
import Testing
@testable import EditorUI

@MainActor
struct PasteImageTests {
    private func pngData(width: Int, height: Int) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }

    private func makeCanvas(_ annotations: [Annotation] = [], readOnly: Bool = false) -> CanvasView {
        let undo = UndoManager()
        undo.groupsByEvent = false
        let session = EditorSession(document: TestDocuments.document(annotations: annotations, size: PixelSize(width: 400, height: 300), scale: 1),
                                    assets: DictionaryAssetProvider([TestDocuments.background: TestImages.quadrants()]),
                                    undoManager: undo, isReadOnly: readOnly)
        let canvas = CanvasView(model: EditorModel(session: session))
        canvas.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        canvas.needsLayout = true
        canvas.layoutSubtreeIfNeeded()
        canvas.pasteboard = NSPasteboard(name: NSPasteboard.Name("com.degiorgi.pinxel.tests.\(UUID().uuidString)"))
        return canvas
    }

    @Test func assetStoreAddsPNGAssetsAndFallsBackToTheDocument() throws {
        let background = TestImages.quadrants()
        let store = AssetStore(base: DictionaryAssetProvider([TestDocuments.background: background]))
        let image = TestImages.solid(width: 30, height: 20, red: 1, green: 0, blue: 0)
        let ref = try #require(store.add(image, id: TestDocuments.id(7)))
        #expect(ref.name == "assets/\(TestDocuments.id(7).uuidString).png")
        #expect(store.image(for: ref) === image)
        #expect(store.image(for: TestDocuments.background) === background)
        let data = try #require(store.addedData[ref])
        #expect(NSBitmapImageRep(data: data)?.pixelsWide == 30)
    }

    @Test func placementKeepsRetinaPixelsAndScalesOneXImages() {
        #expect(ImagePlacement.place(pixelSize: CGSize(width: 200, height: 100), imageScale: 2, documentScale: 2,
                                     center: CGPoint(x: 300, y: 200), imageSize: PixelSize(width: 800, height: 600), adaptCanvas: false)
                == ImagePlacement.Placement(rect: CGRect(x: 200, y: 150, width: 200, height: 100), imageSize: PixelSize(width: 800, height: 600)))
        #expect(ImagePlacement.place(pixelSize: CGSize(width: 100, height: 50), imageScale: 1, documentScale: 2,
                                     center: CGPoint(x: 300, y: 200), imageSize: PixelSize(width: 800, height: 600), adaptCanvas: false).rect.size
                == CGSize(width: 200, height: 100))
    }

    @Test func adaptingTheCanvasGivesItThePastedSizeBothWays() {
        let larger = ImagePlacement.place(pixelSize: CGSize(width: 1000, height: 200), imageScale: 1, documentScale: 1,
                                          center: CGPoint(x: 200, y: 150), imageSize: PixelSize(width: 400, height: 300), adaptCanvas: true)
        #expect(larger == ImagePlacement.Placement(rect: CGRect(x: 0, y: 0, width: 1000, height: 200), imageSize: PixelSize(width: 1000, height: 200)))
        let smaller = ImagePlacement.place(pixelSize: CGSize(width: 120, height: 90), imageScale: 1, documentScale: 1,
                                           center: CGPoint(x: 200, y: 150), imageSize: PixelSize(width: 400, height: 300), adaptCanvas: true)
        #expect(smaller == ImagePlacement.Placement(rect: CGRect(x: 0, y: 0, width: 120, height: 90), imageSize: PixelSize(width: 120, height: 90)))
    }

    @Test func keepingTheCanvasFitsLargeImagesInsideIt() {
        let placement = ImagePlacement.place(pixelSize: CGSize(width: 1000, height: 500), imageScale: 1, documentScale: 1,
                                             center: CGPoint(x: 200, y: 150), imageSize: PixelSize(width: 400, height: 300), adaptCanvas: false)
        #expect(placement == ImagePlacement.Placement(rect: CGRect(x: 0, y: 50, width: 400, height: 200), imageSize: PixelSize(width: 400, height: 300)))
    }

    @Test func imageNearTheEdgeStaysInsideTheCapture() {
        let placement = ImagePlacement.place(pixelSize: CGSize(width: 100, height: 100), imageScale: 1, documentScale: 1,
                                             center: CGPoint(x: 390, y: 10), imageSize: PixelSize(width: 400, height: 300), adaptCanvas: false)
        #expect(placement.rect == CGRect(x: 300, y: 0, width: 100, height: 100))
    }

    @Test func adaptingNeverPassesTheDocumentLimit() {
        let placement = ImagePlacement.place(pixelSize: CGSize(width: 30_000, height: 100), imageScale: 1, documentScale: 2,
                                             center: .zero, imageSize: PixelSize(width: 400, height: 300), adaptCanvas: true)
        #expect(placement.imageSize.width == PinxelDocument.maxImageSide)
        #expect(placement.rect.width == CGFloat(PinxelDocument.maxImageSide))
    }

    @Test func pastingASmallerScreenshotShrinksTheCanvas() throws {
        let canvas = makeCanvas()
        canvas.pasteboard.clearContents()
        canvas.pasteboard.setData(pngData(width: 150, height: 100), forType: .png)
        canvas.paste(nil)
        let session = canvas.model.session
        #expect(session.document.imageSize == PixelSize(width: 150, height: 100))
        // Lo screenshot diventa l'immagine della cattura, non un oggetto sopra.
        #expect(session.document.annotations.isEmpty)
        #expect(session.document.background != TestDocuments.background)
        #expect(session.assets.image(for: session.document.background)?.width == 150)
        session.undoManager.undo()
        #expect(session.document.imageSize == PixelSize(width: 400, height: 300))
        #expect(session.document.background == TestDocuments.background)
    }

    @Test func pastingWithoutAdaptingKeepsTheCanvas() throws {
        let canvas = makeCanvas()
        canvas.pasteboard.clearContents()
        canvas.pasteboard.setData(pngData(width: 40, height: 20), forType: .png)
        canvas.pasteKeepingCanvas(nil)
        let session = canvas.model.session
        #expect(session.document.imageSize == PixelSize(width: 400, height: 300))
        guard case .image(let data) = session.document.annotations.first?.kind else { Issue.record("no image"); return }
        #expect(data.rect == CGRect(x: 180, y: 140, width: 40, height: 20))
    }

    @Test func pastingALargerScreenshotGrowsTheCanvasInOneUndoStep() throws {
        let canvas = makeCanvas()
        canvas.pasteboard.clearContents()
        canvas.pasteboard.setData(pngData(width: 900, height: 700), forType: .png)
        canvas.paste(nil)
        let session = canvas.model.session
        #expect(session.document.imageSize == PixelSize(width: 900, height: 700))
        #expect(session.document.annotations.isEmpty)
        #expect(session.undoManager.undoActionName == "Incolla immagine")
        session.undoManager.undo()
        #expect(session.document.imageSize == PixelSize(width: 400, height: 300))
        #expect(session.document.background == TestDocuments.background)
        session.undoManager.redo()
        #expect(session.document.imageSize == PixelSize(width: 900, height: 700))
    }

    /// Tre fasce: rossa 0..<30, verde 30..<70, blu 70..<100 (righe dall'alto).
    private func bandsPNG() -> Data {
        let ctx = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 70, width: 100, height: 30))
        ctx.setFillColor(CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 30, width: 100, height: 40))
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 30))
        return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
    }

    @Test func scissorsCutAPastedScreenshotInsteadOfSquashingIt() throws {
        let canvas = makeCanvas()
        canvas.pasteboard.clearContents()
        canvas.pasteboard.setData(bandsPNG(), forType: .png)
        canvas.paste(nil)
        let session = canvas.model.session
        session.perform(ApplyImageOperation(.cutOut(CutOut(axis: .horizontal, start: 30, length: 40)), in: session.document))
        #expect(session.document.imageSize == PixelSize(width: 100, height: 60))
        let rendered = try DocumentRenderer().renderImage(session.document, assets: session.assets)
        let rep = NSBitmapImageRep(cgImage: rendered)
        func isGreen(_ y: Int) -> Bool { (rep.colorAt(x: 50, y: y)?.usingColorSpace(.sRGB)?.greenComponent ?? 0) > 0.5 }
        // Via la fascia verde: restano rosso sopra e blu sotto, ricuciti, senza verde schiacciato in mezzo.
        #expect(!(0..<60).contains(where: isGreen))
        #expect((rep.colorAt(x: 50, y: 10)?.usingColorSpace(.sRGB)?.redComponent ?? 0) > 0.9)
        #expect((rep.colorAt(x: 50, y: 50)?.usingColorSpace(.sRGB)?.blueComponent ?? 0) > 0.9)
    }

    @Test func pastedImageIsCenteredInTheVisibleArea() throws {
        let canvas = makeCanvas()
        canvas.pasteboard.clearContents()
        canvas.pasteboard.setData(pngData(width: 40, height: 20), forType: .png)
        canvas.pasteKeepingCanvas(nil)
        let session = canvas.model.session
        let pasted = try #require(session.document.annotations.first)
        guard case .image(let data) = pasted.kind else { Issue.record("no image"); return }
        #expect(data.rect == CGRect(x: 180, y: 140, width: 40, height: 20))
        #expect(session.assets.addedData[data.asset] != nil)
        #expect(session.selection == [pasted.id])
        session.undoManager.undo()
        #expect(session.document.annotations.isEmpty)
    }

    @Test func annotationsWinOverImagesOnThePasteboard() throws {
        let shape = Annotation(id: TestDocuments.id(1), kind: .shape(ShapeData(rect: CGRect(x: 10, y: 10, width: 20, height: 20), shape: .rectangle)))
        let canvas = makeCanvas()
        canvas.pasteboard.clearContents()
        canvas.pasteboard.setData(try AnnotationClipboard.encode([shape]), forType: CanvasView.annotationsType)
        canvas.pasteboard.setData(pngData(width: 40, height: 20), forType: .png)
        canvas.paste(nil)
        guard case .shape = canvas.model.session.document.annotations.first?.kind else { Issue.record("no shape"); return }
    }

    @Test func readOnlyCanvasDoesNotPasteImages() {
        let canvas = makeCanvas(readOnly: true)
        canvas.pasteboard.clearContents()
        canvas.pasteboard.setData(pngData(width: 40, height: 20), forType: .png)
        canvas.paste(nil)
        #expect(canvas.model.session.document.annotations.isEmpty)
        #expect(canvas.model.session.assets.addedData.isEmpty)
    }
}
