import Foundation
import Testing
@testable import DocumentModel
import PinxelTestSupport

struct ContentFitTests {
    func image(_ rect: CGRect, rotation: Double = 0) -> Annotation {
        Annotation(kind: .image(PlacedImageData(rect: rect, asset: ImageAssetRef(name: "a.png"))), style: Style(stroke: nil, lineWidth: 0), rotation: rotation)
    }

    func document(_ annotations: [Annotation], size: PixelSize = PixelSize(width: 100, height: 100)) -> PinxelDocument {
        var document = TestDocuments.document(annotations: [], size: size)
        document.annotations = annotations
        return document
    }

    @Test func imagesGiveTheirRectangle() {
        #expect(ContentFit.bounds(of: [image(CGRect(x: 10, y: 20, width: 30, height: 40))]) == PixelRect(x: 10, y: 20, width: 30, height: 40))
    }

    @Test func boundsRoundOutward() {
        #expect(ContentFit.bounds(of: [image(CGRect(x: 0.5, y: 0.5, width: 10, height: 10))]) == PixelRect(x: 0, y: 0, width: 11, height: 11))
    }

    @Test func thickStrokeAndArrowHeadsCount() {
        let arrow = Annotation(kind: .arrow(ArrowData(line: LineGeometry(start: CGPoint(x: 0, y: 50), end: CGPoint(x: 100, y: 50)),
                                                      heads: ArrowHeads(start: .none, end: .triangle))),
                               style: Style(stroke: .black, lineWidth: 10))
        // Tratto 5 + punta max(30,10)*0.6 = 18 → 23 per lato.
        #expect(ContentFit.bounds(of: [arrow]) == PixelRect(x: -23, y: 27, width: 146, height: 46))
    }

    @Test func rotationCounts() throws {
        let rotated = image(CGRect(x: 0, y: 0, width: 100, height: 10), rotation: .pi / 2)
        let rect = try #require(ContentFit.bounds(of: [rotated]))
        #expect(rect.width == 10 && rect.height == 100)
    }

    @Test func shadowCounts() {
        var shape = Annotation(kind: .shape(ShapeData(rect: CGRect(x: 0, y: 0, width: 10, height: 10), shape: .rectangle)), style: Style(stroke: nil, lineWidth: 0))
        shape.style.shadow = Shadow(offset: CGSize(width: 0, height: 10), blur: 2, color: .black)
        #expect(ContentFit.bounds(of: [shape]) == PixelRect(x: -3, y: 0, width: 16, height: 23))
    }

    @Test func noObjectsNoBounds() {
        #expect(ContentFit.bounds(of: []) == nil)
    }

    @Test func hugeCoordinatesDoNotCrash() {
        let far = image(CGRect(x: 1e300, y: -1e300, width: 10, height: .nan))
        _ = ContentFit.bounds(of: [far, image(CGRect(x: 0, y: 0, width: 10, height: 10))])
        _ = FitCanvas(in: document([far]))
    }

    @Test func fitTranslatesToTheOriginAndSetsTheSize() throws {
        let doc = document([image(CGRect(x: -20, y: 10, width: 50, height: 30))])
        let fit = try #require(FitCanvas(in: doc))
        var after = doc
        fit.apply(to: &after)
        #expect(after.canvasSize == PixelSize(width: 50, height: 30))
        guard case .image(let data) = after.annotations[0].kind else { Issue.record("not an image"); return }
        #expect(data.rect == CGRect(x: 0, y: 0, width: 50, height: 30))
        #expect(fit.offset == CGVector(dx: 20, dy: -10))
        fit.revert(on: &after)
        #expect(after == doc)
    }

    @Test func alreadyFittedNeedsNoCommand() {
        #expect(FitCanvas(in: document([image(CGRect(x: 0, y: 0, width: 100, height: 100))])) == nil)
    }

    @Test func emptyDocumentFitsToZero() throws {
        let fit = try #require(FitCanvas(in: document([])))
        var after = document([])
        fit.apply(to: &after)
        #expect(after.canvasSize == PixelSize(width: 0, height: 0))
    }

    @Test func sizeStopsAtTheLimit() throws {
        let limit = PinxelDocument.maxImageSide
        let fit = try #require(FitCanvas(in: document([image(CGRect(x: 0, y: 0, width: Double(limit) + 500, height: 10))])))
        #expect(fit.sizeAfter == PixelSize(width: limit, height: 10))
    }
}
