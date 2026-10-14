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

struct PastedImageScaleTests {
    @Test func retinaScreenshotIsTwoX() {
        #expect(CaptureDocumentBuilder.pastedScale(pixelWidth: 800, pointWidth: 400) == 2)
    }

    @Test func plainImageIsOneX() {
        #expect(CaptureDocumentBuilder.pastedScale(pixelWidth: 640, pointWidth: 640) == 1)
    }

    @Test func oddRatiosRoundAndStayInRange() {
        #expect(CaptureDocumentBuilder.pastedScale(pixelWidth: 1000, pointWidth: 480) == 2)
        #expect(CaptureDocumentBuilder.pastedScale(pixelWidth: 100, pointWidth: 400) == 1)
        #expect(CaptureDocumentBuilder.pastedScale(pixelWidth: 4000, pointWidth: 400) == 3)
        #expect(CaptureDocumentBuilder.pastedScale(pixelWidth: 400, pointWidth: 0) == 1)
    }
}
