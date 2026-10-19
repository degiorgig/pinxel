import Foundation
import Testing
@testable import AppCore
import PinxelTestSupport

struct AppCoreCatalogTests {
    @Test func catalogIsComplete() throws {
        #expect(try CatalogValidation.problems(inCatalogAt: Catalogs.url(module: "AppCore")) == [])
    }

    @Test func defaultTemplatePerLanguage() {
        #expect(FileNamer.defaultTemplate(for: "en") == "'Pinxel' yyyy-MM-dd 'at' HH.mm.ss")
        #expect(FileNamer.defaultTemplate(for: "it") == "'Pinxel' yyyy-MM-dd 'alle' HH.mm.ss")
        #expect(FileNamer.defaultTemplate(for: "de") == "'Pinxel' yyyy-MM-dd 'um' HH.mm.ss")
        #expect(FileNamer.defaultTemplate(for: "fr") == "'Pinxel' yyyy-MM-dd 'à' HH.mm.ss")
        #expect(FileNamer.defaultTemplate(for: "es") == "'Pinxel' yyyy-MM-dd 'at' HH.mm.ss")
    }

    @Test func theOldDefaultFollowsTheLanguage() {
        var settings = CaptureSettings()
        settings.fileNameTemplate = FileNamer.legacyDefaultTemplate
        #expect(settings.effectiveFileNameTemplate == FileNamer.defaultTemplate)
    }

    @Test func aCustomTemplateNeverChanges() {
        var settings = CaptureSettings()
        settings.fileNameTemplate = "'Shot' HH-mm"
        #expect(settings.effectiveFileNameTemplate == "'Shot' HH-mm")
    }

    @Test func titlesAreEnglishInTests() {
        #expect(PostCaptureAction.quickPreview.title == "Quick Preview")
        #expect(HotKeyAction.area.title == "Capture Area")
        #expect(KeyCombo(keyCode: 0x31, modifiers: KeyCombo.control).displayString.contains("Space"))
    }
}
