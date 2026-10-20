# Localization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pinxel shows every interface text in English, Italian, German or French, following the Mac's language, with English as the fallback.

**Architecture:** English becomes the source language of every user-visible string. The app target gets `Localizable.xcstrings` and `InfoPlist.xcstrings`. The PinxelKit modules that show text (`DocumentModel`, `EditorUI`, `AppCore`) get a catalog each and use `String(localized:bundle: .module)`. Command names live once in `DocumentModel.CommandName`. A small Python tool merges translation tables into catalogs and checks coverage against the keys Xcode extracts at build time; a Swift test checks every catalog is complete. The library folder becomes `Library` with a one-time move from `Libreria`.

**Tech Stack:** Swift 6, macOS 15+, SwiftUI + AppKit, Swift Testing, XCTest UI tests, XcodeGen, String Catalogs (`.xcstrings`), Python 3 (tooling only).

**Spec:** `docs/superpowers/specs/2026-10-20-pinxel-localization-design.md`

## Global Constraints

- Languages: English (base), Italian, German, French. The language follows the Mac; no selector in Pinxel. Fallback: English.
- Source strings in code are English; Italian, German and French are translations in String Catalogs.
- One catalog for the app (`App/Pinxel/Localizable.xcstrings`), one for Info.plist strings (`App/Pinxel/InfoPlist.xcstrings`), one per PinxelKit module that shows text.
- Library folder: `~/Pictures/Pinxel/Library` in every language, migrated from `Libreria`.
- Default file name template translated (`at` / `alle` / `um` / `à`); a customized template never changes; the old default (`'Pinxel' yyyy-MM-dd 'at' HH.mm.ss`) counts as not customized.
- `.pinxel` format (version 2), `library.json`, asset names, accessibility identifiers and log names do not change.
- Project docs (specs, plans, manual tests) stay in Italian; code comments stay in Italian like the surrounding code; commits in English with the Co-Authored-By trailer.
- German and French translations are written by the implementer and marked for review by a native speaker (in the manual checklist, not in the catalogs: catalog states are `translated`).
- Never mention other screenshot products in the repo (public).
- Package tests: `python3 /private/tmp/claude-501/-Users-giovanni-work-reatool/d2d00140-beb8-4428-98e4-cbbc64479070/scratchpad/pt.py [filter]` (prints `exit | tests | problems`). App build: `xcodebuild -project Pinxel.xcodeproj -scheme Pinxel -configuration Debug build`. After adding app files run `xcodegen generate`.
- Verified before planning: `.xcstrings` resources in a Swift package compile with `swift test`; under `swift test` the module bundle's preferred localization is `en`. Xcode builds with `SWIFT_EMIT_LOC_STRINGS=YES` write `*.stringsdata` (JSON: `tables` → `[ {key, comment} ]`) for app and package targets under `Build/Intermediates.noindex/`.

## Glossary (use these everywhere)

| English | Italiano | Deutsch | Français |
|---|---|---|---|
| Capture (noun) | Cattura | Aufnahme | Capture |
| Capture Area | Cattura area | Bereich aufnehmen | Capturer une zone |
| Capture Window | Cattura finestra | Fenster aufnehmen | Capturer une fenêtre |
| Capture Screen | Cattura schermo | Bildschirm aufnehmen | Capturer l'écran |
| Scrolling Capture | Cattura a scorrimento | Scrollende Aufnahme | Capture défilante |
| Repeat Last Area | Ripeti ultima area | Letzten Bereich wiederholen | Répéter la dernière zone |
| Editor | Editor | Editor | Éditeur |
| Canvas | Tela | Leinwand | Canevas |
| Library | Libreria | Mediathek | Bibliothèque |
| Strip (library) | Carosello | Leiste | Bandeau |
| Annotation | Annotazione | Anmerkung | Annotation |
| Select (tool) | Selezione | Auswahl | Sélection |
| Arrow | Freccia | Pfeil | Flèche |
| Line | Linea | Linie | Ligne |
| Shape | Forma | Form | Forme |
| Text | Testo | Text | Texte |
| Callout | Callout | Sprechblase | Bulle |
| Step | Step | Schritt | Étape |
| Pen | Penna | Stift | Stylo |
| Highlighter | Evidenziatore | Textmarker | Surligneur |
| Blur | Sfocatura | Weichzeichnen | Flou |
| Pixelate | Pixel | Verpixeln | Pixeliser |
| Magnifier | Lente | Lupe | Loupe |
| Crop | Ritaglio / Ritaglia | Zuschneiden | Recadrer |
| Cut Out | Taglia e ricuci | Ausschneiden und schließen | Couper et rapprocher |
| Resize | Ridimensiona | Größe ändern | Redimensionner |
| Move | Sposta | Bewegen | Déplacer |
| Rotate | Ruota | Drehen | Faire pivoter |
| Duplicate | Duplica | Duplizieren | Dupliquer |
| Delete | Elimina | Löschen | Supprimer |
| Lock / Unlock | Blocca / Sblocca | Sperren / Entsperren | Verrouiller / Déverrouiller |
| Bring to Front | Porta in primo piano | Nach vorne bringen | Mettre au premier plan |
| Bring Forward | Porta avanti | Eine Ebene nach vorne | Avancer |
| Send Backward | Porta indietro | Eine Ebene nach hinten | Reculer |
| Send to Back | Porta in fondo | Nach hinten stellen | Mettre à l'arrière-plan |
| Arrange (menu) | Disponi | Anordnen | Disposition |
| Paste | Incolla | Einsetzen | Coller |
| Paste Image | Incolla immagine | Bild einsetzen | Coller l'image |
| Insert Image | Inserisci immagine | Bild einfügen | Insérer une image |
| Border, Shadow and Padding | Bordo, ombra e margini | Rahmen, Schatten und Abstand | Bordure, ombre et marges |
| Fit Canvas | Adatta tela | Leinwand anpassen | Ajuster le canevas |
| Quick Style | Stile rapido | Schnellstil | Style rapide |
| Export | Esporta | Exportieren | Exporter |
| Settings | Impostazioni | Einstellungen | Réglages |
| Quick Preview | Anteprima veloce | Schnellvorschau | Aperçu rapide |
| Clipboard Only | Solo appunti | Nur Zwischenablage | Presse-papiers uniquement |
| Screen Recording | Registrazione schermo | Bildschirmaufnahme | Enregistrement de l'écran |
| Folder / Tag | Cartella / Etichetta | Ordner / Tag | Dossier / Étiquette |
| Pinxel Document | Documento Pinxel | Pinxel-Dokument | Document Pinxel |

Use macOS's own wording for standard menu items (Undo, Redo, Cut, Copy, Paste, Select All, Zoom In/Out, Actual Size, Close, Save, Revert…), whose standard translations are listed above where they matter.

## Review Focus

