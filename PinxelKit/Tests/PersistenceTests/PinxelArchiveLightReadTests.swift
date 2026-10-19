import Foundation
import Testing
import DocumentModel
import Rendering
@testable import Persistence
import PinxelTestSupport

struct PinxelArchiveLightReadTests {
    func archive(thumbnail: Data = Data([7, 8, 9])) throws -> Data {
        let images = [TestDocuments.background: try ImageCodec.encode(TestImages.quadrants(), type: .png),
                      TestDocuments.placedImage: try ImageCodec.encode(TestImages.solid(width: 10, height: 10, red: 0, green: 0.6, blue: 1), type: .png)]
        return try PinxelArchive.write(document: TestDocuments.document(), images: images, thumbnail: thumbnail, appVersion: "0.1.0")
    }

    @Test func readDocumentReturnsTheDocument() throws {
        #expect(try PinxelArchive.readDocument(archive()) == TestDocuments.document())
    }

    @Test func readDocumentRejectsOtherFiles() {
        #expect(throws: (any Error).self) { try PinxelArchive.readDocument(Data("hello".utf8)) }
    }

    @Test func readThumbnailReturnsTheStoredPNG() throws {
        #expect(PinxelArchive.readThumbnail(try archive()) == Data([7, 8, 9]))
        #expect(PinxelArchive.readThumbnail(Data("hello".utf8)) == nil)
    }
}
