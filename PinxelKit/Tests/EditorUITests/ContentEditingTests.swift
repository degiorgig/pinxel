import CoreGraphics
import DocumentModel
import Foundation
import PinxelTestSupport
import Rendering
import Testing
@testable import EditorUI

struct ContentEditingTests {
    final class Images {
        var stored: [ImageAssetRef: CGImage] = [:]
        func image(_ ref: ImageAssetRef) -> CGImage? { stored[ref] }
        func add(_ image: CGImage) -> ImageAssetRef? {
            let ref = ImageAssetRef(name: "assets/\(stored.count).png")
            stored[ref] = image
            return ref
        }
    }

    func placed(_ rect: CGRect, _ ref: ImageAssetRef, rotation: Double = 0) -> Annotation {
        Annotation(kind: .image(PlacedImageData(rect: rect, asset: ref)), style: Style(stroke: nil, lineWidth: 0), rotation: rotation)
    }

    func rect(_ annotation: Annotation) -> CGRect? {
        if case .image(let data) = annotation.kind { return data.rect }
        return nil
    }

    func step(_ center: CGPoint) -> Annotation {
        Annotation(kind: .step(StepData(center: center, diameter: 20, label: StepLabel())), style: Style(stroke: nil, fill: .accentRed))
    }

    @Test func cropCutsImagePixelsAndDropsWhatIsOutside() throws {
        let images = Images()
        let capture = ImageAssetRef(name: "capture.png")
        images.stored[capture] = TestImages.quadrants(width: 400, height: 300)
        let result = ContentEditing.cropped([placed(CGRect(x: 0, y: 0, width: 400, height: 300), capture), step(CGPoint(x: 350, y: 250)), step(CGPoint(x: 100, y: 100))],
                                            to: PixelRect(x: 0, y: 0, width: 200, height: 150), images: images.image, add: images.add)
        #expect(result.count == 2)                       // lo step a (350,250) era tutto fuori
        #expect(rect(result[0]) == CGRect(x: 0, y: 0, width: 200, height: 150))
        guard case .image(let data) = result[0].kind, let pixels = images.stored[data.asset] else { Issue.record("no cropped image"); return }
        #expect(pixels.width == 200 && pixels.height == 150)
    }

    @Test func anImageWhoseOnlyShadowReachesTheCropIsDropped() {
        // L'ombra (12 px in basso) entra nel riquadro, i pixel no: niente immagine con un riquadro nullo (non si salverebbe).
        let images = Images()
        var shadowed = placed(CGRect(x: 0, y: 0, width: 100, height: 100), ImageAssetRef(name: "s.png"))
        shadowed.style.shadow = Shadow()
        let result = ContentEditing.cropped([shadowed], to: PixelRect(x: 0, y: 105, width: 100, height: 50), images: images.image, add: images.add)
        #expect(result.isEmpty)
    }

    @Test func cropKeepsAnnotationsAcrossTheEdgeWhole() {
        let images = Images()
        let crossing = step(CGPoint(x: 200, y: 75))
        let result = ContentEditing.cropped([crossing], to: PixelRect(x: 0, y: 0, width: 200, height: 150), images: images.image, add: images.add)
        #expect(result == [crossing])
    }

    @Test func cropRespectsTheImageDensity() throws {
        let images = Images()
        let ref = ImageAssetRef(name: "retina.png")
        images.stored[ref] = TestImages.quadrants(width: 800, height: 600)   // 2 pixel dell'immagine per pixel del documento
        let result = ContentEditing.cropped([placed(CGRect(x: 0, y: 0, width: 400, height: 300), ref)], to: PixelRect(x: 100, y: 0, width: 100, height: 300),
                                            images: images.image, add: images.add)
        guard case .image(let data) = result[0].kind, let pixels = images.stored[data.asset] else { Issue.record("no cropped image"); return }
        #expect(data.rect == CGRect(x: 100, y: 0, width: 100, height: 300))
        #expect(pixels.width == 200 && pixels.height == 600)
    }

    @Test func rotatedImagesAcrossTheCropStayWhole() {
        let images = Images()
        let rotated = placed(CGRect(x: 150, y: 50, width: 100, height: 50), ImageAssetRef(name: "r.png"), rotation: 0.3)
        #expect(ContentEditing.cropped([rotated], to: PixelRect(x: 0, y: 0, width: 200, height: 200), images: images.image, add: images.add) == [rotated])
    }

