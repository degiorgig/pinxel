import CoreGraphics
import DocumentModel
import PinxelTestSupport
import Testing
@testable import EditorUI

struct AnnotationClipboardTests {
    private let shape = Annotation(id: TestDocuments.id(1), kind: .shape(ShapeData(rect: CGRect(x: 20, y: 30, width: 40, height: 20), shape: .rectangle)), isLocked: true)
    private let image = Annotation(id: TestDocuments.id(2), kind: .image(PlacedImageData(rect: CGRect(x: 0, y: 0, width: 10, height: 10), asset: TestDocuments.placedImage)))

    @Test func encodeDecodeRoundTripsEveryKind() throws {
        let all = TestDocuments.allKindsAnnotations()
        #expect(try AnnotationClipboard.decode(AnnotationClipboard.encode(all)) == all)
    }

    @Test func pastedCopiesAreNewMovedAndUnlocked() {
        let copies = AnnotationClipboard.prepareForPaste([shape], makeID: { TestDocuments.id(77) })
        #expect(copies.count == 1)
        #expect(copies[0].id == TestDocuments.id(77))
        #expect(copies[0].bounds.origin == CGPoint(x: 30, y: 40))
        #expect(!copies[0].isLocked)
    }

    @Test func placedImagesAreNotPasted() {
        #expect(AnnotationClipboard.prepareForPaste([image, shape]).count == 1)
    }

    @Test func cropRectCoversTheAnnotationsWithMarginInsideTheCanvas() {
        let rect = AnnotationClipboard.cropRect(for: [shape], padding: 5, canvasSize: CGSize(width: 400, height: 300))
        #expect(rect == CGRect(x: 17, y: 27, width: 56, height: 36))
        let clipped = AnnotationClipboard.cropRect(for: [image], padding: 0, canvasSize: CGSize(width: 400, height: 300))
        #expect(clipped == CGRect(x: 0, y: 0, width: 18, height: 18))
    }

    @Test func cropRectIsNilWithoutVisibleBounds() {
        #expect(AnnotationClipboard.cropRect(for: [], padding: 0, canvasSize: CGSize(width: 10, height: 10)) == nil)
        let outside = Annotation(id: TestDocuments.id(3), kind: .shape(ShapeData(rect: CGRect(x: 900, y: 900, width: 5, height: 5), shape: .rectangle)))
        #expect(AnnotationClipboard.cropRect(for: [outside], padding: 0, canvasSize: CGSize(width: 100, height: 100)) == nil)
    }
}
