import DocumentModel
import Foundation
import Persistence
import PinxelTestSupport
import Testing
@testable import AppCore

struct DocumentRecoveryTests {
    private func archive() throws -> Data {
        let contents = try CaptureDocumentBuilder.make(image: TestImages.quadrants(), scale: 2, metadata: CaptureMetadata())
        return try PinxelArchive.write(document: contents.document, images: contents.images, thumbnail: Data(), appVersion: "0.1.0")
    }

    /// Rovina i byte compressi di `document.json` (subito dopo il nome nell'intestazione locale), lasciando intatto lo sfondo.
    private func damaged(_ data: Data) -> Data {
        var bytes = data
        guard let range = bytes.range(of: Data("document.json".utf8)) else { return bytes }
        for index in range.upperBound..<min(range.upperBound + 16, bytes.count) { bytes[index] ^= 0xFF }
        return bytes
    }

    @Test func damagedFileGivesANewDocumentWithTheBackground() throws {
        let data = damaged(try archive())
        #expect(throws: (any Error).self) { try PinxelArchive.read(data) }
        let contents = try #require(DocumentRecovery.contents(fromDamaged: data, scale: 2))
        #expect(contents.document.canvasSize == PixelSize(width: 400, height: 300))
        #expect(contents.document.scale == 2)
        // Solo la cattura recuperata, come immagine in fondo.
        #expect(contents.document.annotations.count == 1)
        guard case .image(let capture) = contents.document.annotations.first?.kind else { Issue.record("no capture"); return }
        #expect(capture.rect == CGRect(x: 0, y: 0, width: 400, height: 300))
    }

    @Test func garbageGivesNothing() {
        #expect(DocumentRecovery.contents(fromDamaged: Data("non è un file Pinxel".utf8), scale: 2) == nil)
    }
}
