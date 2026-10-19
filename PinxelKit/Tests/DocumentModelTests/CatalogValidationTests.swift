import Foundation
import Testing
import PinxelTestSupport

struct CatalogValidationTests {
    func catalog(_ strings: String) -> Data {
        Data(#"{ "sourceLanguage" : "en", "version" : "1.0", "strings" : { \#(strings) } }"#.utf8)
    }

    func unit(_ value: String, state: String = "translated") -> String {
        #"{ "stringUnit" : { "state" : "\#(state)", "value" : "\#(value)" } }"#
    }

    @Test func completeCatalogHasNoProblems() throws {
        let data = catalog(#""Move" : { "localizations" : { "it" : \#(unit("Sposta")), "de" : \#(unit("Bewegen")), "fr" : \#(unit("Déplacer")) } }"#)
        #expect(try CatalogValidation.problems(inCatalog: data, languages: ["it", "de", "fr"]).isEmpty)
    }

    @Test func missingLanguageIsReported() throws {
        let data = catalog(#""Move" : { "localizations" : { "it" : \#(unit("Sposta")) } }"#)
        let problems = try CatalogValidation.problems(inCatalog: data, languages: ["it", "de", "fr"])
        #expect(problems == ["Move: missing de", "Move: missing fr"])
    }

    @Test func emptyOrUntranslatedValuesAreReported() throws {
        let data = catalog(#""Move" : { "localizations" : { "it" : \#(unit("")), "de" : \#(unit("Bewegen", state: "new")), "fr" : \#(unit("Déplacer")) } }"#)
        let problems = try CatalogValidation.problems(inCatalog: data, languages: ["it", "de", "fr"])
        #expect(problems == ["Move: empty it", "Move: de is new"])
    }

    @Test func placeholdersMatch() throws {
        let data = catalog(#""Objects: %lld" : { "localizations" : { "it" : \#(unit("Oggetti")), "de" : \#(unit("Objekte: %@")), "fr" : \#(unit("Objets : %lld")) } }"#)
        let problems = try CatalogValidation.problems(inCatalog: data, languages: ["it", "de", "fr"])
        #expect(problems == ["Objects: %lld: placeholders it [] ≠ [%lld]", "Objects: %lld: placeholders de [%@] ≠ [%lld]"])
    }

    @Test func positionalPlaceholdersMayBeReordered() throws {
        let data = catalog(#""%lld × %lld" : { "localizations" : { "it" : \#(unit("%2$lld × %1$lld")), "de" : \#(unit("%lld × %lld")), "fr" : \#(unit("%lld × %lld")) } }"#)
        #expect(try CatalogValidation.problems(inCatalog: data, languages: ["it", "de", "fr"]).isEmpty)
    }

    @Test func pluralVariationsAreChecked() throws {
        let plural = #"{ "variations" : { "plural" : { "one" : \#(unit("%lld oggetto")), "other" : \#(unit("%lld oggetti")) } } }"#
        let data = catalog(#""%lld objects" : { "localizations" : { "it" : \#(plural), "de" : \#(unit("%lld Objekte")), "fr" : \#(unit("%lld objets")) } }"#)
        #expect(try CatalogValidation.problems(inCatalog: data, languages: ["it", "de", "fr"]).isEmpty)
    }

    @Test func entriesMarkedDoNotTranslateAreSkipped() throws {
        let data = catalog(#""Pinxel" : { "shouldTranslate" : false }"#)
        #expect(try CatalogValidation.problems(inCatalog: data, languages: ["it", "de", "fr"]).isEmpty)
    }
}