1. A Mac in a language Pinxel does not have (e.g. Spanish) must show English, not Italian and not keys. → Task 6 UI test `testUnsupportedLanguageFallsBackToEnglish`.
2. Interpolated strings (accessibility value, size badges, "Undo …") must keep their numbers and names in every language; a translation with a missing or extra `%lld`/`%@` would crash or garble. → Task 1 validator rule `placeholdersMatch`, enforced for every catalog.
3. The user's existing library must survive the rename even when `Library` already exists or the move fails. → Task 4 tests `migrationKeepsBothWhenLibraryExists`, `migrationFailureKeepsUsingLibreria`.
4. Strings shown in AppKit (alerts, notifications, context menu, `NSMenu` titles, accessibility) are not extracted by SwiftUI automatically; any left as a plain literal stays Italian. → Task 5 step "leftover Italian scan" and Task 1 `coverage` command.
5. UI tests must keep working on a Mac whose language is not Italian. → Task 6 launches every UI test with `-AppleLanguages (it)`.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `scripts/l10n/xcstrings.py` (new) | `merge` a TSV into a catalog; `coverage` compares build-extracted keys with catalogs |
| `PinxelKit/Tests/PinxelTestSupport/CatalogValidation.swift` (new) | Parses a catalog and lists problems (missing languages, empty values, placeholder mismatch) |
| `PinxelKit/Tests/PinxelTestSupport/CatalogValidationTests` → `PinxelKit/Tests/DocumentModelTests/CatalogValidationTests.swift` (new) | Validator rules on fixture catalogs |
| `PinxelKit/Tests/*/CatalogCompletenessTests.swift` (new, one per catalog module) | The module's real catalog has no problems |
| `PinxelKit/Package.swift` | `defaultLocalization: "en"`; catalog resources for `DocumentModel`, `EditorUI`, `AppCore` |
| `PinxelKit/Sources/DocumentModel/Localizable.xcstrings` (new) | Command names, operation names |
| `PinxelKit/Sources/DocumentModel/CommandName.swift` (new) | Every undo/redo command name, localized |
| `PinxelKit/Sources/EditorUI/Localizable.xcstrings` (new) | Tool titles, canvas texts, context menu, accessibility |
| `PinxelKit/Sources/AppCore/Localizable.xcstrings` (new) | Post-capture actions, hot key titles, key names, default file name template |
| `PinxelKit/Sources/AppCore/FileNamer.swift`, `CaptureSettings.swift` | Localized default template; legacy default treated as not customized |
| `PinxelKit/Sources/Library/LibraryStore.swift` | `Library` folder name and migration |
| `App/Pinxel/**/*.swift` | English source strings; `String(localized:)` for AppKit texts |
| `App/Pinxel/Localizable.xcstrings`, `App/Pinxel/InfoPlist.xcstrings` (new) | App translations |
| `project.yml` | `developmentLanguage: en`, `SWIFT_EMIT_LOC_STRINGS: YES`, new resources |
| `App/PinxelUITests/*.swift` | `-AppleLanguages (it)`; new `LocalizationUITests.swift` |
| `README.md`, `docs/manual-tests/localization.md` (new), spec status | Docs |

---

### Task 1: Catalog tooling and validation

**Files:**
- Create: `scripts/l10n/xcstrings.py`, `PinxelKit/Tests/PinxelTestSupport/CatalogValidation.swift`, `PinxelKit/Tests/DocumentModelTests/CatalogValidationTests.swift`
- Modify: `PinxelKit/Package.swift`, `project.yml`
- Create (empty catalogs): `PinxelKit/Sources/DocumentModel/Localizable.xcstrings`, `PinxelKit/Sources/EditorUI/Localizable.xcstrings`, `PinxelKit/Sources/AppCore/Localizable.xcstrings`

**Interfaces:**
- Produces: `public enum CatalogValidation { public static func problems(inCatalogAt url: URL, languages: [String] = ["it", "de", "fr"]) throws -> [String]; public static func problems(inCatalog data: Data, languages: [String]) throws -> [String] }`; `public enum Catalogs { public static func url(module: String, file: String = #filePath) -> URL }` (resolves `PinxelKit/Sources/<module>/Localizable.xcstrings` from a test file path).
- Produces: `scripts/l10n/xcstrings.py merge <catalog> <table.tsv>` and `scripts/l10n/xcstrings.py coverage <derivedData> <repoRoot>`.

- [ ] **Step 1: Write the failing validator tests** — `PinxelKit/Tests/DocumentModelTests/CatalogValidationTests.swift`:

```swift
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
```

- [ ] **Step 2: Run them to verify they fail**

Run: `python3 …/pt.py CatalogValidationTests`
Expected: compile error `cannot find 'CatalogValidation' in scope`.

- [ ] **Step 3: Write `CatalogValidation.swift`** in `PinxelKit/Tests/PinxelTestSupport/`:

```swift
import Foundation

/// Controlli sui String Catalog (`.xcstrings`): ogni testo tradotto in tutte le lingue, niente valori vuoti,
/// stessi segnaposto della lingua di base (l'ordine può cambiare con i segnaposto posizionali `%2$lld`).
public enum CatalogValidation {
    public static func problems(inCatalogAt url: URL, languages: [String] = ["it", "de", "fr"]) throws -> [String] {
        try problems(inCatalog: Data(contentsOf: url), languages: languages)
    }

    public static func problems(inCatalog data: Data, languages: [String]) throws -> [String] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let strings = root["strings"] as? [String: Any] else { return ["not a string catalog"] }
        var problems: [String] = []
        for key in strings.keys.sorted() {
            guard let entry = strings[key] as? [String: Any] else { continue }
            if entry["shouldTranslate"] as? Bool == false { continue }
            let source = placeholders(in: key)
            let localizations = entry["localizations"] as? [String: Any] ?? [:]
            for language in languages {
                guard let localization = localizations[language] as? [String: Any] else {
                    problems.append("\(key): missing \(language)")
                    continue
                }
                for unit in units(in: localization) {
                    let state = unit["state"] as? String ?? ""
                    let value = unit["value"] as? String ?? ""
                    if value.isEmpty {
                        problems.append("\(key): empty \(language)")
                    } else if state != "translated" {
                        problems.append("\(key): \(language) is \(state)")
                    } else if placeholders(in: value) != source {
                        problems.append("\(key): placeholders \(language) \(placeholders(in: value)) ≠ \(source)")
                    }
                }
            }
        }
        return problems
    }

    /// Le `stringUnit` di una localizzazione, anche dentro le varianti (plurali, dispositivi).
    private static func units(in node: [String: Any]) -> [[String: Any]] {
        var found: [[String: Any]] = []
        if let unit = node["stringUnit"] as? [String: Any] { found.append(unit) }
        if let variations = node["variations"] as? [String: Any] {
            for case let group as [String: Any] in variations.values {
                for case let child as [String: Any] in group.values { found += units(in: child) }
            }
        }
        return found
    }

    /// Segnaposto in ordine canonico: `%2$lld` conta come `%lld`; `%%` non è un segnaposto.
    static func placeholders(in text: String) -> [String] {
        let pattern = #"%(?:\d+\$)?(lld|ld|d|@|f|\.\d+f|s)"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let clean = text.replacingOccurrences(of: "%%", with: "")
        return regex.matches(in: clean, range: NSRange(clean.startIndex..., in: clean))
            .map { "%" + (clean as NSString).substring(with: $0.range(at: 1)) }
            .sorted()
    }
}

/// Percorso dei cataloghi dei moduli a partire dal file del test (i test non leggono il bundle: controllano il sorgente).
public enum Catalogs {
    public static func url(module: String, file: String = #filePath) -> URL {
        var url = URL(fileURLWithPath: file)
        while url.lastPathComponent != "Tests", url.path != "/" { url.deleteLastPathComponent() }
        return url.deletingLastPathComponent().appendingPathComponent("Sources/\(module)/Localizable.xcstrings")
    }
}
```

Note the sorted comparison: `placeholdersMatch` expects `[%lld]` for the key, `[]` for "Oggetti", `[%@]` for "Objekte: %@".

- [ ] **Step 4: Run the validator tests**

Run: `python3 …/pt.py CatalogValidationTests` → `exit 0 | tests 7`.

- [ ] **Step 5: Package and project setup**

`PinxelKit/Package.swift`: add `defaultLocalization: "en",` right after `name: "PinxelKit",`, and add `resources: [.process("Localizable.xcstrings")]` to the `DocumentModel`, `EditorUI` and `AppCore` targets (keep their existing parameters). Create each catalog with this exact content:

```json
{
  "sourceLanguage" : "en",
  "strings" : {

  },
  "version" : "1.0"
}
```

`project.yml`: under `options:` add `developmentLanguage: en`; under the `Pinxel` target's `settings.base` add `SWIFT_EMIT_LOC_STRINGS: YES` and `LOCALIZATION_PREFERS_STRING_CATALOGS: YES`.

- [ ] **Step 6: Write `scripts/l10n/xcstrings.py`**

