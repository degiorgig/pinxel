import Foundation
import Testing
@testable import DocumentModel
import PinxelTestSupport

struct DocumentTests {
    let size = PixelSize(width: 400, height: 300)

    @Test func documentRoundTrips() throws {
        var document = TestDocuments.document()
        document.canvasStyle = CanvasStyle(padding: 12, backgroundColor: .white, border: Border(color: .black, width: 2), shadow: Shadow())
        #expect(try roundTrip(document) == document)
    }

    @Test func imageSizeIsTheCanvas() {
        var document = TestDocuments.document(size: size)
        #expect(document.imageSize == size)
        document.canvasSize = PixelSize(width: 150, height: 80)
        #expect(document.imageSize == PixelSize(width: 150, height: 80))
    }

    @Test func theCaptureIsTheFirstObject() {
        let document = TestDocuments.document(size: size)
        #expect(document.annotations.first == TestDocuments.capture(size: size))
        #expect(document.userAnnotations == TestDocuments.allKindsAnnotations())
    }

    @Test func emptyCanvasIsValidOnlyWhenBothSidesAreZero() {
        var document = TestDocuments.document(annotations: [])
        document.annotations = []
        document.canvasSize = PixelSize(width: 0, height: 0)
        #expect(document.validationError() == nil)
        document.canvasSize = PixelSize(width: 0, height: 10)
        #expect(document.validationError() != nil)
    }

    @Test func cropOutsideImageIsClamped() {
        let op = ImageOperation.crop(PixelRect(x: 350, y: -20, width: 200, height: 100))
        #expect(op.resultSize(from: size) == PixelSize(width: 50, height: 80))
    }

    @Test func cropMappingTranslates() {
        let mapping = ImageOperation.crop(PixelRect(x: 30, y: 40, width: 100, height: 100)).mapping(from: size)
        #expect(mapping.map(CGPoint(x: 30, y: 40)) == CGPoint(x: 0, y: 0))
        #expect(mapping.map(CGPoint(x: 10, y: 10)) == CGPoint(x: -20, y: -30))
        #expect(mapping.lengthScale == 1)
    }

    @Test func resizeMappingScales() {
        let mapping = ImageOperation.resize(PixelSize(width: 200, height: 75)).mapping(from: size)
        #expect(mapping.map(CGPoint(x: 100, y: 100)) == CGPoint(x: 50, y: 25))
        #expect(abs(mapping.lengthScale - (0.5 * 0.25).squareRoot()) < 1e-9)
    }

    @Test func cutOutMappingCollapsesBand() {
        let cut = CutOut(axis: .horizontal, start: 100, length: 50, edge: .zigzag)
        let mapping = ImageOperation.cutOut(cut).mapping(from: size)
        #expect(mapping.map(CGPoint(x: 7, y: 80)) == CGPoint(x: 7, y: 80))
        #expect(mapping.map(CGPoint(x: 7, y: 120)) == CGPoint(x: 7, y: 100))
        #expect(mapping.map(CGPoint(x: 7, y: 200)) == CGPoint(x: 7, y: 150))
        #expect(ImageOperation.cutOut(cut).resultSize(from: size) == PixelSize(width: 400, height: 250))

        let vertical = ImageOperation.cutOut(CutOut(axis: .vertical, start: 380, length: 100, edge: .straight))
        #expect(vertical.resultSize(from: size) == PixelSize(width: 380, height: 300))
        #expect(vertical.mapping(from: size).map(CGPoint(x: 390, y: 5)) == CGPoint(x: 380, y: 5))
    }

    @Test func transformedMovesEveryGeometry() {
        let mapping = ImageOperation.crop(PixelRect(x: 10, y: 20, width: 300, height: 200)).mapping(from: size)
        for annotation in TestDocuments.allKindsAnnotations() {
            let moved = annotation.transformed(by: mapping)
            #expect(moved.id == annotation.id)
            #expect(moved.style == annotation.style)
            let expected = annotation.bounds.offsetBy(dx: -10, dy: -20)
            #expect(abs(moved.bounds.minX - expected.minX) < 1e-9, "\(annotation.kind.typeName)")
            #expect(abs(moved.bounds.minY - expected.minY) < 1e-9, "\(annotation.kind.typeName)")
            #expect(abs(moved.bounds.width - expected.width) < 1e-9, "\(annotation.kind.typeName)")
        }
    }

    @Test func resizeScalesStepDiameter() {
        let step = Annotation(kind: .step(StepData(center: CGPoint(x: 100, y: 100), diameter: 40)))
        let moved = step.transformed(by: ImageOperation.resize(PixelSize(width: 200, height: 150)).mapping(from: size))
        guard case .step(let data) = moved.kind else {
            Issue.record("expected step")
            return
        }
        #expect(data.center == CGPoint(x: 50, y: 50))
        #expect(abs(data.diameter - 20) < 1e-9)
    }

    @Test func extendGrowsTheCanvasAndKeepsPoints() {
        let op = ImageOperation.extend(PixelSize(width: 600, height: 200))
        #expect(op.resultSize(from: size) == PixelSize(width: 600, height: 300))
        #expect(op.mapping(from: size).map(CGPoint(x: 12, y: 34)) == CGPoint(x: 12, y: 34))
        #expect(op.name == "Estendi tela")
    }

    @Test func extendRoundTripsThroughJSON() throws {
        let op = ImageOperation.extend(PixelSize(width: 640, height: 480))
        let decoded = try JSONDecoder().decode(ImageOperation.self, from: JSONEncoder().encode(op))
        #expect(decoded == op)
    }
}
