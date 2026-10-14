import CoreGraphics
import Foundation
import Testing
import DocumentModel
import Rendering
@testable import Persistence
import PinxelTestSupport

struct ExporterTests {
    let provider = DictionaryAssetProvider([
        TestDocuments.background: TestImages.quadrants(),
        TestDocuments.placedImage: TestImages.solid(width: 10, height: 10, red: 0, green: 0.6, blue: 1),
    ])

    @Test func pngAtNativeScaleMatchesCanvasRenderExactly() throws {
        // Documento a scala 2: 2x = pixel nativi, cioè quello che il canvas mostra al 100%.
        let document = TestDocuments.document()
        let exported = try ImageCodec.decode(Exporter.export(document, assets: provider, format: .png, scale: .twoX))
        let canvas = try DocumentRenderer().renderImage(document, assets: provider, options: RenderOptions(outputScale: 1))
        #expect(PixelBuffer(exported).differingPixelFraction(from: PixelBuffer(canvas), channelTolerance: 0) == 0)
    }

    @Test func oneXHalvesARetinaCapture() throws {
        let image = try ImageCodec.decode(Exporter.export(TestDocuments.document(), assets: provider, format: .png, scale: .oneX))
        #expect(image.width == 200 && image.height == 150)
    }

    @Test func twoXDoublesANonRetinaCapture() throws {
        let document = TestDocuments.document(scale: 1)
        let image = try ImageCodec.decode(Exporter.export(document, assets: provider, format: .png, scale: .twoX))
        #expect(image.width == 800 && image.height == 600)
    }

    @Test func jpegUsesWhiteMatte() throws {
        var document = TestDocuments.document(annotations: [])
        document.canvasStyle = CanvasStyle(padding: 20)
        let data = try Exporter.export(document, assets: provider, format: .jpeg(quality: 0.9), scale: .twoX)
        #expect(data.starts(with: [0xFF, 0xD8]))
        let pixels = PixelBuffer(try ImageCodec.decode(data))
        let corner = pixels.pixel(x: 3, y: 3)
        #expect(corner.r > 245 && corner.g > 245 && corner.b > 245, "got \(corner)")
    }

    @Test func heicExportDecodes() throws {
        let data = try Exporter.export(TestDocuments.document(), assets: provider, format: .heic(quality: 0.8), scale: .twoX)
        let image = try ImageCodec.decode(data)
        #expect(image.width == 400 && image.height == 300)
    }

    @Test func pdfHasOnePageOfTheRightSize() throws {
        let data = try Exporter.export(TestDocuments.document(), assets: provider, format: .pdf, scale: .oneX)
        #expect(data.starts(with: Array("%PDF".utf8)))
        let pdf = try #require(CGPDFDocument(CGDataProvider(data: data as CFData)!))
        #expect(pdf.numberOfPages == 1)
        let box = try #require(pdf.page(at: 1)).getBoxRect(.mediaBox)
        #expect(box.size == CGSize(width: 200, height: 150))
    }

    @Test func missingBackgroundPropagates() {
        #expect(throws: RenderError.missingBackground) {
            try Exporter.export(TestDocuments.document(), assets: DictionaryAssetProvider([:]), format: .png, scale: .oneX)
        }
    }
}
