import CoreGraphics
import Foundation
import Testing
import DocumentModel
import Rendering
@testable import Persistence
import PinxelTestSupport

struct PinxelArchiveTests {
    func images() throws -> [ImageAssetRef: Data] {
        [
            TestDocuments.background: try ImageCodec.encode(TestImages.quadrants(), type: .png),
            TestDocuments.placedImage: try ImageCodec.encode(TestImages.solid(width: 10, height: 10, red: 0, green: 0.6, blue: 1), type: .png),
        ]
    }

    func write(_ document: PinxelDocument = TestDocuments.document()) throws -> Data {
        try PinxelArchive.write(document: document, images: images(), thumbnail: Data([1, 2, 3]), appVersion: "0.1.0")
    }

    @Test func roundTrip() throws {
        let document = TestDocuments.document()
        let contents = try PinxelArchive.read(write(document))
        #expect(contents.document == document)
        #expect(contents.images == (try images()))
        #expect(contents.thumbnail == Data([1, 2, 3]))
        #expect(!contents.isReadOnly)
    }

    @Test func aPastedCaptureIsSavedAndReopened() throws {
        let pasted = ImageAssetRef(name: "assets/00000000-0000-0000-0000-000000000009.png")
        var document = TestDocuments.document()
        let image = TestImages.solid(width: 30, height: 20, red: 1, green: 0, blue: 0)
        document.annotations[0].kind = .image(PlacedImageData(rect: CGRect(x: 0, y: 0, width: 30, height: 20), asset: pasted))
        var files = try images()
        files[pasted] = try ImageCodec.encode(image, type: .png)
        let contents = try PinxelArchive.read(PinxelArchive.write(document: document, images: files, thumbnail: Data(), appVersion: "0.1.0"))
        #expect(contents.document == document)
        #expect(contents.images[pasted] != nil)
        // L'immagine di prima non serve più e non viene salvata.
        #expect(contents.images[TestDocuments.background] == nil)
    }

    @Test func archiveLayout() throws {
        let reader = try ZipReader(write())
        #expect(Set(reader.entries.map(\.name)) == ["manifest.json", "document.json", "background.png", TestDocuments.placedImage.name, "thumbnail.png"])
        let manifest = try JSONDecoder().decode(PinxelManifest.self, from: reader.data(for: "manifest.json"))
        #expect(manifest == PinxelManifest(format: "pinxel", version: 2, appVersion: "0.1.0"))
    }

