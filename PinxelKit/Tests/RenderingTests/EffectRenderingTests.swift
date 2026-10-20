import CoreGraphics
import Foundation
import Testing
import DocumentModel
@testable import Rendering
import PinxelTestSupport

struct EffectRenderingTests {
    func render(_ annotations: [Annotation], background: CGImage = TestImages.quadrants(), canvasStyle: CanvasStyle = CanvasStyle()) throws -> CGImage {
        var document = TestDocuments.document(annotations: annotations, size: PixelSize(width: background.width, height: background.height))
        document.canvasStyle = canvasStyle
        return try DocumentRenderer().renderImage(document, assets: assets(background))
    }

    func redVariance(_ pixels: PixelBuffer, rect: CGRect) -> Double {
        var values: [Double] = []
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) { values.append(Double(pixels.pixel(x: x, y: y).r)) }
        }
        let mean = values.reduce(0, +) / Double(values.count)
        return values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
    }

    @Test func blurRemovesDetail() throws {
        let noise = TestImages.noise(width: 200, height: 200)
        let rect = CGRect(x: 50, y: 50, width: 100, height: 100)
        let inner = rect.insetBy(dx: 10, dy: 10)
        let before = redVariance(PixelBuffer(noise), rect: inner)
        let after = redVariance(PixelBuffer(try render([Annotation(kind: .blur(BlurData(rect: rect, radius: 8)))], background: noise)), rect: inner)
        #expect(after < before * 0.2, "variance \(before) → \(after)")
    }

    @Test func pixelateMakesUniformBlocks() throws {
        let noise = TestImages.noise(width: 200, height: 200)
        let pixels = PixelBuffer(try render([Annotation(kind: .pixelate(PixelateData(rect: CGRect(x: 100, y: 100, width: 40, height: 40), blockSize: 10)))], background: noise))
        #expect(pixels.pixel(x: 101, y: 101) == pixels.pixel(x: 108, y: 108))
        #expect(pixels.pixel(x: 121, y: 131) == pixels.pixel(x: 128, y: 138))
        #expect(pixels.pixel(x: 101, y: 101) != pixels.pixel(x: 131, y: 131))
    }

    @Test func magnifierCopiesSourceIntoTarget() throws {
        let magnifier = Annotation(kind: .magnifier(MagnifierData(
            source: CGRect(x: 50, y: 50, width: 10, height: 10),
            target: CGRect(x: 40, y: 200, width: 60, height: 60),
            shape: .rectangle, showsConnector: false)), style: Style(stroke: nil))
        let pixels = PixelBuffer(try render([magnifier]))
        #expect(pixels.pixel(x: 70, y: 230) == red)    // the target is in the blue quadrant but shows red
        #expect(pixels.pixel(x: 20, y: 230) == blue)
    }

    @Test func magnifierWithSourceOutsideImageDrawsNothing() throws {
        let magnifier = Annotation(kind: .magnifier(MagnifierData(
            source: CGRect(x: -100, y: -100, width: 20, height: 20),
            target: CGRect(x: 40, y: 200, width: 60, height: 60))))
        let image = try render([magnifier])
        #expect(PixelBuffer(image).differingPixelFraction(from: PixelBuffer(TestImages.quadrants()), channelTolerance: 1) == 0)
    }

    @Test func placedImageAndMissingPlaceholder() throws {
        let present = Annotation(kind: .image(PlacedImageData(rect: CGRect(x: 20, y: 20, width: 40, height: 40), asset: TestDocuments.placedImage)))
        let missing = Annotation(kind: .image(PlacedImageData(rect: CGRect(x: 100, y: 20, width: 40, height: 40), asset: ImageAssetRef(name: "assets/missing.png"))))
        let pixels = PixelBuffer(try render([present, missing]))
        #expect(pixels.pixel(x: 40, y: 40) == RGBA8(r: 0, g: 153, b: 255))
        let placeholder = pixels.pixel(x: 103, y: 40)
        #expect(placeholder.r == placeholder.g && placeholder.g == placeholder.b && placeholder.r > 200, "got \(placeholder)")
    }

    @Test func canvasStyleSnapshot() throws {
        let style = CanvasStyle(padding: 30, backgroundColor: RGBA(red: 0.93, green: 0.94, blue: 0.96), border: Border(color: .black, width: 4), shadow: Shadow(offset: CGSize(width: 0, height: 8), blur: 16, color: RGBA(red: 0, green: 0, blue: 0, alpha: 0.5)))
        Snapshot.assertMatches(try render([], canvasStyle: style), named: "canvas-style")
    }

    @Test func allKindsSnapshot() throws {
        Snapshot.assertMatches(try render(TestDocuments.allKindsAnnotations()), named: "all-kinds", tolerance: 0.02)
    }

    @Test func largeCanvasRenders() throws {
        let background = TestImages.solid(width: 6000, height: 4000, red: 0.2, green: 0.4, blue: 0.6)
        let annotations = [
            Annotation(kind: .blur(BlurData(rect: CGRect(x: 1000, y: 1000, width: 800, height: 600), radius: 20))),
            Annotation(kind: .arrow(ArrowData(line: LineGeometry(start: CGPoint(x: 100, y: 100), end: CGPoint(x: 5900, y: 3900))))),
        ]
        let image = try render(annotations, background: background)
        #expect(image.width == 6000 && image.height == 4000)
    }

    @Test func renderingIsDeterministicWithCache() throws {
        let renderer = DocumentRenderer()
        let document = TestDocuments.document()
        let provider = assets()
        let first = PixelBuffer(try renderer.renderImage(document, assets: provider))
        let second = PixelBuffer(try renderer.renderImage(document, assets: provider))
        #expect(first == second)
    }
}