```python
#!/usr/bin/env python3
"""String Catalog tools for Pinxel.

merge <catalog.xcstrings> <table.tsv>
    TSV columns: key, it, de, fr, comment (optional). Adds or replaces those
    entries (state "translated"); other entries are kept. Keys are the English
    source strings exactly as written in code (interpolations as %lld / %@).

coverage <derivedDataPath> <repoRoot>
    Reads the *.stringsdata files written by an Xcode build with
    SWIFT_EMIT_LOC_STRINGS=YES and reports, per catalog, keys used in code but
    missing from the catalog and catalog keys no longer used. Exit 1 if any key
    is missing.
"""
import csv
import glob
import json
import os
import sys

LANGS = ["it", "de", "fr"]
CATALOGS = {
    "Pinxel.build": ("App/Pinxel/Localizable.xcstrings", "Localizable"),
    "DocumentModel": ("PinxelKit/Sources/DocumentModel/Localizable.xcstrings", "Localizable"),
    "EditorUI": ("PinxelKit/Sources/EditorUI/Localizable.xcstrings", "Localizable"),
    "AppCore": ("PinxelKit/Sources/AppCore/Localizable.xcstrings", "Localizable"),
}


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def save(path, catalog):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(catalog, f, ensure_ascii=False, indent=2, sort_keys=True, separators=(",", " : "))
        f.write("\n")


def merge(catalog_path, table_path):
    catalog = load(catalog_path)
    strings = catalog.setdefault("strings", {})
    with open(table_path, encoding="utf-8") as f:
        for row in csv.reader(f, delimiter="\t"):
            if not row or row[0].startswith("#"):
                continue
            key, values, comment = row[0], row[1:4], (row[4] if len(row) > 4 else "")
            if len(values) != 3 or not all(values):
                sys.exit(f"incomplete row for {key!r}")
            entry = {"localizations": {lang: {"stringUnit": {"state": "translated", "value": value}}
                                       for lang, value in zip(LANGS, values)}}
            if comment:
                entry["comment"] = comment
            strings[key] = entry
    save(catalog_path, catalog)


def coverage(derived, root):
    used = {name: set() for name in CATALOGS}
    for path in glob.glob(os.path.join(derived, "Build/Intermediates.noindex/**/*.stringsdata"), recursive=True):
        owner = next((name for name in CATALOGS if f"/{name}/" in path or f"/{name}-" in path), None)
        if owner is None:
            continue
        table = CATALOGS[owner][1]
        for entry in load(path).get("tables", {}).get(table, []):
            used[owner].add(entry["key"])
    missing_any = False
    for name, (catalog_path, _) in CATALOGS.items():
        keys = set(load(os.path.join(root, catalog_path)).get("strings", {}))
        missing, unused = sorted(used[name] - keys), sorted(keys - used[name])
        print(f"{name}: {len(used[name])} used, {len(missing)} missing, {len(unused)} unused")
        for key in missing:
            print(f"  missing: {key}")
        for key in unused:
            print(f"  unused:  {key}")
        missing_any = missing_any or bool(missing)
    sys.exit(1 if missing_any else 0)


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "merge":
        merge(sys.argv[2], sys.argv[3])
    elif len(sys.argv) == 4 and sys.argv[1] == "coverage":
        coverage(sys.argv[2], sys.argv[3])
    else:
        sys.exit(__doc__)
```

Check the owner matching on a real build path before relying on it: package object files live under `PinxelKit.build/Debug/EditorUI-t.build/…`, so the match is `"/EditorUI-"`; app files under `Pinxel.build/…`.

- [ ] **Step 7: Verify the tooling end to end**

Run: `xcodegen generate && xcodebuild -project Pinxel.xcodeproj -scheme Pinxel -configuration Debug -derivedDataPath build/l10n SWIFT_EMIT_LOC_STRINGS=YES build 2>&1 | tail -1` → `** BUILD SUCCEEDED **`.
Run: `python3 scripts/l10n/xcstrings.py coverage build/l10n .`
Expected: `Pinxel.build: N used, N missing` with N ≈ 200 (the Italian SwiftUI literals; all missing for now), `0 used` for the three modules, exit 1. This is the baseline Tasks 2–5 drive to zero.
Run: `python3 …/pt.py` → `exit 0`.

- [ ] **Step 8: Commit**

```bash
git add scripts/l10n PinxelKit/Package.swift PinxelKit/Sources/*/Localizable.xcstrings PinxelKit/Tests project.yml
git commit -m "build(l10n): string catalogs, catalog validation and coverage tooling" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: DocumentModel — command names

**Files:**
- Create: `PinxelKit/Sources/DocumentModel/CommandName.swift`, `PinxelKit/Tests/DocumentModelTests/CatalogCompletenessTests.swift`
- Modify: `PinxelKit/Sources/DocumentModel/EditCommand.swift`, `ImageOperation.swift`, `PinxelKit/Sources/DocumentModel/Localizable.xcstrings`, tests comparing Italian names (`EditCommandTests`, `DocumentTests`)

**Interfaces:**
- Consumes: `CatalogValidation`, `Catalogs` (Task 1).
- Produces: `public enum CommandName` with static `String` properties listed below. Every command name in the codebase (DocumentModel, EditorUI, App) comes from here.

- [ ] **Step 1: Failing tests** — `PinxelKit/Tests/DocumentModelTests/CatalogCompletenessTests.swift`:

```swift
import Foundation
import Testing
@testable import DocumentModel
import PinxelTestSupport

struct DocumentModelCatalogTests {
    @Test func catalogIsComplete() throws {
        #expect(try CatalogValidation.problems(inCatalogAt: Catalogs.url(module: "DocumentModel")) == [])
    }

    @Test func commandNamesAreEnglishInTests() {
        // Sotto `swift test` la lingua del bundle è l'inglese (verificato): i nomi sono la lingua di base.
        #expect(CommandName.move == "Move")
        #expect(CommandName.bringToFront == "Bring to Front")
        #expect(CommandName.fitCanvas == "Fit Canvas")
    }

    @Test func italianTranslationExists() throws {
        let path = try #require(Bundle.module(for: "DocumentModel")?.path(forResource: "it", ofType: "lproj"))
        #expect(Bundle(path: path)?.localizedString(forKey: "Move", value: nil, table: nil) == "Sposta")
    }
}
```

and add to `PinxelTestSupport/CatalogValidation.swift`:

```swift
extension Bundle {
    /// Il bundle delle risorse di un modulo di PinxelKit (`PinxelKit_<Modulo>.bundle`), cercato accanto ai test.
    public static func module(for module: String) -> Bundle? {
        let name = "PinxelKit_\(module).bundle"
        let candidates = [Bundle.main.bundleURL, Bundle.main.bundleURL.deletingLastPathComponent()]
            + Bundle.allBundles.map { $0.bundleURL.deletingLastPathComponent() }
        return candidates.lazy.map { $0.appendingPathComponent(name) }.compactMap { Bundle(url: $0) }.first
    }
}
```

Replace in `EditCommandTests` and `DocumentTests` every Italian name literal by the `CommandName` constant (e.g. `#expect(op.name == "Estendi tela")` → `#expect(op.name == CommandName.extendCanvas)`; `SetAnnotations(name: "Ritaglia", …)` → `SetAnnotations(name: CommandName.crop, …)`; `"Sposta"`/`"Incolla"` likewise).

- [ ] **Step 2: Run to verify failure**

Run: `python3 …/pt.py DocumentModelCatalogTests` → compile error `cannot find 'CommandName'`.

- [ ] **Step 3: `CommandName.swift`**

