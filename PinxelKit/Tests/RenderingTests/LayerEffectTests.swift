import CoreGraphics
import Foundation
import Testing
import DocumentModel
@testable import Rendering
import PinxelTestSupport

struct LayerEffectTests {
    let noiseRef = ImageAssetRef(name: "assets/noise.png")

    /// Stesse immagini per tutti i render di un test: la cache del renderer le riconosce.
    let assets: DictionaryAssetProvider

    init() {
        assets = DictionaryAssetProvider([
            TestDocuments.background: TestImages.solid(width: 200, height: 200, red: 1, green: 1, blue: 1),
            noiseRef: TestImages.noise(width: 100, height: 100),
        ])
    }

    func render(_ annotations: [Annotation], renderer: DocumentRenderer = DocumentRenderer()) throws -> CGImage {
        let document = TestDocuments.document(annotations: annotations, size: PixelSize(width: 200, height: 200))
        return try renderer.renderImage(document, assets: assets)
    }

    func variance(_ image: CGImage, _ rect: CGRect) -> Double {
        let pixels = PixelBuffer(image)
        var values: [Double] = []
        for y in Int(rect.minY)..<Int(rect.maxY) { for x in Int(rect.minX)..<Int(rect.maxX) { values.append(Double(pixels.pixel(x: x, y: y).r)) } }
        let mean = values.reduce(0, +) / Double(values.count)
        return values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
    }

    var placedNoise: Annotation {
        Annotation(kind: .image(PlacedImageData(rect: CGRect(x: 50, y: 50, width: 100, height: 100), asset: noiseRef)), style: Style(stroke: nil, lineWidth: 0))
    }

    @Test func blurCoversAPlacedImage() throws {
        let inner = CGRect(x: 70, y: 70, width: 60, height: 60)
        let before = variance(try render([placedNoise]), inner)
        let after = variance(try render([placedNoise, Annotation(kind: .blur(BlurData(rect: CGRect(x: 50, y: 50, width: 100, height: 100), radius: 8)))]), inner)
        #expect(after < before * 0.2, "variance \(before) → \(after)")
    }

    @Test func blurCoversAnArrowBelowButNotOneAbove() throws {
        let arrow = { (y: Double) in Annotation(kind: .arrow(ArrowData(line: LineGeometry(start: CGPoint(x: 20, y: y), end: CGPoint(x: 180, y: y)), heads: ArrowHeads(start: .none, end: .none))),
                                                style: Style(stroke: .black, lineWidth: 4)) }
        let blur = Annotation(kind: .blur(BlurData(rect: CGRect(x: 0, y: 0, width: 200, height: 200), radius: 10)))
        let below = PixelBuffer(try render([arrow(100), blur]))
        let above = PixelBuffer(try render([blur, arrow(100)]))
        #expect(below.pixel(x: 100, y: 100).r > 60)   // la freccia sotto è sfocata: niente più nero pieno
        #expect(above.pixel(x: 100, y: 100).r < 10)   // quella sopra resta nitida
    }

    @Test func magnifierShowsAPlacedImage() throws {
        let red = Annotation(kind: .image(PlacedImageData(rect: CGRect(x: 10, y: 10, width: 20, height: 20), asset: ImageAssetRef(name: "assets/red.png"))), style: Style(stroke: nil, lineWidth: 0))
        let magnifier = Annotation(kind: .magnifier(MagnifierData(source: CGRect(x: 12, y: 12, width: 10, height: 10), target: CGRect(x: 100, y: 100, width: 60, height: 60),
                                                                  shape: .rectangle, showsConnector: false)), style: Style(stroke: nil))
        let document = TestDocuments.document(annotations: [red, magnifier], size: PixelSize(width: 200, height: 200))
        let assets = DictionaryAssetProvider([
            TestDocuments.background: TestImages.solid(width: 200, height: 200, red: 1, green: 1, blue: 1),
            ImageAssetRef(name: "assets/red.png"): TestImages.solid(width: 20, height: 20, red: 1, green: 0, blue: 0),
        ])
        let pixel = PixelBuffer(try DocumentRenderer().renderImage(document, assets: assets)).pixel(x: 130, y: 130)
        #expect(pixel.r > 240 && pixel.g < 15)
    }

    @Test func farObjectsDoNotInvalidateTheEffect() throws {
        let renderer = DocumentRenderer()
        let blur = Annotation(kind: .blur(BlurData(rect: CGRect(x: 50, y: 50, width: 40, height: 40), radius: 4)))
        let far = { (x: Double) in Annotation(id: TestDocuments.id(50), kind: .shape(ShapeData(rect: CGRect(x: x, y: 170, width: 10, height: 10), shape: .rectangle))) }
        _ = try render([far(150), blur], renderer: renderer)
        let misses = renderer.effectCacheMisses
        _ = try render([far(160), blur], renderer: renderer)
        #expect(renderer.effectCacheMisses == misses)
    }

    @Test func layersAreRenderedOnlyForTheRegion() throws {
        let renderer = DocumentRenderer()
        _ = try render([Annotation(kind: .blur(BlurData(rect: CGRect(x: 10, y: 20, width: 30, height: 40), radius: 4)))], renderer: renderer)
        #expect(renderer.lastLayerSize == PixelSize(width: 30, height: 40))
    }

    @Test func stepNumbersUnderAnEffectFollowRenumbering() throws {
        // Lente sopra lo step "2": lo step "1" diventa una forma (stesso posto nella pila), il badge passa a "1"
        // e la lente deve mostrarlo, non la copia in cache.
        let renderer = DocumentRenderer()
        let first = Annotation(id: TestDocuments.id(60), kind: .step(StepData(center: CGPoint(x: 20, y: 180), diameter: 20, label: StepLabel())),
                               style: Style(stroke: nil, fill: .accentRed))
        let second = Annotation(id: TestDocuments.id(61), kind: .step(StepData(center: CGPoint(x: 60, y: 60), diameter: 40, label: StepLabel())),
                                style: Style(stroke: nil, fill: .accentRed))
        let magnifier = Annotation(kind: .magnifier(MagnifierData(source: CGRect(x: 40, y: 40, width: 40, height: 40), target: CGRect(x: 110, y: 110, width: 80, height: 80),
                                                                  shape: .rectangle, showsConnector: false)), style: Style(stroke: nil))
        _ = try render([first, second, magnifier], renderer: renderer)
        var shape = first
        shape.kind = .shape(ShapeData(rect: CGRect(x: 10, y: 170, width: 20, height: 20), shape: .rectangle))
        let cached = PixelBuffer(try render([shape, second, magnifier], renderer: renderer))
        let fresh = PixelBuffer(try render([shape, second, magnifier]))
        #expect(cached.differingPixelFraction(from: fresh, channelTolerance: 1) == 0)
    }
}
