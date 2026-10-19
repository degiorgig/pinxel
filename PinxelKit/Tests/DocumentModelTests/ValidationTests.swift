import Foundation
import Testing
@testable import DocumentModel
import PinxelTestSupport

struct ValidationTests {
    @Test func validDocumentPasses() {
        #expect(TestDocuments.document().validationError() == nil)
    }

    @Test func clampedDoesNotOverflow() {
        let rect = PixelRect(x: Int.max, y: Int.max - 1, width: 10, height: Int.max)
        let clamped = rect.clamped(to: PixelSize(width: 100, height: 100))
        #expect(clamped.width == 0 && clamped.height == 0)
        let negative = PixelRect(x: Int.min, y: 0, width: Int.min, height: 10).clamped(to: PixelSize(width: 100, height: 100))
        #expect(negative.width == 0)
    }

    @Test func hostileValuesAreRejected() {
        var padding = TestDocuments.document()
        padding.canvasStyle.padding = 1e308
        #expect(padding.validationError() != nil)

        // Le operazioni ostili dei file della versione 1: LegacyDocumentV1 e HostileDocumentTests.
        var size = TestDocuments.document(size: PixelSize(width: 0, height: 300))
        #expect(size.validationError() != nil)
        size = TestDocuments.document(size: PixelSize(width: 100_000, height: 300))
        #expect(size.validationError() != nil)

        var scale = TestDocuments.document()
        scale.scale = .nan
        #expect(scale.validationError() != nil)

        var duplicates = TestDocuments.document()
        duplicates.annotations.append(duplicates.annotations[0])
        #expect(duplicates.validationError() != nil)
    }

    @Test func reorderToleratesDuplicateIDs() {
        var document = TestDocuments.document()
        document.annotations.append(document.annotations[1])
        let command = ReorderAnnotations.bringToFront([document.annotations[2].id], in: document)
        command.apply(to: &document)
        #expect(document.annotations.last?.id == TestDocuments.id(2))
    }
}
