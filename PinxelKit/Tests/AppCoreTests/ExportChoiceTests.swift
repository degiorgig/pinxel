import Persistence
import Testing
import UniformTypeIdentifiers
@testable import AppCore

struct ExportChoiceTests {
    @Test func defaultScaleFollowsTheCapture() {
        #expect(ExportChoice(documentScale: 2).scale == .twoX)
        #expect(ExportChoice(documentScale: 1).scale == .oneX)
        #expect(ExportChoice(documentScale: 2).fileType == .png)
    }

    @Test func qualityMapsToZeroOneAndIsClamped() {
        var choice = ExportChoice(documentScale: 2)
        choice.fileType = .jpeg
        #expect(choice.format == .jpeg(quality: 0.9))
        choice.quality = 150
        #expect(choice.format == .jpeg(quality: 1))
        choice.fileType = .heic
        choice.quality = -5
        #expect(choice.format == .heic(quality: 0))
        choice.fileType = .png
        #expect(choice.format == .png)
        choice.fileType = .pdf
        #expect(choice.format == .pdf)
    }

    @Test func fileNameReplacesOnlyKnownExtensions() {
        var choice = ExportChoice(documentScale: 2)
        #expect(choice.fileName(from: "Cattura.pinxel") == "Cattura.png")
        #expect(choice.fileName(from: "Pinxel 2026-10-14 at 10.00.00") == "Pinxel 2026-10-14 at 10.00.00.png")
        #expect(choice.fileName(from: "") == "Pinxel.png")
        choice.fileType = .jpeg
        #expect(choice.fileName(from: "Cattura.PNG") == "Cattura.jpg")
    }

    @Test func fileTypesDescribeThemselves() {
        #expect(ExportFileType.jpeg.contentType == .jpeg)
        #expect(ExportFileType.pdf.fileExtension == "pdf")
        #expect(ExportFileType.heic.hasQuality && !ExportFileType.png.hasQuality)
    }
}