```swift
import Foundation

/// Nomi dei comandi mostrati in "Annulla …"/"Ripeti …", tradotti. Ogni comando del codice prende il nome da qui,
/// così un nome è scritto (e tradotto) in un punto solo.
public enum CommandName {
    private static func text(_ key: String.LocalizationValue, _ comment: StaticString) -> String {
        String(localized: key, bundle: .module, comment: comment)
    }

    public static var add: String { text("Add", "Undo: generic add") }
    public static var addText: String { text("Add Text", "Undo: new text annotation") }
    public static var addCallout: String { text("Add Callout", "Undo: new callout") }
    public static var delete: String { text("Delete", "Undo: delete objects") }
    public static var edit: String { text("Edit", "Undo: generic change") }
    public static var editText: String { text("Edit Text", "Undo: text edited on the canvas") }
    public static var deleteText: String { text("Delete Text", "Undo: text emptied and removed") }
    public static var arrange: String { text("Arrange", "Undo: generic reorder") }
    public static var bringToFront: String { text("Bring to Front", "Undo and menu") }
    public static var bringForward: String { text("Bring Forward", "Undo and menu") }
    public static var sendBackward: String { text("Send Backward", "Undo and menu") }
    public static var sendToBack: String { text("Send to Back", "Undo and menu") }
    public static var move: String { text("Move", "Undo: objects moved") }
    public static var resize: String { text("Resize", "Undo: object or image resized") }
    public static var rotate: String { text("Rotate", "Undo: object rotated") }
    public static var duplicate: String { text("Duplicate", "Undo and menu") }
    public static var lock: String { text("Lock", "Undo and menu") }
    public static var unlock: String { text("Unlock", "Undo and menu") }
    public static var cut: String { text("Cut", "Undo: objects cut to the clipboard") }
    public static var paste: String { text("Paste", "Undo: objects pasted") }
    public static var pasteImage: String { text("Paste Image", "Undo: image pasted") }
    public static var insertImage: String { text("Insert Image", "Undo: image dropped or inserted") }
    public static var crop: String { text("Crop", "Undo: crop") }
    public static var cutOut: String { text("Cut Out", "Undo: remove a band and close the gap") }
    public static var extendCanvas: String { text("Extend Canvas", "Version 1 files only") }
    public static var fitCanvas: String { text("Fit Canvas", "Undo: canvas fitted to the content") }
    public static var canvasStyle: String { text("Canvas Style", "Undo: border, shadow and padding") }
    public static var style: String { text("Style", "Undo: color, width, opacity…") }
    public static var quickStyle: String { text("Quick Style", "Undo: quick style applied") }
    public static var fill: String { text("Fill", "Undo: fill toggled") }
    public static var effect: String { text("Effect", "Undo: blur ↔ pixelate") }
    public static var arrowHeads: String { text("Arrowheads", "Undo: arrow heads changed") }
    public static var shape: String { text("Shape", "Undo: rectangle/ellipse") }
    public static var magnifierShape: String { text("Magnifier Shape", "Undo") }
    public static var connector: String { text("Connector", "Undo: magnifier connector line") }
    public static var magnification: String { text("Magnification", "Undo: magnifier zoom") }
    public static var intensity: String { text("Intensity", "Undo: blur radius / pixel size") }
    public static var sequence: String { text("Sequence", "Undo: step numbering style") }
    public static var font: String { text("Font", "Undo: text font family") }
    public static var textSize: String { text("Text Size", "Undo") }
    public static var textColor: String { text("Text Color", "Undo") }
    public static var alignment: String { text("Alignment", "Undo: text alignment") }
    public static var bold: String { text("Bold", "Undo") }
    public static var italic: String { text("Italic", "Undo") }
    public static var underline: String { text("Underline", "Undo") }
}
```

Translations for these keys (TSV for `scripts/l10n/xcstrings.py merge`; key, it, de, fr):

```
Add	Aggiungi	Hinzufügen	Ajouter
Add Text	Aggiungi testo	Text hinzufügen	Ajouter du texte
Add Callout	Aggiungi callout	Sprechblase hinzufügen	Ajouter une bulle
Delete	Elimina	Löschen	Supprimer
Edit	Modifica	Bearbeiten	Modifier
Edit Text	Modifica testo	Text bearbeiten	Modifier le texte
Delete Text	Elimina testo	Text löschen	Supprimer le texte
Arrange	Disponi	Anordnen	Disposer
Bring to Front	Porta in primo piano	Nach vorne bringen	Mettre au premier plan
Bring Forward	Porta avanti	Eine Ebene nach vorne	Avancer
Send Backward	Porta indietro	Eine Ebene nach hinten	Reculer
Send to Back	Porta in fondo	Nach hinten stellen	Mettre à l'arrière-plan
Move	Sposta	Bewegen	Déplacer
Resize	Ridimensiona	Größe ändern	Redimensionner
Rotate	Ruota	Drehen	Faire pivoter
Duplicate	Duplica	Duplizieren	Dupliquer
Lock	Blocca	Sperren	Verrouiller
Unlock	Sblocca	Entsperren	Déverrouiller
Cut	Taglia	Ausschneiden	Couper
Paste	Incolla	Einsetzen	Coller
Paste Image	Incolla immagine	Bild einsetzen	Coller l'image
Insert Image	Inserisci immagine	Bild einfügen	Insérer une image
Crop	Ritaglia	Zuschneiden	Recadrer
Cut Out	Taglia e ricuci	Ausschneiden und schließen	Couper et rapprocher
Extend Canvas	Estendi tela	Leinwand erweitern	Agrandir le canevas
Fit Canvas	Adatta tela	Leinwand anpassen	Ajuster le canevas
Canvas Style	Stile tela	Leinwandstil	Style du canevas
Style	Stile	Stil	Style
Quick Style	Stile rapido	Schnellstil	Style rapide
Fill	Riempimento	Füllung	Remplissage
Effect	Effetto	Effekt	Effet
Arrowheads	Punte	Pfeilspitzen	Pointes
Shape	Forma	Form	Forme
Magnifier Shape	Forma lente	Lupenform	Forme de la loupe
Connector	Connettore	Verbindungslinie	Connecteur
Magnification	Ingrandimento	Vergrößerung	Grossissement
Intensity	Intensità	Stärke	Intensité
Sequence	Sequenza	Folge	Séquence
Font	Carattere	Schrift	Police
Text Size	Dimensione testo	Textgröße	Taille du texte
Text Color	Colore testo	Textfarbe	Couleur du texte
Alignment	Allineamento	Ausrichtung	Alignement
Bold	Grassetto	Fett	Gras
Italic	Corsivo	Kursiv	Italique
Underline	Sottolineato	Unterstrichen	Souligné
```

Save it as `scratchpad/l10n/document-model.tsv` (tab-separated) and run `python3 scripts/l10n/xcstrings.py merge PinxelKit/Sources/DocumentModel/Localizable.xcstrings <that file>`.

- [ ] **Step 4: Use the names in DocumentModel**

In `EditCommand.swift` replace the default/literal names: `AddAnnotations(…, name: String = CommandName.add)`, `DeleteAnnotations(…, name: String = CommandName.delete)`, `UpdateAnnotations(name: String = CommandName.edit, …)`, `ReorderAnnotations(name: String = CommandName.arrange, …)` and the four helpers (`CommandName.bringToFront`, `.sendToBack`, `.bringForward`, `.sendBackward`), `UpdateCanvasStyle(…, name: String = CommandName.canvasStyle)`, `FitCanvas.name = CommandName.fitCanvas` (`public let name = CommandName.fitCanvas`). In `ImageOperation.name`: `.crop: CommandName.crop`, `.resize: CommandName.resize`, `.cutOut: CommandName.cutOut`, `.extend: CommandName.extendCanvas`.

- [ ] **Step 5: Run**

Run: `python3 …/pt.py DocumentModelTests` → `exit 0`. If `italianTranslationExists` cannot find the bundle, print `Bundle.allBundles.map(\.bundleURL)` in the test once to locate `PinxelKit_DocumentModel.bundle` and fix `Bundle.module(for:)`; do not delete the test.

- [ ] **Step 6: Full suite and commit**

Run: `python3 …/pt.py` → `exit 0`. EditorUI tests that compare Italian names still pass for now only if they don't reach DocumentModel defaults; any failure there is fixed in this task by switching the test to `CommandName`.