    @Test func scaleMovesAndResizesEverything() {
        let result = ContentEditing.scaled([placed(CGRect(x: 0, y: 0, width: 400, height: 300), ImageAssetRef(name: "a.png")), step(CGPoint(x: 100, y: 100))],
                                           from: PixelSize(width: 400, height: 300), to: PixelSize(width: 200, height: 150))
        #expect(rect(result[0]) == CGRect(x: 0, y: 0, width: 200, height: 150))
        guard case .step(let data) = result[1].kind else { Issue.record("not a step"); return }
        #expect(data.center == CGPoint(x: 50, y: 50))
    }

    @Test func cutRemovesTheBandFromImagesAndPullsTheRestCloser() throws {
        let images = Images()
        let ref = ImageAssetRef(name: "c.png")
        images.stored[ref] = TestImages.quadrants(width: 400, height: 300)
        let cut = CutOut(axis: .horizontal, start: 100, length: 50)
        let result = ContentEditing.cut([placed(CGRect(x: 0, y: 0, width: 400, height: 300), ref), step(CGPoint(x: 50, y: 200))],
                                        cut, canvas: PixelSize(width: 400, height: 300), images: images.image, add: images.add)
        #expect(rect(result[0]) == CGRect(x: 0, y: 0, width: 400, height: 250))
        guard case .image(let data) = result[0].kind, let pixels = images.stored[data.asset] else { Issue.record("no cut image"); return }
        #expect(pixels.height == 250)
        guard case .step(let moved) = result[1].kind else { Issue.record("not a step"); return }
        #expect(moved.center == CGPoint(x: 50, y: 150))
    }

    @Test func cutThroughPartOfAnImage() throws {
        let images = Images()
        let ref = ImageAssetRef(name: "p.png")
        images.stored[ref] = TestImages.quadrants(width: 100, height: 100)
        let result = ContentEditing.cut([placed(CGRect(x: 0, y: 120, width: 100, height: 100), ref)], CutOut(axis: .horizontal, start: 100, length: 50),
                                        canvas: PixelSize(width: 100, height: 220), images: images.image, add: images.add)
        // La fascia 100..<150 toglie 30 righe dall'immagine (120..<150); l'immagine sale a 100.
        #expect(rect(result[0]) == CGRect(x: 0, y: 100, width: 100, height: 70))
    }

    @Test func rotatedImagesInTheBandMoveWithoutCutting() {
        let images = Images()
        let rotated = placed(CGRect(x: 0, y: 160, width: 100, height: 20), ImageAssetRef(name: "r.png"), rotation: 0.5)
        let result = ContentEditing.cut([rotated], CutOut(axis: .horizontal, start: 100, length: 50), canvas: PixelSize(width: 100, height: 200),
                                        images: images.image, add: images.add)
        #expect(rect(result[0]) == CGRect(x: 0, y: 110, width: 100, height: 20))
    }

    @Test func pasteReplacesTheBottomImageKeepingItsPlace() throws {
        let annotations = [step(CGPoint(x: 10, y: 10)), placed(CGRect(x: 30, y: 40, width: 400, height: 300), ImageAssetRef(name: "old.png"))]
        let command = ContentEditing.replacingBottomImage(in: annotations, asset: ImageAssetRef(name: "new.png"), size: CGSize(width: 100, height: 50), newID: UUID())
        var document = TestDocuments.document(annotations: [], size: PixelSize(width: 430, height: 340))
        document.annotations = annotations
        command.apply(to: &document)
        #expect(document.annotations.count == 2)
        guard case .image(let data) = document.annotations[1].kind else { Issue.record("not an image"); return }
        #expect(data.rect == CGRect(x: 30, y: 40, width: 100, height: 50) && data.asset.name == "new.png")
    }

    @Test func pasteWithoutImagesAddsOneAtTheBottom() {
        var document = TestDocuments.document(annotations: [], size: PixelSize(width: 10, height: 10))
        document.annotations = [step(CGPoint(x: 5, y: 5))]
        let id = UUID()
        ContentEditing.replacingBottomImage(in: document.annotations, asset: ImageAssetRef(name: "n.png"), size: CGSize(width: 10, height: 10), newID: id).apply(to: &document)
        #expect(document.annotations.first?.id == id)
    }
}
