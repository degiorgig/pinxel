import CoreGraphics
import Foundation
import Testing
import DocumentModel
@testable import Rendering
import PinxelTestSupport

struct HardeningTests {
    @Test func nonFiniteCanvasThrowsInsteadOfTrapping() {
        var document = emptyDocument()
        document.canvasStyle.padding = 1e308
        #expect(throws: RenderError.invalidSize) {
            try DocumentRenderer().renderImage(document, assets: assets(), options: RenderOptions(outputScale: 2))
        }
    }

    @Test func tinyOutputKeepsAtLeastOnePixel() throws {
        let document = emptyDocument(size: PixelSize(width: 2000, height: 1))
        let strip = TestImages.solid(width: 2000, height: 1, red: 1, green: 0, blue: 0)
        let image = try DocumentRenderer().renderImage(document, assets: assets(strip), options: RenderOptions(outputScale: 0.256))
        #expect(image.width == 512 && image.height == 1)
    }

    @Test func magnifierWithSourcePartlyOutsideIsNotStretched() throws {
        // 20×10 source straddling the right edge: only the left half (green) exists.
        let magnifier = Annotation(kind: .magnifier(MagnifierData(
            source: CGRect(x: 390, y: 10, width: 20, height: 10),
            target: CGRect(x: 40, y: 200, width: 40, height: 20),
            shape: .rectangle, showsConnector: false)), style: Style(stroke: nil))
        let document = TestDocuments.document(annotations: [magnifier])
        let pixels = PixelBuffer(try DocumentRenderer().renderImage(document, assets: assets()))
        #expect(pixels.pixel(x: 50, y: 210) == green)
        #expect(pixels.pixel(x: 75, y: 210) == white)
    }
}
