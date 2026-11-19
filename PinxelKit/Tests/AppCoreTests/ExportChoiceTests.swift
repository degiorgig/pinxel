import Persistence
import Testing
import UniformTypeIdentifiers
@testable import AppCore

struct ExportChoiceTests {
    @Test func defaultsArePNGAtOneX() {
        #expect(ExportChoice().scale == .oneX)
        #expect(ExportChoice().fileType == .png)
    }

    @Test func qualityMapsToZeroOneAndIsClamped() {
        var choice = ExportChoice()
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
        var choice = ExportChoice()
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
