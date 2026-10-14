import Foundation
import Testing
import DocumentModel
import Persistence
@testable import AppCore
import PinxelTestSupport

struct CaptureDocumentTests {
    @Test func buildsDocumentFromCapture() throws {
        let metadata = CaptureMetadata(captureDate: Date(timeIntervalSinceReferenceDate: 1000), appName: "Safari", bundleIdentifier: "com.apple.Safari", windowTitle: "Apple")
        let contents = try CaptureDocumentBuilder.make(image: TestImages.quadrants(), scale: 2, metadata: metadata)
        #expect(contents.document.canvasSize == PixelSize(width: 400, height: 300))
        #expect(contents.document.scale == 2)
        #expect(contents.document.annotations.isEmpty)
        #expect(contents.document.metadata == metadata)
        #expect(contents.document.background == ImageAssetRef(name: "background.png"))
        #expect(contents.document.validationError() == nil)
        let decoded = try #require(contents.assetProvider().image(for: contents.document.background))
        #expect(decoded.width == 400)

        let reread = try PinxelArchive.read(PinxelArchive.write(document: contents.document, images: contents.images, thumbnail: Data(), appVersion: "0.1.0"))
        #expect(reread.document == contents.document)
    }
}