```bash
git add PinxelKit/Sources/DocumentModel PinxelKit/Tests
git commit -m "feat(l10n): command names come from a translated catalog" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: EditorUI

**Files:**
- Modify: `PinxelKit/Sources/EditorUI/EditorTool.swift`, `CanvasView.swift`, `ToolController.swift`, `TextEditing.swift`, `EditorModel.swift`, `EditorSession.swift`, `AnnotationEditing.swift`, `ContentEditing.swift`, `EditorMenuState.swift`, `Localizable.xcstrings`
- Create: `PinxelKit/Tests/EditorUITests/EditorUICatalogTests.swift`
- Modify tests comparing Italian text: `ContextMenuTests`, `SelectToolTests`, `EditorModelTests`, `SessionFitTests`, `PasteImageTests`, `CanvasViewTests`, `CanvasShiftTests`, `ImageEditingTests`

**Interfaces:**
- Consumes: `CommandName` (Task 2).
- Produces: `EditorTool.title` (localized), `EditorTool.addCommandName: String`, `EditorMenuState.undoTitle`/`redoTitle` built with `UndoManager.undoMenuTitle(forUndoActionName:)`.

- [ ] **Step 1: Failing tests** — `EditorUICatalogTests.swift`:

```swift
import AppKit
import Testing
@testable import EditorUI
import PinxelTestSupport

@MainActor
struct EditorUICatalogTests {
    @Test func catalogIsComplete() throws {
        #expect(try CatalogValidation.problems(inCatalogAt: Catalogs.url(module: "EditorUI")) == [])
    }

    @Test func toolTitlesAreEnglishInTests() {
        #expect(EditorTool.cutOut.title == "Cut Out")
        #expect(EditorTool.arrow.addCommandName == "Add Arrow")
    }

    @Test func undoTitleUsesTheSystemFormat() {
        var state = EditorMenuState()
        state.hasEditor = true
        state.undoActionName = CommandName.move
        #expect(state.undoTitle == UndoManager().undoMenuTitle(forUndoActionName: CommandName.move))
    }
}
```

(`CommandName` needs `import DocumentModel`.) In the listed test files replace Italian literals by the source: context-menu titles → `CommandName.bringToFront` etc. and `CommandName.delete`; `undoActionName == "Sposta"` → `CommandName.move`; `"Ritaglia"` → `CommandName.crop`; `"Duplica"` → `CommandName.duplicate`; `"Ridimensiona"` → `CommandName.resize`; `"Ruota"` → `CommandName.rotate`; `"Taglia e ricuci"` → `CommandName.cutOut`; `"Incolla immagine"` → `CommandName.pasteImage`; `"Sblocca"`/`"Blocca"` → `CommandName.unlock`/`.lock`; `"Elimina"` → `CommandName.delete`.

- [ ] **Step 2: Run to verify failure**

Run: `python3 …/pt.py EditorUICatalogTests` → `addCommandName` not found / titles still Italian.

- [ ] **Step 3: Implement**

- `EditorTool.title`: `String(localized: "Select", bundle: .module, comment: "Tool")` … for each tool: Select, Arrow, Line, Shape, Text, Callout, Step, Pen, Highlighter, Blur, Magnifier, Crop, Cut Out.
- `EditorTool.addCommandName`: per tool, `String(localized: "Add Arrow", bundle: .module, comment: "Undo: new object")` (Add Arrow, Add Line, Add Shape, Add Text, Add Callout, Add Step, Add Pen Stroke, Add Highlight, Add Blur, Add Magnifier; `.select`, `.crop`, `.cutOut` return `CommandName.add`). `ToolController` uses it instead of `"Aggiungi \(tool.title.lowercased())"`.
- Every command name literal in the files listed → `CommandName.…` (Duplica → `.duplicate`, Taglia → `.cut`, Incolla → `.paste`, Incolla immagine → `.pasteImage`, Inserisci immagine → `.insertImage`, Ritaglia → `.crop`, Taglia e ricuci → `.cutOut`, Sposta → `.move`, Blocca/Sblocca → `.lock`/`.unlock`, Stile → `.style`, Stile rapido → `.quickStyle`, Riempimento → `.fill`, Effetto → `.effect`, Aggiungi callout → `.addCallout`, Aggiungi testo → `.addText`, Modifica testo → `.editText`, Elimina testo → `.deleteText`, Ridimensiona → `.resize`, Ruota → `.rotate`).
- `CanvasView`:
  - accessibility label `String(localized: "Canvas", bundle: .module)`;
  - accessibility value `String(localized: "Annotations: \(count), selected: \(selected), image: \(width)×\(height)", bundle: .module, comment: "Canvas accessibility value")`; the catalog key is `Annotations: %lld, selected: %lld, image: %lld×%lld` and the Italian translation must be exactly `Annotazioni: %lld, selezionate: %lld, immagine: %lld×%lld` (UI tests read it);
  - render failure message `String(localized: "The document's image can't be shown.", bundle: .module)`;
  - empty hint `String(localized: "Paste a screenshot with ⌘V", bundle: .module)`;
  - context menu: `NSMenu(title: CommandName.arrange)` and items `CommandName.bringToFront` … `CommandName.delete`;
  - size badges: keep the numbers, `"\(w) × \(h)"` needs no translation; `"− \(n) px"` stays (unit symbol).
- `EditorMenuState`: `undoTitle`/`redoTitle` → `UndoManager().undoMenuTitle(forUndoActionName:)` / `redoMenuTitle(forUndoActionName:)` when an editor is key and not editing text and the name is non-empty; otherwise `String(localized: "Undo", bundle: .module)` / `"Redo"`. Remove the lowercasing helper.
- Default text font family `"Helvetica"` stays (font name, not text).

Then merge the translations. Keys and translations for this module:

```
Canvas	Tela	Leinwand	Canevas
Annotations: %lld, selected: %lld, image: %lld×%lld	Annotazioni: %lld, selezionate: %lld, immagine: %lld×%lld	Anmerkungen: %lld, ausgewählt: %lld, Bild: %lld×%lld	Annotations : %lld, sélectionnées : %lld, image : %lld×%lld
The document's image can't be shown.	Impossibile mostrare l'immagine del documento.	Das Bild des Dokuments kann nicht angezeigt werden.	Impossible d'afficher l'image du document.
Paste a screenshot with ⌘V	Incolla uno screenshot con ⌘V	Bildschirmfoto mit ⌘V einsetzen	Collez une capture d'écran avec ⌘V
Undo	Annulla	Widerrufen	Annuler
Redo	Ripristina	Wiederholen	Rétablir
Select	Selezione	Auswahl	Sélection
Arrow	Freccia	Pfeil	Flèche
Line	Linea	Linie	Ligne
Shape	Forma	Form	Forme
Text	Testo	Text	Texte
Callout	Callout	Sprechblase	Bulle
Step	Step	Schritt	Étape
Pen	Penna	Stift	Stylo
Highlighter	Evidenziatore	Textmarker	Surligneur
Blur	Sfocatura	Weichzeichnen	Flou
Magnifier	Lente	Lupe	Loupe
Crop	Ritaglio	Zuschneiden	Recadrer
Cut Out	Taglia e ricuci	Ausschneiden und schließen	Couper et rapprocher
Add Arrow	Aggiungi freccia	Pfeil hinzufügen	Ajouter une flèche
Add Line	Aggiungi linea	Linie hinzufügen	Ajouter une ligne
Add Shape	Aggiungi forma	Form hinzufügen	Ajouter une forme
Add Text	Aggiungi testo	Text hinzufügen	Ajouter du texte
Add Callout	Aggiungi callout	Sprechblase hinzufügen	Ajouter une bulle
Add Step	Aggiungi step	Schritt hinzufügen	Ajouter une étape
Add Pen Stroke	Aggiungi tratto di penna	Stiftstrich hinzufügen	Ajouter un trait de stylo
Add Highlight	Aggiungi evidenziazione	Markierung hinzufügen	Ajouter un surlignage
Add Blur	Aggiungi sfocatura	Weichzeichnung hinzufügen	Ajouter un flou
Add Magnifier	Aggiungi lente	Lupe hinzufügen	Ajouter une loupe
```

Any other literal you find in EditorUI while converting gets a row in the same table before merging.

- [ ] **Step 4: Run**

Run: `python3 …/pt.py EditorUITests` → `exit 0`.

- [ ] **Step 5: Coverage for the modules**

Run the Task 1 build and `python3 scripts/l10n/xcstrings.py coverage build/l10n .` → `DocumentModel` and `EditorUI`: `0 missing`. A key reported as `unused` that you did use means the owner matching in the script is wrong: fix the script.

- [ ] **Step 6: Full suite and commit**

Run: `python3 …/pt.py` → `exit 0`.

```bash
git add PinxelKit/Sources/EditorUI PinxelKit/Tests
git commit -m "feat(l10n): editor tools, canvas and context menu in four languages" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: AppCore and the library folder

