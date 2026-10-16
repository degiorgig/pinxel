import CoreGraphics
import Foundation
import Testing
import DocumentModel
@testable import Rendering
import PinxelTestSupport

let red = RGBA8(r: 255, g: 0, b: 0)
let green = RGBA8(r: 0, g: 255, b: 0)
let blue = RGBA8(r: 0, g: 0, b: 255)
let yellow = RGBA8(r: 255, g: 255, b: 0)
let white = RGBA8(r: 255, g: 255, b: 255)

func emptyDocument(size: PixelSize = PixelSize(width: 400, height: 300)) -> PinxelDocument {
    TestDocuments.document(annotations: [], size: size)
}

func assets(_ background: CGImage = TestImages.quadrants()) -> DictionaryAssetProvider {
    DictionaryAssetProvider([
        TestDocuments.background: background,
        TestDocuments.placedImage: TestImages.solid(width: 10, height: 10, red: 0, green: 0.6, blue: 1),
    ])
}

struct BackgroundTests {
    let quadrants = TestImages.quadrants()

    @Test func cropKeepsTopRightQuadrant() throws {
        let result = try #require(BackgroundProcessor.process(quadrants, operations: [.crop(PixelRect(x: 200, y: 0, width: 200, height: 150))]))
        #expect(result.width == 200 && result.height == 150)
        let pixels = PixelBuffer(result)
        #expect(pixels.pixel(x: 5, y: 5) == green)
        #expect(pixels.pixel(x: 195, y: 145) == green)
    }

    @Test func cropOutsideImageFails() {
        #expect(BackgroundProcessor.process(quadrants, operations: [.crop(PixelRect(x: 500, y: 0, width: 10, height: 10))]) == nil)
    }

    @Test func resizeHalvesImage() throws {
        let result = try #require(BackgroundProcessor.process(quadrants, operations: [.resize(PixelSize(width: 200, height: 150))]))
        #expect(result.width == 200 && result.height == 150)
        #expect(PixelBuffer(result).pixel(x: 50, y: 37) == red)
    }

    @Test func horizontalCutOutJoinsBands() throws {
        let cut = CutOut(axis: .horizontal, start: 100, length: 100, edge: .straight)
        let result = try #require(BackgroundProcessor.process(quadrants, operations: [.cutOut(cut)]))
        #expect(result.width == 400 && result.height == 200)
        let pixels = PixelBuffer(result)
        #expect(pixels.pixel(x: 10, y: 99) == red)   // riga 99 originale
        #expect(pixels.pixel(x: 10, y: 100) == blue) // riga 200 originale
    }

    @Test func verticalCutOutJoinsBands() throws {
        let cut = CutOut(axis: .vertical, start: 150, length: 100, edge: .straight)
        let result = try #require(BackgroundProcessor.process(quadrants, operations: [.cutOut(cut)]))
        #expect(result.width == 300 && result.height == 300)
        let pixels = PixelBuffer(result)
        #expect(pixels.pixel(x: 149, y: 10) == red)
        #expect(pixels.pixel(x: 150, y: 10) == green) // colonna 250 originale
    }

    @Test func zigzagCutOutDrawsSeam() throws {
        let cut = CutOut(axis: .horizontal, start: 100, length: 100, edge: .zigzag)
        let result = try #require(BackgroundProcessor.process(quadrants, operations: [.cutOut(cut)]))
        Snapshot.assertMatches(result, named: "cutout-zigzag")
    }

    @Test func emptyDocumentRendersBackgroundExactly() throws {
        let image = try DocumentRenderer().renderImage(emptyDocument(), assets: assets())
        #expect(PixelBuffer(image).differingPixelFraction(from: PixelBuffer(quadrants), channelTolerance: 1) == 0)
    }

    @Test func paddingAndBackgroundColor() throws {
        var document = emptyDocument()
        document.canvasStyle = CanvasStyle(padding: 10, backgroundColor: .white)
        let renderer = DocumentRenderer()
        #expect(renderer.canvasSize(for: document) == CGSize(width: 420, height: 320))
        let pixels = PixelBuffer(try renderer.renderImage(document, assets: assets()))
        #expect(pixels.width == 420 && pixels.height == 320)
        #expect(pixels.pixel(x: 5, y: 5) == white)
        #expect(pixels.pixel(x: 15, y: 15) == red)
        #expect(pixels.pixel(x: 405, y: 305) == yellow)
    }

    @Test func outputScaleChangesPixelSize() throws {
        let image = try DocumentRenderer().renderImage(emptyDocument(), assets: assets(), options: RenderOptions(outputScale: 0.5))
        #expect(image.width == 200 && image.height == 150)
    }

    @Test func missingBackgroundThrows() {
        #expect(throws: RenderError.missingBackground) {
            try DocumentRenderer().renderImage(emptyDocument(), assets: DictionaryAssetProvider([:]))
        }
    }

    @Test func operationsAreAppliedWhenRendering() throws {
        var document = emptyDocument()
        document.imageOperations = [.crop(PixelRect(x: 0, y: 150, width: 200, height: 150))]
        let image = try DocumentRenderer().renderImage(document, assets: assets())
        #expect(image.width == 200 && image.height == 150)
        #expect(PixelBuffer(image).pixel(x: 100, y: 75) == blue)
    }

    @Test func extendKeepsTheImageTopLeftAndLeavesTheRestTransparent() throws {
        let result = try #require(BackgroundProcessor.process(quadrants, operations: [.extend(PixelSize(width: 600, height: 400))]))
        #expect(result.width == 600 && result.height == 400)
        let pixels = PixelBuffer(result)
        #expect(pixels.pixel(x: 5, y: 5) == red)
        #expect(pixels.pixel(x: 395, y: 295) == yellow)
        #expect(pixels.pixel(x: 500, y: 100).a == 0)
        #expect(pixels.pixel(x: 100, y: 350).a == 0)
    }
}