    @Test func newerVersionOpensReadOnly() throws {
        let document = TestDocuments.document(annotations: [])
        var zip = ZipWriter()
        try zip.add(name: "manifest.json", data: Data(#"{"format":"pinxel","version":3,"appVersion":"9.0"}"#.utf8), method: .deflate)
        try zip.add(name: "document.json", data: JSONEncoder().encode(document), method: .deflate)
        try zip.add(name: "background.png", data: images()[TestDocuments.background]!, method: .store)
        let contents = try PinxelArchive.read(zip.finish())
        #expect(contents.isReadOnly)
        #expect(contents.document == document)
        #expect(contents.thumbnail == nil)
    }

    @Test func unknownAnnotationSurvivesArchive() throws {
        let raw = JSONValue.object(["emoji": .string("🔥"), "size": .number(3)])
        let document = TestDocuments.document(annotations: [Annotation(kind: .unknown(type: "sticker", raw: raw))])
        let once = try PinxelArchive.read(write(document))
        let twice = try PinxelArchive.read(PinxelArchive.write(document: once.document, images: once.images, thumbnail: Data(), appVersion: "0.1.0"))
        #expect(twice.document.annotations.last?.kind == .unknown(type: "sticker", raw: raw))
    }

    @Test func rejectsZipWithoutManifest() throws {
        var zip = ZipWriter()
        try zip.add(name: "other.txt", data: Data("x".utf8), method: .store)
        #expect(throws: PinxelArchiveError.notAPinxelFile) { try PinxelArchive.read(zip.finish()) }
    }

    @Test func rejectsWrongFormat() throws {
        var zip = ZipWriter()
        try zip.add(name: "manifest.json", data: Data(#"{"format":"other","version":1,"appVersion":"1"}"#.utf8), method: .store)
        #expect(throws: PinxelArchiveError.notAPinxelFile) { try PinxelArchive.read(zip.finish()) }
    }

    @Test func corruptDocumentIsReportedAndBackgroundRecovered() throws {
        let background = try images()[TestDocuments.background]!
        var zip = ZipWriter()
        try zip.add(name: "manifest.json", data: Data(#"{"format":"pinxel","version":1,"appVersion":"0.1.0"}"#.utf8), method: .store)
        try zip.add(name: "document.json", data: Data("{".utf8), method: .store)
        try zip.add(name: "background.png", data: background, method: .store)
        let data = try zip.finish()
        do {
            _ = try PinxelArchive.read(data)
            Issue.record("expected invalidDocument")
        } catch PinxelArchiveError.invalidDocument {
            // atteso
        }
        #expect(PinxelArchive.recoverBackground(data) == background)
        #expect(PinxelArchive.recoverBackground(Data("not a zip".utf8)) == nil)
    }

    @Test func missingAssetOnWriteAndRead() throws {
        let document = TestDocuments.document()
        #expect(throws: PinxelArchiveError.missingAsset(TestDocuments.placedImage.name)) {
            try PinxelArchive.write(document: document, images: [TestDocuments.background: Data([0])], thumbnail: Data(), appVersion: "0.1.0")
        }
        var zip = ZipWriter()
        try zip.add(name: "manifest.json", data: Data(#"{"format":"pinxel","version":2,"appVersion":"0.1.0"}"#.utf8), method: .store)
        try zip.add(name: "document.json", data: JSONEncoder().encode(document), method: .store)
        try zip.add(name: "background.png", data: images()[TestDocuments.background]!, method: .store)
        #expect(throws: PinxelArchiveError.missingAsset(TestDocuments.placedImage.name)) { try PinxelArchive.read(zip.finish()) }
    }

    @Test func assetProviderDecodesImages() throws {
        let provider = try PinxelArchive.read(write()).assetProvider()
        let background = try #require(provider.image(for: TestDocuments.background))
        #expect(background.width == 400 && background.height == 300)
        #expect(PixelBuffer(background).pixel(x: 10, y: 10) == RGBA8(r: 255, g: 0, b: 0))
    }

    @Test func smallBackgroundIsPNG() throws {
        let (ref, data) = try ImageCodec.encodeBackground(TestImages.quadrants())
        #expect(ref == ImageAssetRef(name: "background.png"))
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    @Test func largeBackgroundIsStoredAsHEIC() throws {
        let noise = TestImages.noise(width: 3000, height: 2500)
        let (ref, data) = try ImageCodec.encodeBackground(noise)
        #expect(ref == ImageAssetRef(name: "background.heic"))
        #expect(data.count < ImageCodec.heicThreshold)
        let decoded = try ImageCodec.decode(data)
        #expect(decoded.width == 3000 && decoded.height == 2500)
    }

    @Test func decodeRejectsGarbage() {
        #expect(throws: ImageCodecError.decodingFailed) { try ImageCodec.decode(Data("nope".utf8)) }
    }

    @Test func thumbnailFitsIn512() throws {
        let document = TestDocuments.document(annotations: [], size: PixelSize(width: 1000, height: 800))
        let provider = DictionaryAssetProvider([TestDocuments.background: TestImages.solid(width: 1000, height: 800, red: 0, green: 0, blue: 1)])
        let thumbnail = try ImageCodec.decode(Thumbnailer.make(document, assets: provider))
        #expect(thumbnail.width == 512 && thumbnail.height == 410)

        let small = TestDocuments.document(annotations: [], size: PixelSize(width: 200, height: 100))
        let smallProvider = DictionaryAssetProvider([TestDocuments.background: TestImages.solid(width: 200, height: 100, red: 0, green: 0, blue: 1)])
        let smallThumbnail = try ImageCodec.decode(Thumbnailer.make(small, assets: smallProvider))
        #expect(smallThumbnail.width == 200 && smallThumbnail.height == 100)
    }
}
