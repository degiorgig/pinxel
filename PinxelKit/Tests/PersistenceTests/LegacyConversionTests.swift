import CoreGraphics
import Foundation
import Testing
import DocumentModel
@testable import Persistence
import Rendering
import PinxelTestSupport

struct LegacyConversionTests {
    func v1Archive(operations: [ImageOperation], annotations: [Annotation], background: CGImage = TestImages.quadrants()) throws -> Data {
        let legacy = LegacyDocumentV1(background: ImageAssetRef(name: "background.png"), canvasSize: PixelSize(width: background.width, height: background.height),
                                      scale: 2, colorSpace: .sRGB, imageOperations: operations, canvasStyle: CanvasStyle(),
                                      annotations: annotations, metadata: CaptureMetadata(captureDate: Date(timeIntervalSinceReferenceDate: 1)))
        var zip = ZipWriter()
        let encoder = JSONEncoder()
        try zip.add(name: "manifest.json", data: encoder.encode(PinxelManifest(format: "pinxel", version: 1, appVersion: "0.1.0")), method: .deflate)
        try zip.add(name: "document.json", data: encoder.encode(legacy), method: .deflate)
        try zip.add(name: "background.png", data: ImageCodec.encode(background, type: .png), method: .store)
        return try zip.finish()
    }

    var step: Annotation { Annotation(id: TestDocuments.id(7), kind: .step(StepData(center: CGPoint(x: 50, y: 50), diameter: 20, label: StepLabel())), style: Style(stroke: nil, fill: .accentRed)) }

    @Test func plainCaptureBecomesAnImageObject() throws {
        let contents = try PinxelArchive.read(try v1Archive(operations: [], annotations: [step]))
        #expect(contents.document.canvasSize == PixelSize(width: 400, height: 300))
        #expect(contents.document.annotations.count == 2)
        guard case .image(let data) = contents.document.annotations[0].kind else { Issue.record("no image"); return }
        #expect(data.rect == CGRect(x: 0, y: 0, width: 400, height: 300))
        #expect(data.asset.name == "background.png")
        #expect(contents.document.annotations[1] == step)
    }

    @Test(arguments: [
        ImageOperation.crop(PixelRect(x: 10, y: 20, width: 200, height: 100)),
        .resize(PixelSize(width: 200, height: 150)),
        .cutOut(CutOut(axis: .vertical, start: 100, length: 50)),
        .extend(PixelSize(width: 500, height: 400)),
    ])
    func operationsAreBakedIntoTheImage(_ operation: ImageOperation) throws {
        let contents = try PinxelArchive.read(try v1Archive(operations: [operation], annotations: []))
        let expected = operation.resultSize(from: PixelSize(width: 400, height: 300))
        guard case .image(let data) = contents.document.annotations[0].kind else { Issue.record("no image"); return }
        let pixels = try #require(try contents.assetProvider().image(for: data.asset))
        #expect(PixelSize(width: pixels.width, height: pixels.height) == expected)
        #expect(contents.document.canvasSize == expected)
    }

    @Test func renderMatchesTheProcessedBackground() throws {
        let operation = ImageOperation.crop(PixelRect(x: 200, y: 0, width: 200, height: 150))
        let contents = try PinxelArchive.read(try v1Archive(operations: [operation], annotations: []))
        let rendered = try DocumentRenderer().renderImage(contents.document, assets: try contents.assetProvider())
        let reference = try #require(BackgroundProcessor.process(TestImages.quadrants(), operations: [operation]))
        #expect(PixelBuffer(rendered).differingPixelFraction(from: PixelBuffer(reference), channelTolerance: 1) == 0)
    }

    @Test func annotationOutsideTheImageGrowsTheCanvas() throws {
        let outside = Annotation(kind: .step(StepData(center: CGPoint(x: 420, y: 150), diameter: 20, label: StepLabel())), style: Style(stroke: nil, fill: .accentRed))
        let contents = try PinxelArchive.read(try v1Archive(operations: [], annotations: [outside]))
        #expect(contents.document.canvasSize == PixelSize(width: 430, height: 300))
    }

    @Test func lightReadConvertsWithoutPixels() throws {
        let document = try PinxelArchive.readDocument(try v1Archive(operations: [.crop(PixelRect(x: 0, y: 0, width: 120, height: 80))], annotations: []))
        #expect(document.imageSize == PixelSize(width: 120, height: 80))
    }

    @Test func v1RoundTripThroughV2() throws {
        let first = try PinxelArchive.read(try v1Archive(operations: [.crop(PixelRect(x: 0, y: 0, width: 300, height: 200))], annotations: [step]))
        let saved = try PinxelArchive.write(document: first.document, images: first.images, thumbnail: Data([1]), appVersion: "0.1.0")
        let second = try PinxelArchive.read(saved)
        #expect(second.document == first.document)
        let a = try DocumentRenderer().renderImage(first.document, assets: try first.assetProvider())
        let b = try DocumentRenderer().renderImage(second.document, assets: try second.assetProvider())
        #expect(PixelBuffer(a).differingPixelFraction(from: PixelBuffer(b), channelTolerance: 0) == 0)
    }

    @Test func invalidV1IsRejected() throws {
        let data = try v1Archive(operations: [.resize(PixelSize(width: 0, height: 10))], annotations: [])
        #expect(throws: (any Error).self) { try PinxelArchive.read(data) }
    }
}
