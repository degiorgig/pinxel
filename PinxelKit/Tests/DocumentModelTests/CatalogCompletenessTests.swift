import Foundation
import Testing
@testable import DocumentModel
import PinxelTestSupport

struct DocumentModelCatalogTests {
    @Test func catalogIsComplete() throws {
        #expect(try CatalogValidation.problems(inCatalogAt: Catalogs.url(module: "DocumentModel")) == [])
    }

    @Test func commandNamesAreEnglishInTests() {
        // Under `swift test` the bundle language is English (verified): the names are the base language.
        #expect(CommandName.move == "Move")
        #expect(CommandName.bringToFront == "Bring to Front")
        #expect(CommandName.fitCanvas == "Fit Canvas")
    }

    @Test func italianTranslationExists() throws {
        let path = try #require(Bundle.module(for: "DocumentModel")?.path(forResource: "it", ofType: "lproj"))
        #expect(Bundle(path: path)?.localizedString(forKey: "Move", value: nil, table: nil) == "Sposta")
    }
}
