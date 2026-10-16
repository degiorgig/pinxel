import AppKit
import DocumentModel
import PinxelTestSupport
import Rendering
import Testing
@testable import EditorUI

@MainActor
struct BlankCanvasTests {
    private func transparentImage(width: Int, height: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }

    private func makeCanvas(background: CGImage, annotations: [Annotation] = []) -> CanvasView {
        let undo = UndoManager()
        undo.groupsByEvent = false
        let size = PixelSize(width: background.width, height: background.height)
        let session = EditorSession(document: TestDocuments.document(annotations: annotations, size: size, scale: 1),
                                    assets: DictionaryAssetProvider([TestDocuments.background: background]), undoManager: undo)
        let canvas = CanvasView(model: EditorModel(session: session))
        canvas.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        canvas.layoutSubtreeIfNeeded()
        return canvas
    }

    @Test func aTransparentDocumentWithNothingOnItIsBlank() {
        #expect(makeCanvas(background: transparentImage(width: 160, height: 100)).isBlank)
    }

    @Test func aCaptureIsNotBlank() {
        #expect(!makeCanvas(background: TestImages.quadrants()).isBlank)
    }

    @Test func drawingOnTheBlankDocumentMakesItNotBlank() {
        let canvas = makeCanvas(background: transparentImage(width: 160, height: 100),
                                annotations: [Annotation(id: TestDocuments.id(1), kind: .shape(ShapeData(rect: CGRect(x: 10, y: 10, width: 40, height: 30), shape: .rectangle)))])
        #expect(!canvas.isBlank)
    }

    @Test func aSinglePaintedPixelIsEnough() {
        let ctx = CGContext(data: nil, width: 50, height: 50, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 37, y: 12, width: 1, height: 1))
        #expect(!CanvasView.isFullyTransparent(ctx.makeImage()!))
        #expect(CanvasView.isFullyTransparent(transparentImage(width: 50, height: 50)))
    }
}
