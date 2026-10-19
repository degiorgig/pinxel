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

    /// Un file con `document.json` così com'è: `version` 1 per i documenti della prima versione.
    func archive(json: Data, version: Int, background: Data? = nil) throws -> Data {
        var zip = ZipWriter()
        try zip.add(name: "manifest.json", data: Data(#"{"format":"pinxel","version":\#(version),"appVersion":"0.1.0"}"#.utf8), method: .store)
        try zip.add(name: "document.json", data: json, method: .deflate)
        try zip.add(name: "background.png", data: background ?? backgroundPNG, method: .store)
        return try zip.finish()
    }

    /// Documento della versione 1: quello di prova con `background` e `imageOperations` al posto della cattura.
    func v1JSON(operations: [ImageOperation] = []) throws -> Data {
        var document = TestDocuments.document(annotations: [])
        document.annotations = document.userAnnotations
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as? [String: Any])
        object["background"] = ["name": "background.png"]
        object["imageOperations"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(operations))
        return try JSONSerialization.data(withJSONObject: object)
    }

    func expectInvalid(_ data: Data, sourceLocation: SourceLocation = #_sourceLocation) {
        do {
            _ = try PinxelArchive.read(data)
            Issue.record("expected invalidDocument", sourceLocation: sourceLocation)
        } catch PinxelArchiveError.invalidDocument {
            // atteso
        } catch {
            Issue.record("unexpected \(error)", sourceLocation: sourceLocation)
        }
    }

    func expectInvalid(_ document: PinxelDocument, sourceLocation: SourceLocation = #_sourceLocation) throws {
        expectInvalid(try archive(json: JSONEncoder().encode(document), version: 2), sourceLocation: sourceLocation)
    }

    @Test func overflowingCropIsRejected() throws {
        expectInvalid(try archive(json: v1JSON(operations: [.crop(PixelRect(x: Int.max, y: 0, width: 10, height: 10))]), version: 1))
    }

    @Test func infinitePaddingIsRejected() throws {
        var document = TestDocuments.document(annotations: [])
        document.canvasStyle.padding = 1e308
        try expectInvalid(document)
    }

    @Test func hugeResizeIsRejected() throws {
        expectInvalid(try archive(json: v1JSON(operations: [.resize(PixelSize(width: 60000, height: 60000))]), version: 1))
    }

    @Test func hugeCanvasIsRejected() throws {
        var document = TestDocuments.document(annotations: [])
        document.canvasSize = PixelSize(width: 60000, height: 10)
        try expectInvalid(document)
    }

    @Test func duplicateAnnotationIDsAreRejected() throws {
        let shape = Annotation(kind: .shape(ShapeData(rect: CGRect(x: 1, y: 1, width: 5, height: 5), shape: .rectangle)))
        try expectInvalid(TestDocuments.document(annotations: [shape, shape]))
    }

    @Test func backgroundSizeMismatchIsRejected() throws {
        let other = try ImageCodec.encode(TestImages.solid(width: 50, height: 50, red: 1, green: 0, blue: 0), type: .png)
        expectInvalid(try archive(json: v1JSON(), version: 1, background: other))
    }

    @Test func oversizedImageIsRejected() throws {
        let huge = try ImageCodec.encode(TestImages.solid(width: 40000, height: 1, red: 1, green: 0, blue: 0), type: .png)
        expectInvalid(try archive(json: JSONEncoder().encode(TestDocuments.document(annotations: [])), version: 2, background: huge))
    }
}