**Files:**
- Modify: `PinxelKit/Sources/AppCore/CaptureSettings.swift`, `KeyCombo.swift`, `FileNamer.swift`, `Localizable.xcstrings`; `PinxelKit/Sources/Library/LibraryStore.swift`; `App/Pinxel/AppEnvironment.swift`
- Create: `PinxelKit/Tests/AppCoreTests/AppCoreCatalogTests.swift`, `PinxelKit/Tests/LibraryTests/LibraryMigrationTests.swift`
- Modify tests using `FileNamer.defaultTemplate` or Italian titles (`grep -rn "Anteprima veloce\|Solo appunti\|Cattura area\|Spazio\|defaultTemplate" PinxelKit/Tests`)

**Interfaces:**
- Produces: `FileNamer.defaultTemplate: String` (computed, localized), `FileNamer.legacyDefaultTemplate = "'Pinxel' yyyy-MM-dd 'at' HH.mm.ss"`, `FileNamer.defaultTemplate(for language: String) -> String`; `CaptureSettings.effectiveFileNameTemplate: String`; `LibraryStore.defaultFolderName = "Library"`, `LibraryStore.legacyFolderName = "Libreria"`, `LibraryStore.prepareFolder(in parent: URL, fileManager: FileManager = .default) -> URL`.

- [ ] **Step 1: Failing tests**

`AppCoreCatalogTests.swift`:

```swift
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
```

