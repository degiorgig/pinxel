import CoreGraphics
import Foundation
import Testing
import DocumentModel
import Rendering
@testable import Persistence
import PinxelTestSupport

/// File `.pinxel` ben formati come ZIP ma con valori ostili in document.json o nelle immagini.
struct HostileDocumentTests {
    let backgroundPNG = try! ImageCodec.encode(TestImages.quadrants(), type: .png)

    func archive(_ document: PinxelDocument, background: Data? = nil) throws -> Data {
        var zip = ZipWriter()
        try zip.add(name: "manifest.json", data: Data(#"{"format":"pinxel","version":1,"appVersion":"0.1.0"}"#.utf8), method: .store)
        try zip.add(name: "document.json", data: JSONEncoder().encode(document), method: .deflate)
        try zip.add(name: "background.png", data: background ?? backgroundPNG, method: .store)
        return try zip.finish()
    }

    func expectInvalid(_ document: PinxelDocument, background: Data? = nil, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let data = try archive(document, background: background)
        do {
            _ = try PinxelArchive.read(data)
            Issue.record("expected invalidDocument", sourceLocation: sourceLocation)
        } catch PinxelArchiveError.invalidDocument {
            // atteso
        }
    }

    @Test func overflowingCropIsRejected() throws {
        var document = TestDocuments.document(annotations: [])
        document.imageOperations = [.crop(PixelRect(x: Int.max, y: 0, width: 10, height: 10))]
        try expectInvalid(document)
    }

    @Test func infinitePaddingIsRejected() throws {
        var document = TestDocuments.document(annotations: [])
        document.canvasStyle.padding = 1e308
        try expectInvalid(document)
    }

    @Test func hugeResizeIsRejected() throws {
        var document = TestDocuments.document(annotations: [])
        document.imageOperations = [.resize(PixelSize(width: 60000, height: 60000))]
        try expectInvalid(document)
    }

    @Test func duplicateAnnotationIDsAreRejected() throws {
        let shape = Annotation(kind: .shape(ShapeData(rect: CGRect(x: 1, y: 1, width: 5, height: 5), shape: .rectangle)))
        try expectInvalid(TestDocuments.document(annotations: [shape, shape]))
    }

    @Test func backgroundSizeMismatchIsRejected() throws {
        let other = try ImageCodec.encode(TestImages.solid(width: 50, height: 50, red: 1, green: 0, blue: 0), type: .png)
        try expectInvalid(TestDocuments.document(annotations: []), background: other)
    }
}
