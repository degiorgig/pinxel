import CoreGraphics
import Foundation
import Testing
import DocumentModel
@testable import Persistence
import Rendering
import AppCore
import PinxelTestSupport

struct DocumentV2Tests {
    @Test func captureIsAnImageObjectAtTheBottom() throws {
        let contents = try CaptureDocumentBuilder.make(image: TestImages.quadrants(), scale: 2, metadata: CaptureMetadata())
        #expect(contents.document.canvasSize == PixelSize(width: 400, height: 300))
        guard case .image(let data) = contents.document.annotations.first?.kind else { Issue.record("no image"); return }
        #expect(data.rect == CGRect(x: 0, y: 0, width: 400, height: 300))
        #expect(contents.images[data.asset] != nil)
    }

    @Test func roundTripKeepsTheDocument() throws {
        let contents = try CaptureDocumentBuilder.make(image: TestImages.quadrants(), scale: 2, metadata: CaptureMetadata())
        let data = try PinxelArchive.write(document: contents.document, images: contents.images, thumbnail: Data([1]), appVersion: "0.1.0")
        let reread = try PinxelArchive.read(data)
        #expect(reread.document == contents.document)
        #expect(!reread.isReadOnly)
    }

    @Test func emptyDocumentMakesAThumbnail() throws {
        let blank = try CaptureDocumentBuilder.blank(scale: 2)
        #expect(blank.document.annotations.isEmpty)
        #expect(blank.document.canvasSize == PixelSize(width: 0, height: 0))
        let thumbnail = try Thumbnailer.make(blank.document, assets: try blank.assetProvider())
        #expect(!thumbnail.isEmpty)
        _ = try PinxelArchive.write(document: blank.document, images: blank.images, thumbnail: thumbnail, appVersion: "0.1.0")
    }

    @Test func versionThreeIsReadOnly() throws {
        let contents = try CaptureDocumentBuilder.make(image: TestImages.quadrants(), scale: 2, metadata: CaptureMetadata())
        var zip = ZipWriter()
        let encoder = JSONEncoder()
        try zip.add(name: "manifest.json", data: encoder.encode(PinxelManifest(format: "pinxel", version: 3, appVersion: "9")), method: .deflate)
        try zip.add(name: "document.json", data: encoder.encode(contents.document), method: .deflate)
        for (ref, data) in contents.images { try zip.add(name: ref.name, data: data, method: .store) }
        #expect(try PinxelArchive.read(zip.finish()).isReadOnly)
    }
}