(Check the actual name of `KeyCombo`'s display property — `grep -n "var .*: String" PinxelKit/Sources/AppCore/KeyCombo.swift` — and use it.)

`LibraryMigrationTests.swift`:

```swift
import Foundation
import Testing
@testable import Library

struct LibraryMigrationTests {
    func parent() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pinxel-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func legacyFolderIsRenamedWithItsFiles() throws {
        let root = try parent()
        defer { try? FileManager.default.removeItem(at: root) }
        let legacy = root.appendingPathComponent("Libreria")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: legacy.appendingPathComponent("library.json"))
        let folder = LibraryStore.prepareFolder(in: root)
        #expect(folder.lastPathComponent == "Library")
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("library.json").path))
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
    }

    @Test func migrationKeepsBothWhenLibraryExists() throws {
        let root = try parent()
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["Libreria", "Library"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        #expect(LibraryStore.prepareFolder(in: root).lastPathComponent == "Library")
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("Libreria").path))
    }

    @Test func noFolderGivesLibrary() throws {
        let root = try parent()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(LibraryStore.prepareFolder(in: root).lastPathComponent == "Library")
    }

    @Test func migrationFailureKeepsUsingLibreria() throws {
        let root = try parent()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Libreria"), withIntermediateDirectories: true)
        // Cartella genitore in sola lettura: lo spostamento non riesce.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)
        #expect(LibraryStore.prepareFolder(in: root).lastPathComponent == "Libreria")
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `python3 …/pt.py "AppCoreCatalogTests|LibraryMigrationTests"` → compile errors.

- [ ] **Step 3: Implement**

`FileNamer.swift`:

```swift
    /// Il predefinito delle versioni precedenti: chi lo ha ancora nelle impostazioni non l'ha personalizzato.
    public static let legacyDefaultTemplate = "'Pinxel' yyyy-MM-dd 'at' HH.mm.ss"

    /// Modello `DateFormatter` predefinito nella lingua dell'app: il testo fisso va tra apici.
    public static var defaultTemplate: String {
        String(localized: "'Pinxel' yyyy-MM-dd 'at' HH.mm.ss", bundle: .module, comment: "Default file name: keep the quotes around fixed text")
    }

    /// Il predefinito in una lingua precisa (per i test e per le impostazioni).
    public static func defaultTemplate(for language: String) -> String {
        guard let path = Bundle.module.path(forResource: language, ofType: "lproj"), let bundle = Bundle(path: path) else {
            return legacyDefaultTemplate
        }
        return bundle.localizedString(forKey: legacyDefaultTemplate, value: legacyDefaultTemplate, table: nil)
    }
```

`CaptureSettings.swift`: keep `fileNameTemplate` stored as is; add

```swift
    /// Il modello da usare: quello salvato, oppure il predefinito nella lingua attuale se è ancora il vecchio predefinito.
    public var effectiveFileNameTemplate: String {
        fileNameTemplate == FileNamer.legacyDefaultTemplate ? FileNamer.defaultTemplate : fileNameTemplate
    }
```

and replace every reader of `settings.fileNameTemplate` that builds a name (`grep -rn "fileNameTemplate" App PinxelKit/Sources`) with `effectiveFileNameTemplate`. The Settings text field keeps editing `fileNameTemplate` directly; when it shows the legacy default, display `FileNamer.defaultTemplate` instead (in the SwiftUI binding's getter) so the user sees their language.

`PostCaptureAction.title`, `HotKeyAction.title`: `String(localized: "Open Editor", bundle: .module)`, "Quick Preview", "Clipboard Only"; "Capture Area", "Capture Window", "Capture Screen", "Scrolling Capture", "Repeat Last Area". `KeyCombo.keyNames[0x31]`: the display uses `String(localized: "Space", bundle: .module, comment: "Space bar in a shortcut")`; the one-character names stay.

`LibraryStore.swift`:

```swift
    public static let defaultFolderName = "Library"
    public static let legacyFolderName = "Libreria"

    public static var defaultFolder: URL {
        prepareFolder(in: FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pinxel", isDirectory: true))
    }

    /// La cartella dell'archivio dentro `parent`: `Library`, ricavata spostando `Libreria` la prima volta.
    /// Se lo spostamento non riesce si continua con `Libreria` (niente si perde, si riprova al prossimo avvio).
    public static func prepareFolder(in parent: URL, fileManager: FileManager = .default) -> URL {
        let folder = parent.appendingPathComponent(defaultFolderName, isDirectory: true)
        let legacy = parent.appendingPathComponent(legacyFolderName, isDirectory: true)
        guard fileManager.fileExists(atPath: legacy.path), !fileManager.fileExists(atPath: folder.path) else { return folder }
        do {
            try fileManager.moveItem(at: legacy, to: folder)
            return folder
        } catch {
            logger.notice("Libreria non spostata in Library: \(error.localizedDescription, privacy: .public)")
            return legacy
        }
    }
```

with `private static let logger = Logger(subsystem: "com.degiorgi.pinxel", category: "library")` (`import OSLog`; reuse an existing logger if the file has one). `AppEnvironment` keeps calling `LibraryStore.defaultFolder` (the UI-test path does not).

Translations:

```
'Pinxel' yyyy-MM-dd 'at' HH.mm.ss	'Pinxel' yyyy-MM-dd 'alle' HH.mm.ss	'Pinxel' yyyy-MM-dd 'um' HH.mm.ss	'Pinxel' yyyy-MM-dd 'à' HH.mm.ss
Open Editor	Apri l'editor	Editor öffnen	Ouvrir l'éditeur
Quick Preview	Anteprima veloce	Schnellvorschau	Aperçu rapide
Clipboard Only	Solo appunti	Nur Zwischenablage	Presse-papiers uniquement
Capture Area	Cattura area	Bereich aufnehmen	Capturer une zone
Capture Window	Cattura finestra	Fenster aufnehmen	Capturer une fenêtre
Capture Screen	Cattura schermo	Bildschirm aufnehmen	Capturer l'écran
Scrolling Capture	Cattura a scorrimento	Scrollende Aufnahme	Capture défilante
Repeat Last Area	Ripeti ultima area	Letzten Bereich wiederholen	Répéter la dernière zone
Space	Spazio	Leertaste	Espace
```

- [ ] **Step 4: Run**

Run: `python3 …/pt.py "AppCoreTests|LibraryTests"` → `exit 0`.

- [ ] **Step 5: Full suite and commit**

Run: `python3 …/pt.py` → `exit 0`.

```bash
git add PinxelKit App/Pinxel/AppEnvironment.swift
git commit -m "feat(l10n): capture settings in four languages and the library folder becomes Library" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: The app

**Files:**
- Modify: every Swift file under `App/Pinxel/` with user-visible text (inventory, by count: `EditorCommands`, `Editor/InspectorView`, `Library/LibraryStrip`, `Editor/ImageSheets`, `Editor/TextSection`, `Capture/CaptureCoordinator`, `Settings/SettingsView`, `Editor/ZoomControls`, `Editor/EditorView`, `PostCapture/Notifier`, `Document/PinxelFileDocument`, `AppEnvironment`, `Editor/MagnifierSection`, `Library/LibraryModel`, `Editor/ImageToolSections`, `Capture/ScrollCapturePanel`, `Capture/PermissionWindow`, `MenuContent`, `Editor/ExportPanel`, `Editor/CaptureDragHandle`, `Document/PinxelDocumentController`, `AppDelegate`, `Library/LibraryOpener`, `Editor/QuickStylesSection`, `Editor/EditorWindowController`, `PostCapture/QuickPreview`, `Library/LibraryThumbnailView`, `Capture/SelectionView`, `PostCapture/PostCaptureActions`, `Editor/SharedCapture`, `Document/RecoveryAttempter`, `Capture/OverlayController`)
- Create: `App/Pinxel/Localizable.xcstrings`, `App/Pinxel/InfoPlist.xcstrings`
- Modify: `project.yml` (`CFBundleTypeName`/`UTTypeDescription` in English)

**Interfaces:**
- Consumes: `CommandName` (names passed to `model.update(name:…)`, `updateText(name:…)`), `EditorTool.title`, `PostCaptureAction.title`, `HotKeyAction.title`.

- [ ] **Step 1: Convert the strings, file by file**

Rules:
1. SwiftUI initializers that take a `LocalizedStringKey` (`Text("…")`, `Button("…")`, `Label("…", systemImage:)`, `Toggle("…")`, `Picker("…")`, `Section("…")`, `CommandMenu("…")`, `Menu("…")`, `.help("…")`, `TextField("…")`, `LabeledContent("…")`, `Stepper("…")`): rewrite the literal in English. Interpolations stay (`Text("\(count) captures")`).
2. `String` values shown anywhere (`NSAlert.messageText`, `informativeText`, button titles, `UNMutableNotificationContent.title/body`, `NSMenuItem(title:)`, `window.title`, `setAccessibilityLabel`, `.help(variable)`, errors' `localizedDescription` you build): `String(localized: "…", comment: "…")`.
3. SwiftUI views fed a `String` variable (`Button(state.undoTitle)`, `Text(tool.title)`) take values already localized by PinxelKit — leave them.
4. Command names passed to the model: `model.update(name: CommandName.arrowHeads, …)` etc. (map: Punte → `.arrowHeads`, Forma → `.shape`, Forma lente → `.magnifierShape`, Connettore → `.connector`, Ingrandimento → `.magnification`, Intensità → `.intensity`, Sequenza → `.sequence`, Carattere → `.font`, Dimensione testo → `.textSize`, Colore testo → `.textColor`, Allineamento → `.alignment`, Grassetto → `.bold`, Corsivo → `.italic`, Sottolineato → `.underline`, Bordo, ombra e margini → `.canvasStyle`, Ridimensiona → `.resize`).
5. Not text: accessibility identifiers, SF Symbol names, notification identifiers, UserDefaults keys, file names, `-Pinxel…` launch arguments, log messages — unchanged.
6. Standard menu items use the glossary and macOS wording ("Zoom In", "Zoom Out", "Actual Size", "Zoom to Fit", "Bring to Front"…). Keyboard shortcut definitions do not change.

For each converted file, add its strings to a TSV (key, it, de, fr, comment) — the Italian column is the text the file had before. Use the glossary for German and French.

- [ ] **Step 2: Info.plist strings**

`project.yml`: `CFBundleTypeName: Pinxel Document` (and `Image` for the image type), `UTTypeDescription: Pinxel Document`. Create `App/Pinxel/InfoPlist.xcstrings`:

```json
{
  "sourceLanguage" : "en",
  "strings" : {
    "CFBundleDisplayName" : { "shouldTranslate" : false },
    "Image" : { "localizations" : {
      "it" : { "stringUnit" : { "state" : "translated", "value" : "Immagine" } },
      "de" : { "stringUnit" : { "state" : "translated", "value" : "Bild" } },
      "fr" : { "stringUnit" : { "state" : "translated", "value" : "Image" } } } },
    "Pinxel Document" : { "localizations" : {
      "it" : { "stringUnit" : { "state" : "translated", "value" : "Documento Pinxel" } },
      "de" : { "stringUnit" : { "state" : "translated", "value" : "Pinxel-Dokument" } },
      "fr" : { "stringUnit" : { "state" : "translated", "value" : "Document Pinxel" } } } }
  },
  "version" : "1.0"
}
```

If Xcode's InfoPlist catalog expects keys named after the Info.plist keys (`CFBundleDocumentTypes` entries are localized through `InfoPlist.strings` by the *value*), check the built app: `ls build/l10n/Build/Products/Debug/Pinxel.app/Contents/Resources/it.lproj/` must contain `InfoPlist.strings` with `"Pinxel Document" = "Documento Pinxel";`. If the document type names stay English, use the `CFBundleTypeName` value as key (as above) — that is how Launch Services localizes document type names.

- [ ] **Step 3: Merge, build, coverage**

Merge every TSV into `App/Pinxel/Localizable.xcstrings` (create it first with the empty catalog content from Task 1), add both catalogs to the app target's resources (`xcodegen` picks them up from `App/Pinxel` automatically — confirm with `grep -n xcstrings Pinxel.xcodeproj/project.pbxproj`), then:

Run: `xcodegen generate && xcodebuild -project Pinxel.xcodeproj -scheme Pinxel -configuration Debug -derivedDataPath build/l10n SWIFT_EMIT_LOC_STRINGS=YES build 2>&1 | tail -1` → `** BUILD SUCCEEDED **`.
Run: `python3 scripts/l10n/xcstrings.py coverage build/l10n .` → every catalog `0 missing`, exit 0. Remove `unused` keys from the catalogs (they are leftovers).

Note: Xcode may add newly extracted keys to `Localizable.xcstrings` by itself during the build (state `new`, no translations). The app catalog test in Step 4 then fails until they are translated — that is the intended safety net.

- [ ] **Step 4: App catalog test**

Add to `PinxelKit/Tests/AppCoreTests/AppCoreCatalogTests.swift`:

```swift
    @Test func appCatalogsAreComplete() throws {
        let root = Catalogs.url(module: "AppCore").deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        for name in ["Localizable", "InfoPlist"] {
            let url = root.appendingPathComponent("App/Pinxel/\(name).xcstrings")
            #expect(try CatalogValidation.problems(inCatalogAt: url) == [], "\(name)")
        }
    }
```

Run: `python3 …/pt.py AppCoreCatalogTests` → `exit 0`.

- [ ] **Step 5: Leftover Italian scan**

Run:

```bash
grep -rnE '"[^"]*([àèéìòù]|\b(il|lo|la|gli|le|un|una|di|da|per|con|non|Impossibile|Nessun[ao]?|Apri|Salva|Chiudi|Annulla)\b)[^"]*"' App/Pinxel PinxelKit/Sources --include='*.swift' | grep -v '^\s*//' | grep -v 'Logger\|logger\.\|accessibilityIdentifier\|forKey\|"-Pinxel'
```

(in zsh, quote the glob or run with `bash -c`). Expected: no user-visible literal left. Comments are excluded by the second grep only when they start the line; inspect the rest by hand and convert any real UI text (then re-run Step 3).

- [ ] **Step 6: See it**

Launch the built app in each language (`open -n build/l10n/Build/Products/Debug/Pinxel.app --args -AppleLanguages "(de)" -PinxelUITestOpenSample` and likewise `en`, `fr`, `it`), open the editor, the Settings window and the library strip, and take a screenshot of the Pinxel window only (`screencapture -l <windowID>`; get the ID with the `CGWindowListCopyWindowInfo` one-liner below) to check truncated labels in German and French:

```bash
python3 -c 'import Quartz; print([ (w["kCGWindowNumber"], w.get("kCGWindowName")) for w in Quartz.CGWindowListCopyWindowInfo(Quartz.kCGWindowListOptionOnScreenOnly, 0) if w.get("kCGWindowOwnerName")=="Pinxel"])'
```

Shorten any German or French label that is cut off (keep the meaning), re-merge, rebuild. Quit the app after each language.

- [ ] **Step 7: Full suite, app build, commit**

Run: `python3 …/pt.py` → `exit 0`; `xcodebuild -project Pinxel.xcodeproj -scheme Pinxel -configuration Debug build 2>&1 | tail -1` → `** BUILD SUCCEEDED **`.

```bash
git add App project.yml PinxelKit/Tests
git commit -m "feat(l10n): the app in English, Italian, German and French" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: UI tests, docs

**Files:**
- Modify: every `XCUIApplication` launch in `App/PinxelUITests/*.swift`
- Create: `App/PinxelUITests/LocalizationUITests.swift`, `docs/manual-tests/localization.md`
- Modify: `README.md` (library path), `docs/manual-tests/library.md` (path), spec status

- [ ] **Step 1: Italian UI tests on any Mac**

In every `launchArguments` array put `"-AppleLanguages", "(it)"` right after `"-ApplePersistenceIgnoreState", "YES"` (key-value pairs before valueless flags: AppKit reads arguments in pairs). Run: `caffeinate -dimsu xcodebuild -project Pinxel.xcodeproj -scheme Pinxel -destination 'platform=macOS' test -only-testing:PinxelUITests 2>&1 | grep -E "Test Case.*(failed|skipped)|TEST SUCCEEDED|TEST FAILED"` → `TEST SUCCEEDED` (menu-bar tests may be skipped when the notch hides the icon).

- [ ] **Step 2: Language UI tests** — `App/PinxelUITests/LocalizationUITests.swift`:

```swift
import XCTest

/// L'app nelle quattro lingue: i menu e la barra seguono la lingua scelta all'avvio; una lingua non tradotta dà l'inglese.
final class LocalizationUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ language: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(\(language))",
                               "-PinxelUITestLibraryName", UUID().uuidString, "-PinxelUITestOpenSample"]
        app.launch()
        app.activate()
        XCTAssertTrue(app.images["pinxel.editor.canvas"].waitForExistence(timeout: 10))
        return app
    }

    private func assertMenus(_ language: String, arrange: String, tool: String, file: StaticString = #filePath, line: UInt = #line) {
        let app = launch(language)
        defer { app.terminate() }
        XCTAssertTrue(app.menuBars.menuBarItems[arrange].waitForExistence(timeout: 5), "menu \(arrange)", file: file, line: line)
        XCTAssertTrue(app.toolbars.descendants(matching: .any)[tool].exists || app.radioButtons[tool].exists, "tool \(tool)", file: file, line: line)
    }

    func testEnglish() { assertMenus("en", arrange: "Arrange", tool: "Cut Out") }
    func testGerman() { assertMenus("de", arrange: "Anordnen", tool: "Ausschneiden und schließen") }
    func testFrench() { assertMenus("fr", arrange: "Disposition", tool: "Couper et rapprocher") }
    func testItalian() { assertMenus("it", arrange: "Disponi", tool: "Taglia e ricuci") }
    func testUnsupportedLanguageFallsBackToEnglish() { assertMenus("es", arrange: "Arrange", tool: "Cut Out") }
}
```

The `arrange` strings must match the app catalog's translation of the menu title "Arrange" (glossary: `Disponi` / `Anordnen` / `Disposition`); if the menu bar is not reachable (`menuBars` empty, seen before in this repo with some launch setups), assert only the tool title and say so in the ledger.

Run: `caffeinate -dimsu xcodebuild … test -only-testing:PinxelUITests/LocalizationUITests` → `TEST SUCCEEDED`.

- [ ] **Step 3: Docs**

`docs/manual-tests/localization.md`:

```markdown
# Prove a mano — Lingue

Cambia la lingua di Pinxel in Impostazioni di Sistema ▸ Generali ▸ Lingua e Zona ▸ App (aggiungi Pinxel), poi riapri l'app.

| # | Prova | Atteso |
|---|-------|--------|
| T1 | Inglese: menu della barra, menu Disponi, Impostazioni, editor, carosello | Tutto in inglese, nessuna parola italiana |
| T2 | Tedesco: come T1 | Tutto in tedesco; nessuna etichetta tagliata |
| T3 | Francese: come T1 | Tutto in francese; nessuna etichetta tagliata |
| T4 | Italiano: come T1 | Come prima di questa versione |
| T5 | Spagnolo (o un'altra lingua non tradotta) | Inglese |
| T6 | Sposta un oggetto, apri il menu Modifica | "Annulla Sposta" / "Undo Move" / "Widerrufen: Bewegen"… nella lingua scelta |
| T7 | Primo avvio dopo l'aggiornamento | `~/Pictures/Pinxel/Library` contiene tutte le catture; `Libreria` non c'è più; il carosello le mostra |
| T8 | Salvataggio automatico con il nome predefinito, in italiano | "Pinxel 2026-10-20 alle 14.30.00.pinxel" |
| T9 | Un documento `.pinxel` nel Finder, Ottieni informazioni | Tipo "Documento Pinxel" / "Pinxel Document" / "Pinxel-Dokument" / "Document Pinxel" |
| T10 | Rilettura da parte di un madrelingua di tedesco e francese | Nessun errore o termine strano (da fare quando possibile) |
```

`README.md` (English since PR #12 — merge #12 into `main` and rebase this branch on it first, or the README will conflict): library path `~/Pictures/Pinxel/Library`; add "Languages: English, Italian, German, French (follows the Mac's language)." under "What it does". `docs/manual-tests/library.md`: every `Libreria` path → `Library`. Spec status → `**Stato:** approvata, implementata`.

- [ ] **Step 4: Commit**

```bash
git add App/PinxelUITests docs README.md
git commit -m "test(l10n): UI tests per language, manual checklist and docs" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

## Self-review notes

- Spec §3.2 lists `Library`, `Rendering`, `CaptureKit` as modules "per le poche scritte che hanno": inventory shows they have none (`Helvetica`, `Pinxel`, the fake capture window name used only by UI tests, the folder name), so they get no catalog. Cost if wrong: a catalog added later.
- `library.json.rovinato` (corrupt index backup name) is a file name, not UI text: unchanged (spec §6).
- "Undo …" titles switch to `UndoManager.undoMenuTitle(forUndoActionName:)`, so Italian becomes "Annulla Sposta" instead of "Annulla sposta" (system capitalization in every language). Cost if wrong: one localized format string.
- The README is already English (PR #12); Task 6 only updates the library path and adds the language line.
