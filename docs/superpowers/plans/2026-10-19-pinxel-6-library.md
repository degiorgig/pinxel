# Capture Library Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every capture is kept in a permanent library (one `.pinxel` file per capture plus a `library.json` index with folders and tags), browsable and usable from a thumbnail strip at the bottom of every editor window.

**Architecture:** A new pure package module `Library` holds the index model (`LibraryIndex`), the filter (`LibraryFilter`) and all disk work (`LibraryStore`); it depends on `DocumentModel`, `Persistence` and `AppCore`. The app gets one shared `@Observable LibraryModel`, a per-window `LibraryStripState`, and a SwiftUI `LibraryStrip` under the canvas. Captures are written to the library before any post-capture step and opened from their library URL, so `NSDocument` autosaves them in place. `CanvasView` learns to accept dropped images as image annotations.

**Tech Stack:** Swift 6, macOS 15+, AppKit + SwiftUI, Swift Testing (package), XCTest (UI tests), XcodeGen.

**Spec:** `docs/superpowers/specs/2026-10-19-pinxel-library-design.md`

## Global Constraints

- macOS 15+, Swift 6 strict concurrency; no third-party dependencies.
- Library folder: `~/Pictures/Pinxel/Libreria`; index `library.json`; corrupt copy `library.json.rovinato` (replaces an older one).
- One `.pinxel` per capture, name from `FileNamer.baseName(template: FileNamer.defaultTemplate, date:)` made unique with `FileNamer.uniqueURL`, never overwritten; written to a hidden temporary file and then moved.
- Item identity = file name. A capture has one folder or none and zero or more tags; tags compare case-insensitively and keep the first spelling.
- Files are the source of truth: reconcile at load and when Pinxel becomes active.
- Every capture enters the library before the other "Dopo la cattura" steps; if that fails, warn and behave as today.
- Deleting moves to the Trash with no confirmation; when the Trash is unavailable, confirm and delete permanently. Open windows on deleted captures close first.
- Strip ~110 pt high, newest first; toggle with toolbar button and Vista ▸ Mostra/Nascondi carosello (⌃⌘L — the spec's ⌥⌘L is already Sblocca), shared across windows, stored in `UserDefaults` key `libraryStripVisible`, default visible.
- Filter and selection are per window; the index is shared.
- Search folds case and diacritics; it matches app, window title, tags, folder name and the date formatted `yyyy-MM-dd`.
- UI tests must never write to the user's real library: when `-PinxelUITestFakeCapture` is present the library lives in a fresh temporary folder unless `-PinxelLibraryFolder <path>` is given.
- User-facing strings in Italian; code comments in Italian like the surrounding files; commits in English with the Co-Authored-By trailer.
- Never mention other screenshot products in the repo (public).
- After adding files or targets run `xcodegen generate`.

## Review Focus

1. UI tests and the debug app share one machine: a fake capture landing in the real `~/Pictures/Pinxel/Libreria` would pollute the user's archive. → `AppEnvironment` picks a temporary folder under UI testing; asserted in Task 8's UI test by passing `-PinxelLibraryFolder` and checking the file lands there.
2. A capture's window is open while the user edits, and the document autosaves: the strip must show the new thumbnail and the index the new pixel size (crop/resize) without a relaunch. → Task 4 test `refreshedItemReadsNewSize`, Task 6 wiring of the save notification.
3. Two captures in the same second: the second must get "… 2.pinxel", never overwrite the first. → Task 4 test `twoCapturesInTheSameSecondGetDistinctFiles`.
4. A `library.json` written by a future version (`version: 2`): it must not be overwritten silently; it is set aside and the index rebuilt from the files. → Task 2 test `futureVersionIsRejected`, Task 4 test `futureIndexIsSetAsideAndRebuilt`.
5. Clicking a thumbnail while the window shows an untitled, edited document (library failure, New, an image opened from Finder): the unsaved work must not be closed. → Task 7 `LibraryOpener` uses the pure rule `LibraryOpenDecision`, pinned by Task 4's `LibraryOpenDecisionTests`.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `PinxelKit/Sources/Persistence/PinxelArchive.swift` | `readDocument(_:)`, `readThumbnail(_:)` light reads |
| `PinxelKit/Sources/Library/LibraryIndex.swift` (new) | index model + pure operations |
| `PinxelKit/Sources/Library/LibraryFilter.swift` (new) | folder/tag/text filtering and order |
| `PinxelKit/Sources/Library/LibraryStore.swift` (new) | disk: load/save/reconcile, add, import, thumbnails, trash |
| `PinxelKit/Sources/Library/LibraryOpenDecision.swift` (new) | pure rule: replace in window, new window, or focus existing |
| `PinxelKit/Package.swift`, `project.yml` | new `Library` target/product and test target |
| `PinxelKit/Sources/EditorUI/CanvasView.swift` | accept dropped images as image annotations |
| `App/Pinxel/Library/LibraryModel.swift` (new) | shared observable library, operations, notifications |
| `App/Pinxel/Library/LibraryOpener.swift` (new) | open/replace/focus documents for library items |
| `App/Pinxel/Library/LibraryStrip.swift` (new) | strip view: filter bar, thumbnails, menus |
| `App/Pinxel/Library/LibraryThumbnailView.swift` (new) | one thumbnail: lazy image, drag out, selection border |
| `App/Pinxel/Library/ThumbnailCache.swift` (new) | in-memory thumbnail cache keyed by file + modification date |
| `App/Pinxel/AppEnvironment.swift` | creates `LibraryModel`, library folder choice, last capture URL |
| `App/Pinxel/PostCapture/PostCaptureActions.swift` | add to library first, open library URL |
| `App/Pinxel/Document/PinxelFileDocument.swift` | post `.pinxelDocumentDidSave` after a save |
| `App/Pinxel/Document/DocumentOpener.swift` | `open(url:)` |
| `App/Pinxel/Editor/EditorView.swift` | strip under the canvas, toolbar toggle |
| `App/Pinxel/EditorCommands.swift` | Vista ▸ Mostra/Nascondi carosello |
| `App/Pinxel/PostCapture/Notifier.swift` | messages for `LibraryError` |
| `PinxelKit/Tests/LibraryTests/*` (new) | unit tests |
| `App/PinxelUITests/LibraryUITests.swift` (new) | end-to-end |
| `docs/manual-tests/library.md` (new) | manual checklist |

---

### Task 1: Light reads of a `.pinxel`

**Files:**
- Modify: `PinxelKit/Sources/Persistence/PinxelArchive.swift`
- Test: `PinxelKit/Tests/PersistenceTests/PinxelArchiveLightReadTests.swift` (new)

**Interfaces:**
- Produces: `PinxelArchive.readDocument(_ data: Data) throws -> PinxelDocument` (manifest + document.json only, same errors as `read`, no image entries read); `PinxelArchive.readThumbnail(_ data: Data) -> Data?`.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
import DocumentModel
import Rendering
@testable import Persistence
import PinxelTestSupport

struct PinxelArchiveLightReadTests {
    func archive(thumbnail: Data = Data([7, 8, 9])) throws -> Data {
        let images = [TestDocuments.background: try ImageCodec.encode(TestImages.quadrants(), type: .png),
                      TestDocuments.placedImage: try ImageCodec.encode(TestImages.solid(width: 10, height: 10, red: 0, green: 0.6, blue: 1), type: .png)]
        return try PinxelArchive.write(document: TestDocuments.document(), images: images, thumbnail: thumbnail, appVersion: "0.1.0")
    }

    @Test func readDocumentReturnsTheDocument() throws {
        #expect(try PinxelArchive.readDocument(archive()) == TestDocuments.document())
    }

    @Test func readDocumentRejectsOtherFiles() {
        #expect(throws: PinxelArchiveError.notAPinxelFile) { try PinxelArchive.readDocument(Data("hello".utf8)) }
    }

    @Test func readThumbnailReturnsTheStoredPNG() throws {
        #expect(PinxelArchive.readThumbnail(try archive()) == Data([7, 8, 9]))
        #expect(PinxelArchive.readThumbnail(Data("hello".utf8)) == nil)
    }
}
```

Note: `readDocumentRejectsOtherFiles` expects `notAPinxelFile`; if `ZipReader` throws a `ZipError` for non-zip data in `read`, mirror whatever `read` does for the same input (check `HostileDocumentTests`) and assert that instead.

- [ ] **Step 2: Run to verify they fail**

Run: `python3 <scratchpad>/pt.py PinxelArchiveLightReadTests`
Expected: compile error, `readDocument` / `readThumbnail` not found.

- [ ] **Step 3: Implement**

In `PinxelArchive`, move the manifest + document decoding of `read` (from `let zip = try ZipReader…` through `validationError`) into:

```swift
    /// Manifest e documento validati, senza leggere le immagini.
    private static func manifestAndDocument(_ zip: ZipReader) throws -> (PinxelManifest, PinxelDocument) {
        // corpo spostato da `read`, invariato
    }

    /// Solo il documento, per l'indice della libreria: non legge le immagini.
    public static func readDocument(_ data: Data, limits: ZipLimits = .default) throws -> PinxelDocument {
        try manifestAndDocument(ZipReader(data, limits: limits)).1
    }

    /// La miniatura salvata nel file, se c'è.
    public static func readThumbnail(_ data: Data) -> Data? {
        try? ZipReader(data).data(for: "thumbnail.png")
    }
```

and make `read` call `let (manifest, document) = try manifestAndDocument(zip)`.

- [ ] **Step 4: Run tests**

Run: `python3 <scratchpad>/pt.py Persistence`
Expected: all Persistence tests pass.

- [ ] **Step 5: Commit**

```bash
git add PinxelKit/Sources/Persistence/PinxelArchive.swift PinxelKit/Tests/PersistenceTests/PinxelArchiveLightReadTests.swift
git commit -m "feat(persistence): read a document or its thumbnail without the images"
```

---

### Task 2: `Library` module and `LibraryIndex`

**Files:**
- Modify: `PinxelKit/Package.swift`, `project.yml`
- Create: `PinxelKit/Sources/Library/LibraryIndex.swift`
- Test: `PinxelKit/Tests/LibraryTests/LibraryIndexTests.swift`

**Interfaces:**
- Produces:
  - `struct LibraryFolder: Codable, Equatable, Sendable, Identifiable { var id: UUID; var name: String }`
  - `struct LibraryItem: Codable, Equatable, Sendable, Identifiable { var file: String; var added: Date; var captureDate: Date; var appName: String?; var windowTitle: String?; var pixelWidth: Int; var pixelHeight: Int; var folder: UUID?; var tags: [String]; var id: String { file } }`
  - `enum LibraryIndexError: Error, Equatable { case futureVersion(Int), emptyName, duplicateName }`
  - `struct LibraryIndex: Codable, Equatable, Sendable` with `static let currentVersion = 1`, `version`, `folders`, `items` (both `private(set)`), and: `item(_ file: String) -> LibraryItem?`, `mutating add(_:)` (replaces an entry with the same file), `mutating update(_ file:, pixelWidth:, pixelHeight:)`, `mutating remove(_ files: Set<String>)`, `mutating move(_ files: Set<String>, to folder: UUID?)`, `mutating addTag(_ tag: String, to files: Set<String>)`, `mutating removeTag(_ tag: String, from files: Set<String>)`, `mutating createFolder(named:) throws -> LibraryFolder`, `mutating renameFolder(_ id: UUID, to name: String) throws`, `mutating deleteFolder(_ id: UUID)`, `folder(_ id: UUID) -> LibraryFolder?`, `allTags: [String]`, `reconciled(withFiles: Set<String>, makeItem: (String) -> LibraryItem) -> LibraryIndex`.

- [ ] **Step 1: Add the targets**

In `PinxelKit/Package.swift` add to `products`:

```swift
        .library(name: "Library", targets: ["Library"]),
```

to `targets`:

```swift
        .target(name: "Library", dependencies: ["DocumentModel", "Persistence", "AppCore"]),
```

and the test target:

```swift
        .testTarget(
            name: "LibraryTests",
            dependencies: ["Library", "AppCore", "Persistence", "PinxelTestSupport"]
        ),
```

In `project.yml`, under the `Pinxel` target dependencies, add:

```yaml
      - package: PinxelKit
        product: Library
```

- [ ] **Step 2: Write the failing tests**

```swift
import Foundation
import Testing
@testable import Library

struct LibraryIndexTests {
    func item(_ file: String, added: TimeInterval = 0, tags: [String] = [], folder: UUID? = nil) -> LibraryItem {
        LibraryItem(file: file, added: Date(timeIntervalSince1970: added), captureDate: Date(timeIntervalSince1970: added),
                    appName: nil, windowTitle: nil, pixelWidth: 10, pixelHeight: 10, folder: folder, tags: tags)
    }

    @Test func addReplacesTheSameFile() {
        var index = LibraryIndex()
        index.add(item("a.pinxel"))
        var changed = item("a.pinxel")
        changed.pixelWidth = 99
        index.add(changed)
        #expect(index.items.count == 1)
        #expect(index.item("a.pinxel")?.pixelWidth == 99)
    }

    @Test func foldersRejectEmptyAndDuplicateNames() throws {
        var index = LibraryIndex()
        let work = try index.createFolder(named: "  Lavoro ")
        #expect(work.name == "Lavoro")
        #expect(throws: LibraryIndexError.emptyName) { try index.createFolder(named: "   ") }
        #expect(throws: LibraryIndexError.duplicateName) { try index.createFolder(named: "lavoro") }
        let home = try index.createFolder(named: "Casa")
        #expect(throws: LibraryIndexError.duplicateName) { try index.renameFolder(home.id, to: "LAVORO") }
        try index.renameFolder(home.id, to: "Casa mia")
        #expect(index.folder(home.id)?.name == "Casa mia")
    }

    @Test func deletingAFolderKeepsItsCaptures() throws {
        var index = LibraryIndex()
        let work = try index.createFolder(named: "Lavoro")
        index.add(item("a.pinxel", folder: work.id))
        index.deleteFolder(work.id)
        #expect(index.folders.isEmpty)
        #expect(index.item("a.pinxel")?.folder == nil)
    }

    @Test func moveSetsAndClearsTheFolder() throws {
        var index = LibraryIndex()
        let work = try index.createFolder(named: "Lavoro")
        index.add(item("a.pinxel"))
        index.add(item("b.pinxel"))
        index.move(["a.pinxel", "b.pinxel"], to: work.id)
        #expect(index.items.allSatisfy { $0.folder == work.id })
        index.move(["a.pinxel"], to: nil)
        #expect(index.item("a.pinxel")?.folder == nil)
    }

    @Test func tagsAreCaseInsensitiveAndKeepTheFirstSpelling() {
        var index = LibraryIndex()
        index.add(item("a.pinxel"))
        index.add(item("b.pinxel"))
        index.addTag("Bug", to: ["a.pinxel"])
        index.addTag("bug ", to: ["a.pinxel", "b.pinxel"])
        #expect(index.item("a.pinxel")?.tags == ["Bug"])
        #expect(index.item("b.pinxel")?.tags == ["Bug"])
        index.addTag("   ", to: ["a.pinxel"])
        #expect(index.item("a.pinxel")?.tags == ["Bug"])
        index.removeTag("BUG", from: ["a.pinxel"])
        #expect(index.item("a.pinxel")?.tags == [])
        #expect(index.allTags == ["Bug"])
        index.removeTag("bug", from: ["b.pinxel"])
        #expect(index.allTags.isEmpty)
    }

    @Test func allTagsAreSortedIgnoringCase() {
        var index = LibraryIndex()
        index.add(item("a.pinxel", tags: ["zeta", "Alfa"]))
        index.add(item("b.pinxel", tags: ["beta"]))
        #expect(index.allTags == ["Alfa", "beta", "zeta"])
    }

    @Test func reconcileAddsNewFilesAndDropsMissingOnes() throws {
        var index = LibraryIndex()
        let work = try index.createFolder(named: "Lavoro")
        index.add(item("kept.pinxel", tags: ["x"], folder: work.id))
        index.add(item("gone.pinxel"))
        var orphan = item("orphan.pinxel")
        orphan.folder = UUID()
        index.add(orphan)
        let result = index.reconciled(withFiles: ["kept.pinxel", "new.pinxel", "orphan.pinxel"]) { self.item($0, added: 5) }
        #expect(Set(result.items.map(\.file)) == ["kept.pinxel", "new.pinxel", "orphan.pinxel"])
        #expect(result.item("kept.pinxel")?.tags == ["x"])
        #expect(result.item("kept.pinxel")?.folder == work.id)
        #expect(result.item("new.pinxel")?.added == Date(timeIntervalSince1970: 5))
        #expect(result.item("orphan.pinxel")?.folder == nil)
    }

    @Test func roundTripsThroughJSON() throws {
        var index = LibraryIndex()
        let work = try index.createFolder(named: "Lavoro")
        index.add(item("a.pinxel", tags: ["bug"], folder: work.id))
        let data = try JSONEncoder().encode(index)
        #expect(try JSONDecoder().decode(LibraryIndex.self, from: data) == index)
    }

    @Test func unreadableItemsAreSkippedAndUnknownFieldsIgnored() throws {
        let json = """
        {"version":1,"folders":[],"items":[
          {"file":"a.pinxel","added":0,"captureDate":0,"pixelWidth":1,"pixelHeight":1,"tags":[],"future":"x"},
          {"file":"broken.pinxel"}
        ]}
        """
        let index = try JSONDecoder().decode(LibraryIndex.self, from: Data(json.utf8))
        #expect(index.items.map(\.file) == ["a.pinxel"])
    }

    @Test func futureVersionIsRejected() {
        let json = #"{"version":2,"folders":[],"items":[]}"#
        #expect(throws: LibraryIndexError.futureVersion(2)) { try JSONDecoder().decode(LibraryIndex.self, from: Data(json.utf8)) }
    }
}
```

Note: the JSON in `unreadableItemsAreSkippedAndUnknownFieldsIgnored` uses the default `JSONDecoder` date strategy (seconds since 2001); `LibraryStore` (Task 4) uses ISO 8601. The test decodes with the default decoder, so `0` is valid.

- [ ] **Step 3: Run to verify they fail**

Run: `python3 <scratchpad>/pt.py LibraryIndexTests`
Expected: compile errors (types not defined).

- [ ] **Step 4: Implement `LibraryIndex.swift`**

```swift
import Foundation

public struct LibraryFolder: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String

    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

/// Una cattura dell'archivio: il nome del file è la sua identità.
public struct LibraryItem: Codable, Equatable, Sendable, Identifiable {
    public var file: String
    public var added: Date
    public var captureDate: Date
    public var appName: String?
    public var windowTitle: String?
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var folder: UUID?
    public var tags: [String]

    public var id: String { file }

    public init(file: String, added: Date, captureDate: Date, appName: String?, windowTitle: String?,
                pixelWidth: Int, pixelHeight: Int, folder: UUID? = nil, tags: [String] = []) {
        self.file = file
        self.added = added
        self.captureDate = captureDate
        self.appName = appName
        self.windowTitle = windowTitle
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.folder = folder
        self.tags = tags
    }
}

public enum LibraryIndexError: Error, Equatable {
    case futureVersion(Int)
    case emptyName
    case duplicateName
}

/// Contenuto di `library.json`: cartelle e catture. Le etichette non hanno una lista propria:
/// sono quelle usate dalle catture.
public struct LibraryIndex: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public private(set) var version = LibraryIndex.currentVersion
    public private(set) var folders: [LibraryFolder] = []
    public private(set) var items: [LibraryItem] = []

    public init() {}

    private enum CodingKeys: String, CodingKey { case version, folders, items }

    /// Una voce illeggibile si salta senza perdere le altre; un indice di una versione futura non si tocca.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decode(Int.self, forKey: .version)
        guard version <= Self.currentVersion else { throw LibraryIndexError.futureVersion(version) }
        folders = (try? c.decode([Lenient<LibraryFolder>].self, forKey: .folders))?.compactMap(\.value) ?? []
        items = (try? c.decode([Lenient<LibraryItem>].self, forKey: .items))?.compactMap(\.value) ?? []
    }

    public func item(_ file: String) -> LibraryItem? {
        items.first { $0.file == file }
    }

    public func folder(_ id: UUID) -> LibraryFolder? {
        folders.first { $0.id == id }
    }

    public mutating func add(_ item: LibraryItem) {
        if let i = items.firstIndex(where: { $0.file == item.file }) {
            items[i] = item
        } else {
            items.append(item)
        }
    }

    public mutating func update(_ file: String, pixelWidth: Int, pixelHeight: Int) {
        guard let i = items.firstIndex(where: { $0.file == file }) else { return }
        items[i].pixelWidth = pixelWidth
        items[i].pixelHeight = pixelHeight
    }

    public mutating func remove(_ files: Set<String>) {
        items.removeAll { files.contains($0.file) }
    }

    public mutating func move(_ files: Set<String>, to folder: UUID?) {
        for i in items.indices where files.contains(items[i].file) { items[i].folder = folder }
    }

    public mutating func addTag(_ tag: String, to files: Set<String>) {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Stessa etichetta scritta in un altro modo: si usa la grafia già presente.
        let spelling = allTags.first { Self.same($0, trimmed) } ?? trimmed
        for i in items.indices where files.contains(items[i].file) && !items[i].tags.contains(where: { Self.same($0, spelling) }) {
            items[i].tags.append(spelling)
        }
    }

    public mutating func removeTag(_ tag: String, from files: Set<String>) {
        for i in items.indices where files.contains(items[i].file) {
            items[i].tags.removeAll { Self.same($0, tag) }
        }
    }

    public mutating func createFolder(named name: String) throws -> LibraryFolder {
        let folder = LibraryFolder(name: try validName(name, excluding: nil))
        folders.append(folder)
        return folder
    }

    public mutating func renameFolder(_ id: UUID, to name: String) throws {
        let valid = try validName(name, excluding: id)
        guard let i = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[i].name = valid
    }

    public mutating func deleteFolder(_ id: UUID) {
        folders.removeAll { $0.id == id }
        for i in items.indices where items[i].folder == id { items[i].folder = nil }
    }

    /// Le etichette in uso, una per grafia (la prima incontrata), in ordine alfabetico.
    public var allTags: [String] {
        var seen: [String] = []
        for tag in items.flatMap(\.tags) where !seen.contains(where: { Self.same($0, tag) }) { seen.append(tag) }
        return seen.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// I file comandano: entrano quelli senza voce, escono le voci senza file; una cartella sparita diventa "nessuna".
    public func reconciled(withFiles files: Set<String>, makeItem: (String) -> LibraryItem) -> LibraryIndex {
        var result = self
        result.items.removeAll { !files.contains($0.file) }
        let known = Set(result.items.map(\.file))
        for file in files.sorted() where !known.contains(file) { result.items.append(makeItem(file)) }
        let folderIDs = Set(result.folders.map(\.id))
        for i in result.items.indices where result.items[i].folder.map({ !folderIDs.contains($0) }) ?? false {
            result.items[i].folder = nil
        }
        return result
    }

    private func validName(_ name: String, excluding id: UUID?) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LibraryIndexError.emptyName }
        guard !folders.contains(where: { $0.id != id && Self.same($0.name, trimmed) }) else { throw LibraryIndexError.duplicateName }
        return trimmed
    }

    static func same(_ a: String, _ b: String) -> Bool {
        a.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(b.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }
}

/// Decodifica che non fallisce: un elemento illeggibile diventa `nil`.
private struct Lenient<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}
```

- [ ] **Step 5: Run tests and regenerate the project**

Run: `python3 <scratchpad>/pt.py LibraryIndexTests` then `xcodegen generate`
Expected: 10 tests pass; project generated.

- [ ] **Step 6: Commit**

```bash
git add PinxelKit/Package.swift project.yml PinxelKit/Sources/Library PinxelKit/Tests/LibraryTests
git commit -m "feat(library): index with folders and tags"
```

---

### Task 3: `LibraryFilter`

**Files:**
- Create: `PinxelKit/Sources/Library/LibraryFilter.swift`
- Test: `PinxelKit/Tests/LibraryTests/LibraryFilterTests.swift`

**Interfaces:**
- Consumes: `LibraryIndex`, `LibraryItem`, `LibraryFolder` (Task 2).
- Produces: `enum FolderScope: Hashable, Sendable { case all, unfiled, folder(UUID) }`; `struct LibraryFilter: Equatable, Sendable { var folder: FolderScope = .all; var tag: String?; var text = ""; init(); func apply(to: LibraryIndex, timeZone: TimeZone = .current) -> [LibraryItem] }`.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import Library

struct LibraryFilterTests {
    let utc = TimeZone(identifier: "UTC")!

    func makeIndex() throws -> (LibraryIndex, LibraryFolder) {
        var index = LibraryIndex()
        let work = try index.createFolder(named: "Lavoro Città")
        // 2026-10-19 08:00 UTC e 2026-10-18 08:00 UTC
        index.add(LibraryItem(file: "new.pinxel", added: Date(timeIntervalSince1970: 1_792_396_800), captureDate: Date(timeIntervalSince1970: 1_792_396_800),
                              appName: "Safari", windowTitle: "Café — Menu", pixelWidth: 1, pixelHeight: 1, folder: work.id, tags: ["Bug"]))
        index.add(LibraryItem(file: "old.pinxel", added: Date(timeIntervalSince1970: 1_792_310_400), captureDate: Date(timeIntervalSince1970: 1_792_310_400),
                              appName: "Mail", windowTitle: nil, pixelWidth: 1, pixelHeight: 1))
        return (index, work)
    }

    @Test func allIsNewestFirst() throws {
        let (index, _) = try makeIndex()
        #expect(LibraryFilter().apply(to: index, timeZone: utc).map(\.file) == ["new.pinxel", "old.pinxel"])
    }

    @Test func folderScopes() throws {
        let (index, work) = try makeIndex()
        var filter = LibraryFilter()
        filter.folder = .folder(work.id)
        #expect(filter.apply(to: index, timeZone: utc).map(\.file) == ["new.pinxel"])
        filter.folder = .unfiled
        #expect(filter.apply(to: index, timeZone: utc).map(\.file) == ["old.pinxel"])
    }

    @Test func tagIgnoresCase() throws {
        let (index, _) = try makeIndex()
        var filter = LibraryFilter()
        filter.tag = "bug"
        #expect(filter.apply(to: index, timeZone: utc).map(\.file) == ["new.pinxel"])
    }

    @Test func textFoldsCaseAndAccents() throws {
        let (index, _) = try makeIndex()
        var filter = LibraryFilter()
        for text in ["cafe", "SAFARI", "citta", "bug", "2026-10-19"] {
            filter.text = text
            #expect(filter.apply(to: index, timeZone: utc).map(\.file) == ["new.pinxel"], "\(text)")
        }
        filter.text = "2026-10-18"
        #expect(filter.apply(to: index, timeZone: utc).map(\.file) == ["old.pinxel"])
    }

    @Test func everyWordMustMatchAndFiltersCombine() throws {
        let (index, work) = try makeIndex()
        var filter = LibraryFilter()
        filter.text = "safari menu"
        #expect(filter.apply(to: index, timeZone: utc).count == 1)
        filter.text = "safari mail"
        #expect(filter.apply(to: index, timeZone: utc).isEmpty)
        filter.text = "mail"
        filter.folder = .folder(work.id)
        #expect(filter.apply(to: index, timeZone: utc).isEmpty)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `python3 <scratchpad>/pt.py LibraryFilterTests`
Expected: compile errors.

- [ ] **Step 3: Implement**

```swift
import Foundation

public enum FolderScope: Hashable, Sendable {
    case all
    case unfiled
    case folder(UUID)
}

/// Cosa mostra il carosello: cartella, etichetta e testo insieme (E logico), dalla cattura più nuova.
public struct LibraryFilter: Equatable, Sendable {
    public var folder: FolderScope = .all
    public var tag: String?
    public var text = ""

    public init() {}

    public func apply(to index: LibraryIndex, timeZone: TimeZone = .current) -> [LibraryItem] {
        let words = Self.fold(text).split(whereSeparator: \.isWhitespace).map(String.init)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return index.items
            .filter { item in
                switch folder {
                case .all: true
                case .unfiled: item.folder == nil
                case .folder(let id): item.folder == id
                }
            }
            .filter { item in tag.map { tag in item.tags.contains { LibraryIndex.same($0, tag) } } ?? true }
            .filter { item in
                guard !words.isEmpty else { return true }
                var fields = [item.appName, item.windowTitle, item.folder.flatMap { index.folder($0)?.name }, formatter.string(from: item.captureDate)]
                    .compactMap { $0 }
                fields += item.tags
                let haystack = fields.map(Self.fold)
                return words.allSatisfy { word in haystack.contains { $0.contains(word) } }
            }
            .sorted { $0.added != $1.added ? $0.added > $1.added : $0.file > $1.file }
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
```

- [ ] **Step 4: Run tests**

Run: `python3 <scratchpad>/pt.py Library`
Expected: all Library tests pass.

- [ ] **Step 5: Commit**

```bash
git add PinxelKit/Sources/Library/LibraryFilter.swift PinxelKit/Tests/LibraryTests/LibraryFilterTests.swift
git commit -m "feat(library): filter by folder, tag and text"
```

---

### Task 4: `LibraryStore` and `LibraryOpenDecision`

**Files:**
- Create: `PinxelKit/Sources/Library/LibraryStore.swift`, `PinxelKit/Sources/Library/LibraryOpenDecision.swift`
- Test: `PinxelKit/Tests/LibraryTests/LibraryStoreTests.swift`, `PinxelKit/Tests/LibraryTests/LibraryOpenDecisionTests.swift`

**Interfaces:**
- Consumes: Task 1 `PinxelArchive.readDocument/readThumbnail`; Task 2 `LibraryIndex`; `FileNamer`, `ImageImport`, `Thumbnailer`, `PinxelArchive.write`.
- Produces:
  - `enum LibraryError: Error, Equatable { case notWritable(String), writeFailed(String), unsupportedFile(String), trashUnavailable }`
  - `struct LibraryLoad { var index: LibraryIndex; var setAsideCorruptIndex: Bool }`
  - `final class LibraryStore` with `static var defaultFolder: URL`, `static let indexName = "library.json"`, `static let corruptName = "library.json.rovinato"`, `let folder: URL`, `init(folder: URL, fileManager: FileManager = .default, appVersion: String = "0.1.0", now: @escaping () -> Date = Date.init)`, `func load() -> LibraryLoad`, `func save(_ index: LibraryIndex) throws`, `func add(_ contents: PinxelFileContents, to index: inout LibraryIndex) throws -> LibraryItem`, `func importFile(at url: URL, into index: inout LibraryIndex) throws -> LibraryItem`, `func url(for item: LibraryItem) -> URL`, `func file(for url: URL) -> String?` (name if the URL is a direct child of `folder`), `func refreshed(_ file: String, in index: inout LibraryIndex)`, `func trash(_ files: Set<String>, in index: inout LibraryIndex) throws`, `func deletePermanently(_ files: Set<String>, in index: inout LibraryIndex) throws`, `static func thumbnail(at url: URL) -> Data?` (nonisolated, safe off the main thread).
  - `enum LibraryOpenDecision: Equatable { case focusExisting, replaceInWindow, openNewWindow }` with `static func decide(targetAlreadyOpen: Bool, windowShowsLibraryItem: Bool) -> LibraryOpenDecision`.

- [ ] **Step 1: Write the failing store tests**

```swift
import Foundation
import Testing
import DocumentModel
import Persistence
import AppCore
@testable import Library
import PinxelTestSupport

/// FileManager con Cestino non disponibile, per il ripiego della cancellazione definitiva.
final class NoTrashFileManager: FileManager, @unchecked Sendable {
    override func trashItem(at url: URL, resultingItemURL outResultingURL: AutoreleasingUnsafeMutablePointer<NSURL?>?) throws {
        throw CocoaError(.featureUnsupported)
    }
}

struct LibraryStoreTests {
    let date = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func temporaryFolder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("pinxel-library-\(UUID().uuidString)")
    }

    func contents(app: String? = "Safari") throws -> PinxelFileContents {
        try CaptureDocumentBuilder.make(image: TestImages.quadrants(), scale: 2,
                                        metadata: CaptureMetadata(captureDate: date, appName: app, windowTitle: "Pagina"))
    }

    func files(in folder: URL) throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: folder.path))
    }

    @Test func addWritesAPinxelAndAnEntry() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LibraryStore(folder: folder, now: { self.date })
        var index = LibraryIndex()
        let item = try store.add(contents(), to: &index)
        #expect(item.file.hasSuffix(".pinxel"))
        #expect(item.appName == "Safari" && item.windowTitle == "Pagina")
        #expect(item.pixelWidth == 400 && item.pixelHeight == 300)
        #expect(index.item(item.file) == item)
        let reread = try PinxelArchive.read(Data(contentsOf: store.url(for: item)))
        #expect(reread.document.canvasSize == PixelSize(width: 400, height: 300))
        #expect(LibraryStore.thumbnail(at: store.url(for: item)) != nil)
        #expect(try files(in: folder) == [item.file])
    }

    @Test func twoCapturesInTheSameSecondGetDistinctFiles() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LibraryStore(folder: folder, now: { self.date })
        var index = LibraryIndex()
        let first = try store.add(contents(), to: &index)
        let second = try store.add(contents(), to: &index)
        #expect(first.file != second.file)
        #expect(second.file.hasSuffix(" 2.pinxel"))
    }

    @Test func saveAndLoadRoundTrip() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LibraryStore(folder: folder)
        var index = LibraryIndex()
        let item = try store.add(contents(), to: &index)
        index.addTag("bug", to: [item.file])
        try store.save(index)
        let load = store.load()
        #expect(load.index == index)
        #expect(!load.setAsideCorruptIndex)
    }

    @Test func loadReconcilesWithTheFolder() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LibraryStore(folder: folder)
        var index = LibraryIndex()
        let kept = try store.add(contents(), to: &index)
        let gone = try store.add(contents(), to: &index)
        try store.save(index)
        try FileManager.default.removeItem(at: store.url(for: gone))
        // Un .pinxel copiato a mano nella cartella.
        try FileManager.default.copyItem(at: store.url(for: kept), to: folder.appendingPathComponent("A mano.pinxel"))
        let load = store.load()
        #expect(Set(load.index.items.map(\.file)) == [kept.file, "A mano.pinxel"])
        #expect(load.index.item("A mano.pinxel")?.appName == "Safari")
    }

    @Test func missingIndexIsBuiltFromTheFiles() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LibraryStore(folder: folder)
        var index = LibraryIndex()
        let item = try store.add(contents(), to: &index)
        let load = store.load()
        #expect(load.index.items.map(\.file) == [item.file])
        #expect(!load.setAsideCorruptIndex)
    }

    @Test func corruptIndexIsSetAsideAndRebuilt() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LibraryStore(folder: folder)
        var index = LibraryIndex()
        let item = try store.add(contents(), to: &index)
        try Data("{ rotto".utf8).write(to: folder.appendingPathComponent(LibraryStore.indexName))
        let load = store.load()
        #expect(load.setAsideCorruptIndex)
        #expect(load.index.items.map(\.file) == [item.file])
        #expect(try Data(contentsOf: folder.appendingPathComponent(LibraryStore.corruptName)) == Data("{ rotto".utf8))
    }

    @Test func futureIndexIsSetAsideAndRebuilt() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LibraryStore(folder: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let future = Data(#"{"version":2,"folders":[],"items":[]}"#.utf8)
        try future.write(to: folder.appendingPathComponent(LibraryStore.indexName))
        let load = store.load()
        #expect(load.setAsideCorruptIndex)
        #expect(try Data(contentsOf: folder.appendingPathComponent(LibraryStore.corruptName)) == future)
    }

    @Test func unreadablePinxelStillHasAnEntry() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("non è uno zip".utf8).write(to: folder.appendingPathComponent("Rotto.pinxel"))
        let load = LibraryStore(folder: folder).load()
        #expect(load.index.item("Rotto.pinxel")?.pixelWidth == 0)
    }

    @Test func ignoresOtherFilesInTheFolder() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data().write(to: folder.appendingPathComponent("note.txt"))
        try Data().write(to: folder.appendingPathComponent(".abc.tmp"))
        #expect(LibraryStore(folder: folder).load().index.items.isEmpty)
    }

    @Test func importCopiesImagesAndPinxelFiles() throws {
        let folder = temporaryFolder()
        let outside = temporaryFolder()
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.removeItem(at: outside) }
        let png = outside.appendingPathComponent("foto.png")
        try ImageCodec.encode(TestImages.quadrants(), type: .png).write(to: png)
        let store = LibraryStore(folder: folder, now: { self.date })
        var index = LibraryIndex()
        let fromPNG = try store.importFile(at: png, into: &index)
        #expect(fromPNG.pixelWidth == 400)
        #expect(FileManager.default.fileExists(atPath: png.path))
        let fromPinxel = try store.importFile(at: store.url(for: fromPNG), into: &index)
        #expect(fromPinxel.file != fromPNG.file)
        let text = outside.appendingPathComponent("a.txt")
        try Data("x".utf8).write(to: text)
        #expect(throws: LibraryError.unsupportedFile("a.txt")) { try store.importFile(at: text, into: &index) }
        #expect(index.items.count == 2)
    }

    @Test func refreshedItemReadsNewSize() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LibraryStore(folder: folder)
        var index = LibraryIndex()
        let item = try store.add(contents(), to: &index)
        // Il documento salvato dall'editor ora è più piccolo (ritaglio).
        let smaller = try CaptureDocumentBuilder.make(image: TestImages.quadrants(width: 100, height: 50), scale: 2, metadata: CaptureMetadata())
        let data = try PinxelArchive.write(document: smaller.document, images: smaller.images, thumbnail: Data([1]), appVersion: "0.1.0")
        try data.write(to: store.url(for: item))
        store.refreshed(item.file, in: &index)
        #expect(index.item(item.file)?.pixelWidth == 100)
        #expect(index.item(item.file)?.pixelHeight == 50)
    }

    @Test func trashRemovesFilesAndEntries() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LibraryStore(folder: folder)
        var index = LibraryIndex()
        let item = try store.add(contents(), to: &index)
        try store.trash([item.file], in: &index)
        #expect(index.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.url(for: item).path))
    }

    @Test func trashUnavailableThrowsAndKeepsEverything() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LibraryStore(folder: folder, fileManager: NoTrashFileManager())
        var index = LibraryIndex()
        let item = try store.add(contents(), to: &index)
        #expect(throws: LibraryError.trashUnavailable) { try store.trash([item.file], in: &index) }
        #expect(index.items.count == 1)
        try store.deletePermanently([item.file], in: &index)
        #expect(index.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.url(for: item).path))
    }

    @Test func unwritableFolderThrows() throws {
        let parent = temporaryFolder()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: parent.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path)
            try? FileManager.default.removeItem(at: parent)
        }
        let store = LibraryStore(folder: parent.appendingPathComponent("Libreria"))
        var index = LibraryIndex()
        #expect(throws: LibraryError.notWritable(parent.appendingPathComponent("Libreria").path)) { try store.add(contents(), to: &index) }
        #expect(index.items.isEmpty)
    }

    @Test func fileForURLOnlyAcceptsDirectChildren() throws {
        let folder = temporaryFolder()
        let store = LibraryStore(folder: folder)
        #expect(store.file(for: folder.appendingPathComponent("a.pinxel")) == "a.pinxel")
        #expect(store.file(for: folder.appendingPathComponent("sub/a.pinxel")) == nil)
        #expect(store.file(for: URL(fileURLWithPath: "/tmp/a.pinxel")) == nil)
    }
}
```

- [ ] **Step 2: Write the failing decision tests**

```swift
import Testing
@testable import Library

struct LibraryOpenDecisionTests {
    @Test func rules() {
        #expect(LibraryOpenDecision.decide(targetAlreadyOpen: true, windowShowsLibraryItem: true) == .focusExisting)
        #expect(LibraryOpenDecision.decide(targetAlreadyOpen: true, windowShowsLibraryItem: false) == .focusExisting)
        #expect(LibraryOpenDecision.decide(targetAlreadyOpen: false, windowShowsLibraryItem: true) == .replaceInWindow)
        // Documento esterno o senza titolo: non si chiude, la cattura va in una finestra nuova.
        #expect(LibraryOpenDecision.decide(targetAlreadyOpen: false, windowShowsLibraryItem: false) == .openNewWindow)
    }
}
```

- [ ] **Step 3: Run to verify they fail**

Run: `python3 <scratchpad>/pt.py Library`
Expected: compile errors (`LibraryStore`, `LibraryOpenDecision` missing).

- [ ] **Step 4: Implement `LibraryOpenDecision.swift`**

```swift
/// Cosa fa il clic su una miniatura (spec §2): mai chiudere un documento che non sta nell'archivio.
public enum LibraryOpenDecision: Equatable, Sendable {
    case focusExisting
    case replaceInWindow
    case openNewWindow

    public static func decide(targetAlreadyOpen: Bool, windowShowsLibraryItem: Bool) -> LibraryOpenDecision {
        if targetAlreadyOpen { return .focusExisting }
        return windowShowsLibraryItem ? .replaceInWindow : .openNewWindow
    }
}
```

- [ ] **Step 5: Implement `LibraryStore.swift`**

```swift
import AppCore
import DocumentModel
import Foundation
import Persistence
import UniformTypeIdentifiers

public enum LibraryError: Error, Equatable {
    case notWritable(String)
    case writeFailed(String)
    case unsupportedFile(String)
    case trashUnavailable
}

public struct LibraryLoad: Sendable {
    public var index: LibraryIndex
    /// `library.json` era rovinato o di una versione futura: messo da parte e ricostruito dai file.
    public var setAsideCorruptIndex: Bool
}

/// Tutto ciò che tocca la cartella dell'archivio. Si usa dal thread principale; solo `thumbnail(at:)` va bene altrove.
public final class LibraryStore {
    public static let indexName = "library.json"
    public static let corruptName = "library.json.rovinato"

    public static var defaultFolder: URL {
        FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pinxel", isDirectory: true)
            .appendingPathComponent("Libreria", isDirectory: true)
    }

    public let folder: URL
    private let fileManager: FileManager
    private let appVersion: String
    private let now: () -> Date

    public init(folder: URL, fileManager: FileManager = .default, appVersion: String = "0.1.0", now: @escaping () -> Date = Date.init) {
        self.folder = folder.standardizedFileURL
        self.fileManager = fileManager
        self.appVersion = appVersion
        self.now = now
    }

    private var indexURL: URL { folder.appendingPathComponent(Self.indexName) }

    public func url(for item: LibraryItem) -> URL {
        folder.appendingPathComponent(item.file)
    }

    public func file(for url: URL) -> String? {
        let standardized = url.standardizedFileURL
        guard standardized.deletingLastPathComponent().path == folder.path else { return nil }
        return standardized.lastPathComponent
    }

    // MARK: Indice

    public func load() -> LibraryLoad {
        var index = LibraryIndex()
        var setAside = false
        if let data = try? Data(contentsOf: indexURL) {
            do {
                index = try Self.decoder.decode(LibraryIndex.self, from: data)
            } catch {
                setAside = true
                let corrupt = folder.appendingPathComponent(Self.corruptName)
                try? fileManager.removeItem(at: corrupt)
                try? fileManager.moveItem(at: indexURL, to: corrupt)
            }
        }
        let reconciled = index.reconciled(withFiles: pinxelFiles()) { makeItem(file: $0) }
        if reconciled != index || setAside { try? save(reconciled) }
        return LibraryLoad(index: reconciled, setAsideCorruptIndex: setAside)
    }

    public func save(_ index: LibraryIndex) throws {
        try ensureFolder()
        do {
            try Self.encoder.encode(index).write(to: indexURL, options: .atomic)
        } catch {
            throw LibraryError.writeFailed(indexURL.path)
        }
    }

    // MARK: Catture

    public func add(_ contents: PinxelFileContents, to index: inout LibraryIndex) throws -> LibraryItem {
        try ensureFolder()
        let baseName = FileNamer.baseName(template: FileNamer.defaultTemplate, date: contents.document.metadata.captureDate)
        let url = FileNamer.uniqueURL(in: folder, baseName: baseName, fileExtension: "pinxel", fileManager: fileManager)
        do {
            let assets = try contents.assetProvider()
            let thumbnail = try Thumbnailer.make(contents.document, assets: assets)
            let data = try PinxelArchive.write(document: contents.document, images: contents.images, thumbnail: thumbnail, appVersion: appVersion)
            try write(data, to: url)
        } catch {
            throw LibraryError.writeFailed(url.path)
        }
        let item = item(file: url.lastPathComponent, document: contents.document, added: now())
        index.add(item)
        return item
    }

    /// Copia nell'archivio un'immagine o un `.pinxel`; l'originale resta com'è.
    public func importFile(at source: URL, into index: inout LibraryIndex) throws -> LibraryItem {
        let name = source.lastPathComponent
        guard let data = try? Data(contentsOf: source) else { throw LibraryError.unsupportedFile(name) }
        if source.pathExtension.lowercased() == "pinxel" {
            guard let document = try? PinxelArchive.readDocument(data) else { throw LibraryError.unsupportedFile(name) }
            try ensureFolder()
            let url = FileNamer.uniqueURL(in: folder, baseName: source.deletingPathExtension().lastPathComponent, fileExtension: "pinxel", fileManager: fileManager)
            do { try write(data, to: url) } catch { throw LibraryError.writeFailed(url.path) }
            let item = item(file: url.lastPathComponent, document: document, added: now())
            index.add(item)
            return item
        }
        guard let contents = try? ImageImport.contents(fromImageData: data) else { throw LibraryError.unsupportedFile(name) }
        return try add(contents, to: &index)
    }

    /// Dopo un salvataggio dall'editor: dimensioni (ritaglio, ridimensiona) rilette dal file.
    public func refreshed(_ file: String, in index: inout LibraryIndex) {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(file), options: .mappedIfSafe),
              let document = try? PinxelArchive.readDocument(data) else { return }
        index.update(file, pixelWidth: document.canvasSize.width, pixelHeight: document.canvasSize.height)
    }

    public func trash(_ files: Set<String>, in index: inout LibraryIndex) throws {
        var removed: Set<String> = []
        defer { index.remove(removed) }
        for file in files.sorted() {
            let url = folder.appendingPathComponent(file)
            guard fileManager.fileExists(atPath: url.path) else {
                removed.insert(file)
                continue
            }
            do {
                try fileManager.trashItem(at: url, resultingItemURL: nil)
                removed.insert(file)
            } catch {
                throw LibraryError.trashUnavailable
            }
        }
    }

    public func deletePermanently(_ files: Set<String>, in index: inout LibraryIndex) throws {
        var removed: Set<String> = []
        defer { index.remove(removed) }
        for file in files.sorted() {
            let url = folder.appendingPathComponent(file)
            if fileManager.fileExists(atPath: url.path) {
                do { try fileManager.removeItem(at: url) } catch { throw LibraryError.writeFailed(url.path) }
            }
            removed.insert(file)
        }
    }

    /// Miniatura PNG salvata nel file; legge senza decodificare le immagini.
    public static func thumbnail(at url: URL) -> Data? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return PinxelArchive.readThumbnail(data)
    }

    // MARK: Interni

    private func ensureFolder() throws {
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw LibraryError.notWritable(folder.path)
        }
        guard fileManager.isWritableFile(atPath: folder.path) else { throw LibraryError.notWritable(folder.path) }
    }

    /// File nascosto e poi spostamento: niente file a metà, e `moveItem` non sovrascrive.
    private func write(_ data: Data, to url: URL) throws {
        let temporary = folder.appendingPathComponent(".\(UUID().uuidString).tmp")
        try data.write(to: temporary, options: .atomic)
        do {
            try fileManager.moveItem(at: temporary, to: url)
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    private func pinxelFiles() -> Set<String> {
        let names = (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []
        return Set(names.filter { !$0.hasPrefix(".") && ($0 as NSString).pathExtension.lowercased() == "pinxel" })
    }

    /// Voce per un file trovato nella cartella; se il file è illeggibile, dimensioni 0 (miniatura di errore).
    private func makeItem(file: String) -> LibraryItem {
        let url = folder.appendingPathComponent(file)
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        let created = (attributes?[.creationDate] as? Date) ?? now()
        if let data = try? Data(contentsOf: url, options: .mappedIfSafe), let document = try? PinxelArchive.readDocument(data) {
            return item(file: file, document: document, added: created)
        }
        return LibraryItem(file: file, added: created, captureDate: created, appName: nil, windowTitle: nil, pixelWidth: 0, pixelHeight: 0)
    }

    private func item(file: String, document: PinxelDocument, added: Date) -> LibraryItem {
        LibraryItem(file: file, added: added, captureDate: document.metadata.captureDate,
                    appName: document.metadata.appName, windowTitle: document.metadata.windowTitle,
                    pixelWidth: document.canvasSize.width, pixelHeight: document.canvasSize.height)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
```

Note: ISO 8601 drops sub-second precision. `saveAndLoadRoundTrip` compares whole indexes; `now()` in that test is `Date.init`, which has fractions. If it fails on dates, round `added` to whole seconds in `add`/`importFile`/`makeItem` (`Date(timeIntervalSince1970: floor(d.timeIntervalSince1970))`) and the capture date likewise when building the item — ledger it as a ruling.

- [ ] **Step 6: Run tests**

Run: `python3 <scratchpad>/pt.py Library`
Expected: all Library tests pass.

- [ ] **Step 7: Commit**

```bash
git add PinxelKit/Sources/Library PinxelKit/Tests/LibraryTests
git commit -m "feat(library): store captures, index and thumbnails on disk"
```

---

### Task 5: Drop an image on the canvas

**Files:**
- Modify: `PinxelKit/Sources/EditorUI/CanvasView.swift`
- Test: `PinxelKit/Tests/EditorUITests/DropImageTests.swift` (new)

**Interfaces:**
- Produces: `CanvasView.insertImage(_ image: NSImage, centeredAt viewPoint: CGPoint?) -> Bool` (public; adds an image annotation without changing the canvas; `nil` = visible centre); `CanvasView` registers for `.png`, `.tiff`, `.fileURL` and accepts drops of images (`draggingEntered` returns `.copy` when an image can be read and the session is not read-only; `performDragOperation` calls `insertImage` at the drop point).

- [ ] **Step 1: Write the failing test**

```swift
import AppKit
import DocumentModel
import PinxelTestSupport
import Rendering
import Testing
@testable import EditorUI

@MainActor
struct DropImageTests {
    private func makeCanvas(readOnly: Bool = false) -> CanvasView {
        let undo = UndoManager()
        undo.groupsByEvent = false
        let session = EditorSession(document: TestDocuments.document(annotations: [], size: PixelSize(width: 400, height: 300), scale: 1),
                                    assets: DictionaryAssetProvider([TestDocuments.background: TestImages.quadrants()]),
                                    undoManager: undo, isReadOnly: readOnly)
        let canvas = CanvasView(model: EditorModel(session: session))
        canvas.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        canvas.needsLayout = true
        canvas.layoutSubtreeIfNeeded()
        return canvas
    }

    @Test func insertedImageBecomesAnAnnotationAndKeepsTheCanvas() throws {
        let canvas = makeCanvas()
        let image = NSImage(cgImage: TestImages.solid(width: 40, height: 20, red: 1, green: 0, blue: 0), size: NSSize(width: 40, height: 20))
        #expect(canvas.insertImage(image, centeredAt: nil))
        let session = canvas.model.session
        #expect(session.document.imageSize == PixelSize(width: 400, height: 300))
        let annotation = try #require(session.document.annotations.last)
        guard case .image(let data) = annotation.kind else { Issue.record("not an image"); return }
        #expect(data.rect.width == 40 && data.rect.height == 20)
        #expect(session.selection == [annotation.id])
    }

    @Test func readOnlyRefusesTheImage() {
        let canvas = makeCanvas(readOnly: true)
        let image = NSImage(cgImage: TestImages.solid(width: 4, height: 4, red: 1, green: 0, blue: 0), size: NSSize(width: 4, height: 4))
        #expect(!canvas.insertImage(image, centeredAt: nil))
        #expect(canvas.model.session.document.annotations.isEmpty)
    }

    @Test func canvasAcceptsImageDrags() {
        let types = makeCanvas().registeredDraggedTypes
        #expect(types.contains(.fileURL) && types.contains(.png))
    }
}
```

(If `CanvasView` exposes its model under another name than `model`, use that; check `CanvasView.init(model:)`.)

- [ ] **Step 2: Run to verify it fails**

Run: `python3 <scratchpad>/pt.py DropImageTests`
Expected: compile error, `insertImage` not found.

- [ ] **Step 3: Implement**

Refactor `pasteImage(adaptCanvas:)` so the non-adapting branch and the new public method share one helper:

```swift
    /// Un'immagine trascinata o incollata sopra la cattura, senza cambiarne le dimensioni; `viewPoint` è il centro
    /// (in coordinate della vista), `nil` = centro della parte visibile.
    @discardableResult
    public func insertImage(_ image: NSImage, centeredAt viewPoint: CGPoint?) -> Bool {
        guard !session.isReadOnly,
              let original = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let cgImage = ImagePlacement.fitting(original, maxSide: PinxelDocument.maxImageSide) else { return false }
        let document = session.document
        let placement = ImagePlacement.place(
            pixelSize: CGSize(width: cgImage.width, height: cgImage.height),
            imageScale: PixelDensity.scale(pixelWidth: original.width, pointWidth: image.size.width),
            documentScale: document.scale,
            center: viewPoint.map { documentPoint(fromView: $0) } ?? visibleDocumentCenter(),
            imageSize: document.imageSize,
            adaptCanvas: false
        )
        guard let asset = session.assets.add(cgImage) else { return false }
        let annotation = Annotation(kind: .image(PlacedImageData(rect: placement.rect, asset: asset)), style: Style(stroke: nil, lineWidth: 0))
        session.perform(AddAnnotations([annotation], name: "Inserisci immagine"))
        session.selection = [annotation.id]
        return true
    }
```

In `pasteImage(adaptCanvas:)`, when `!adaptCanvas`, return `insertImage(image, centeredAt: nil)` (keep the paste undo name by passing it if the existing tests assert "Incolla immagine": add a `name: String = "Inserisci immagine"` parameter and pass "Incolla immagine" from paste).

Drag destination (in `CanvasView`; call `registerForDraggedTypes([.fileURL, .png, .tiff])` in `init`):

```swift
    private func droppedImage(_ sender: NSDraggingInfo) -> NSImage? {
        let pasteboard = sender.draggingPasteboard
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let url = urls.first, let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage(pasteboard: pasteboard)
    }

    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        !session.isReadOnly && NSImage.canInit(with: sender.draggingPasteboard) ? .copy : []
    }

    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let image = droppedImage(sender) else { return false }
        window?.makeFirstResponder(self)
        return insertImage(image, centeredAt: convert(sender.draggingLocation, from: nil))
    }
```

A `.pinxel` dragged from the strip arrives as a PNG file URL (Task 7 writes the rendered PNG), so `NSImage(contentsOf:)` works.

- [ ] **Step 4: Run tests**

Run: `python3 <scratchpad>/pt.py EditorUI`
Expected: all EditorUI tests pass (including `PasteImageTests`).

- [ ] **Step 5: Commit**

```bash
git add PinxelKit/Sources/EditorUI/CanvasView.swift PinxelKit/Tests/EditorUITests/DropImageTests.swift
git commit -m "feat(editor): drop an image on the canvas to place it"
```

---

### Task 6: Captures go to the library

**Files:**
- Create: `App/Pinxel/Library/LibraryModel.swift`
- Modify: `App/Pinxel/AppEnvironment.swift`, `App/Pinxel/PostCapture/PostCaptureActions.swift`, `App/Pinxel/Document/DocumentOpener.swift`, `App/Pinxel/Document/PinxelFileDocument.swift`, `App/Pinxel/PostCapture/Notifier.swift`, `App/Pinxel/AppDelegate.swift`

**Interfaces:**
- Consumes: `LibraryStore`, `LibraryIndex`, `LibraryError` (Tasks 2-4).
- Produces:
  - `extension Notification.Name { static let pinxelDocumentDidSave }` (object: the saved file `URL`).
  - `@MainActor @Observable final class LibraryModel` with `private(set) var index: LibraryIndex`, `private(set) var thumbnailRevision: [String: Date]` (file → modification date, bumps the view), `let store: LibraryStore`, `init(store: LibraryStore, notifier: Notifier)`, `func reload()`, `func add(_ contents: PinxelFileContents) throws -> URL`, `func importFiles(_ urls: [URL])`, `func move(_ files: Set<String>, to folder: UUID?)`, `func addTag(_ tag: String, to files: Set<String>)`, `func removeTag(_ tag: String, from files: Set<String>)`, `func createFolder(named: String) -> LibraryFolder?`, `func renameFolder(_ id: UUID, to name: String) -> Bool`, `func deleteFolder(_ id: UUID)`, `func delete(_ files: Set<String>)`, `func file(for url: URL) -> String?`, `func url(for item: LibraryItem) -> URL`.
  - `DocumentOpener.open(url: URL)` (opens through `NSDocumentController`, regular activation policy).
  - `AppEnvironment.library: LibraryModel`.

- [ ] **Step 1: Library error messages in `Notifier`**

Add cases to `Notifier.message(for:)`:

```swift
        case LibraryError.notWritable(let path): "Impossibile scrivere nella libreria (\(path)). La cattura resta fuori dalla libreria."
        case LibraryError.writeFailed(let path): "Salvataggio nella libreria non riuscito: \(path)."
        case LibraryError.unsupportedFile(let name): "«\(name)» non è un'immagine né un documento Pinxel."
        case LibraryError.trashUnavailable: "Il Cestino non è disponibile per questi file."
```

and `import Library` at the top.

- [ ] **Step 2: Save notification in `PinxelFileDocument`**

```swift
extension Notification.Name {
    /// Un documento è stato scritto su disco; `object` è il suo URL. La libreria aggiorna miniatura e dimensioni.
    static let pinxelDocumentDidSave = Notification.Name("com.degiorgi.pinxel.documentDidSave")
}
```

In `save(to:ofType:for:completionHandler:)` wrap the completion handler:

```swift
        super.save(to: url, ofType: typeName, for: saveOperation) { error in
            if error == nil { NotificationCenter.default.post(name: .pinxelDocumentDidSave, object: url) }
            completionHandler(error)
        }
```

- [ ] **Step 3: `DocumentOpener.open(url:)`**

```swift
    /// Apre un file (per esempio una cattura della libreria): si salva da solo dove sta.
    static func open(url: URL, completion: ((NSDocument?) -> Void)? = nil) {
        NSApp.setActivationPolicy(.regular)
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { document, _, error in
            if let error { NSApp.presentError(error) }
            NSApp.activate()
            completion?(document)
        }
    }
```

- [ ] **Step 4: `LibraryModel`**

```swift
import AppKit
import Library
import Observation
import Persistence

/// L'archivio condiviso da tutte le finestre. Ogni modifica si salva subito in `library.json`.
@MainActor
@Observable
final class LibraryModel {
    private(set) var index = LibraryIndex()
    /// Data di modifica dei file noti: quando cambia, la miniatura si rilegge.
    private(set) var thumbnailRevision: [String: Date] = [:]

    @ObservationIgnored let store: LibraryStore
    @ObservationIgnored private let notifier: Notifier
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(store: LibraryStore, notifier: Notifier) {
        self.store = store
        self.notifier = notifier
        reload()
        observers.append(NotificationCenter.default.addObserver(forName: .pinxelDocumentDidSave, object: nil, queue: .main) { [weak self] note in
            guard let url = note.object as? URL else { return }
            MainActor.assumeIsolated { self?.documentSaved(at: url) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        })
    }

    func reload() {
        let load = store.load()
        if load.setAsideCorruptIndex {
            notifier.info("L'indice della libreria era danneggiato: ricostruito dai file. Cartelle ed etichette sono andate perse; la copia è in \(LibraryStore.corruptName).")
        }
        if load.index != index { index = load.index }
        refreshRevisions()
    }

    func add(_ contents: PinxelFileContents) throws -> URL {
        let item = try store.add(contents, to: &index)
        persist()
        refreshRevisions()
        return store.url(for: item)
    }

    func importFiles(_ urls: [URL]) {
        for url in urls {
            do { _ = try store.importFile(at: url, into: &index) } catch { notifier.failure(error) }
        }
        persist()
        refreshRevisions()
    }

    func move(_ files: Set<String>, to folder: UUID?) { index.move(files, to: folder); persist() }
    func addTag(_ tag: String, to files: Set<String>) { index.addTag(tag, to: files); persist() }
    func removeTag(_ tag: String, from files: Set<String>) { index.removeTag(tag, from: files); persist() }
    func deleteFolder(_ id: UUID) { index.deleteFolder(id); persist() }

    func createFolder(named name: String) -> LibraryFolder? {
        do {
            let folder = try index.createFolder(named: name)
            persist()
            return folder
        } catch {
            present(error)
            return nil
        }
    }

    func renameFolder(_ id: UUID, to name: String) -> Bool {
        do {
            try index.renameFolder(id, to: name)
            persist()
            return true
        } catch {
            present(error)
            return false
        }
    }

    /// Chiude le finestre aperte su queste catture, poi le sposta nel Cestino (o, se non c'è, chiede e cancella).
    func delete(_ files: Set<String>) {
        guard !files.isEmpty else { return }
        for document in NSDocumentController.shared.documents {
            if let url = document.fileURL, let file = store.file(for: url), files.contains(file) { document.close() }
        }
        do {
            try store.trash(files, in: &index)
        } catch LibraryError.trashUnavailable {
            let alert = NSAlert()
            alert.messageText = files.count == 1 ? "Eliminare definitivamente la cattura?" : "Eliminare definitivamente \(files.count) catture?"
            alert.informativeText = "Il Cestino non è disponibile: non si potranno recuperare."
            alert.addButton(withTitle: "Elimina")
            alert.addButton(withTitle: "Annulla")
            if alert.runModal() == .alertFirstButtonReturn {
                do { try store.deletePermanently(files, in: &index) } catch { notifier.failure(error) }
            }
        } catch {
            notifier.failure(error)
        }
        persist()
        refreshRevisions()
    }

    func file(for url: URL) -> String? { store.file(for: url).flatMap { index.item($0) != nil ? $0 : nil } }
    func url(for item: LibraryItem) -> URL { store.url(for: item) }

    private func documentSaved(at url: URL) {
        guard let file = store.file(for: url) else { return }
        if index.item(file) == nil {
            reload()
        } else {
            store.refreshed(file, in: &index)
            persist()
            refreshRevisions()
        }
    }

    private func persist() {
        do { try store.save(index) } catch { notifier.failure(error) }
    }

    private func refreshRevisions() {
        var next: [String: Date] = [:]
        for item in index.items {
            let date = (try? store.url(for: item).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            next[item.file] = date
        }
        if next != thumbnailRevision { thumbnailRevision = next }
    }

    private func present(_ error: Error) {
        let alert = NSAlert()
        switch error {
        case LibraryIndexError.emptyName: alert.messageText = "Il nome della cartella non può essere vuoto."
        case LibraryIndexError.duplicateName: alert.messageText = "Esiste già una cartella con questo nome."
        default: alert.messageText = Notifier.message(for: error)
        }
        alert.runModal()
    }
}
```

- [ ] **Step 5: Wire `AppEnvironment` and `PostCaptureActions`**

In `AppEnvironment`:

```swift
    @ObservationIgnored let library: LibraryModel
```

created in `init` before `PostCaptureActions`:

```swift
        let libraryFolder: URL
        if let i = arguments.firstIndex(of: "-PinxelLibraryFolder"), i + 1 < arguments.count {
            libraryFolder = URL(fileURLWithPath: arguments[i + 1], isDirectory: true)
        } else if isUITesting {
            // I test non devono mai scrivere nella libreria vera.
            libraryFolder = FileManager.default.temporaryDirectory.appendingPathComponent("pinxel-uitest-library-\(UUID().uuidString)", isDirectory: true)
        } else {
            libraryFolder = LibraryStore.defaultFolder
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        library = LibraryModel(store: LibraryStore(folder: libraryFolder, appVersion: version), notifier: notifier)
        let actions = PostCaptureActions(notifier: notifier, library: library)
```

Replace `lastCapture: PinxelFileContents?` with:

```swift
    /// L'ultima cattura di questa sessione: il file della libreria, o i contenuti se non è entrata nella libreria.
    private(set) var lastCapture: LastCapture?

    enum LastCapture {
        case file(URL)
        case contents(PinxelFileContents)
    }
```

`actions.onCapture = { [unowned self] in self.lastCapture = $0 }` with `onCapture: ((LastCapture) -> Void)?`, and:

```swift
    func openLastCapture() {
        switch lastCapture {
        case .file(let url): DocumentOpener.open(url: url)
        case .contents(let contents): DocumentOpener.open(contents)
        case nil: break
        }
    }
```

(`MenuContent.swift` keeps `.disabled(environment.lastCapture == nil)`; make `LastCapture` not need `Equatable` by comparing with `== nil` on the optional — use `environment.lastCapture == nil` only if it compiles; otherwise add `var hasLastCapture: Bool { lastCapture != nil }` via `if case`.)

In `PostCaptureActions`: add `private let library: LibraryModel`, init parameter `library:`, and in `perform`:

```swift
    func perform(_ plan: PostCapturePlan, contents: PinxelFileContents, image: CGImage, settings: CaptureSettings) {
        // Prima di tutto nell'archivio; se non riesce, la cattura segue la via di sempre.
        var libraryURL: URL?
        do {
            libraryURL = try library.add(contents)
        } catch {
            notifier.failure(error)
        }
        onCapture?(libraryURL.map { .file($0) } ?? .contents(contents))
        ...
```

and pass `libraryURL` down so every `DocumentOpener.open(contents)` in `run` and in the preview's `onOpen` becomes:

```swift
    private func openEditor(_ contents: PinxelFileContents, libraryURL: URL?) {
        if let libraryURL { DocumentOpener.open(url: libraryURL) } else { DocumentOpener.open(contents) }
    }
```

The auto-save failure fallback (`case .autoSave` catch) also uses `openEditor`.

- [ ] **Step 6: Build and run the package tests**

Run: `xcodegen generate && xcodebuild -project Pinxel.xcodeproj -scheme Pinxel -configuration Debug build 2>&1 | tail -3` and `python3 <scratchpad>/pt.py`
Expected: `** BUILD SUCCEEDED **`; all package tests pass.

- [ ] **Step 7: Run the existing capture UI tests**

Run: `caffeinate -dimsu xcodebuild -project Pinxel.xcodeproj -scheme Pinxel -destination 'platform=macOS' test -only-testing:PinxelUITests/CaptureFlowUITests 2>&1 | tail -15`
Expected: tests pass (the two menu-bar tests may be skipped on this Mac); `~/Pictures/Pinxel/Libreria` is not created by them (`ls ~/Pictures/Pinxel/Libreria` before/after shows no new files).

- [ ] **Step 8: Commit**

```bash
git add App/Pinxel PinxelKit project.yml
git commit -m "feat(library): every capture is kept in the library and opened from there"
```

---

### Task 7: The strip in the editor

**Files:**
- Create: `App/Pinxel/Library/LibraryStrip.swift`, `App/Pinxel/Library/LibraryThumbnailView.swift`, `App/Pinxel/Library/ThumbnailCache.swift`, `App/Pinxel/Library/LibraryOpener.swift`
- Modify: `App/Pinxel/Editor/EditorView.swift`, `App/Pinxel/EditorCommands.swift`, `App/Pinxel/Editor/EditorWindowController.swift`

**Interfaces:**
- Consumes: `LibraryModel` (Task 6), `LibraryFilter`, `FolderScope`, `LibraryOpenDecision` (Tasks 3-4), `CanvasView` drop (Task 5), `DocumentOpener.open(url:completion:)`.
- Produces: `@Observable final class LibraryStripState { var filter = LibraryFilter(); var selection: Set<String> = []; var anchor: String? }` (one per `EditorWindowController`); `LibraryStrip(library:state:currentFile:open:)`; `LibraryOpener.open(_ item: LibraryItem, from window: NSWindow?, newWindow: Bool)`; `UserDefaults` key `libraryStripVisible`.

- [ ] **Step 1: `ThumbnailCache`**

```swift
import AppKit

/// Miniature lette dai `.pinxel`, una per file e data di modifica; letture fuori dal thread principale.
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()

    private func key(_ url: URL, _ revision: Date) -> NSString {
        "\(url.path)|\(revision.timeIntervalSinceReferenceDate)" as NSString
    }

    func cached(_ url: URL, revision: Date) -> NSImage? {
        cache.object(forKey: key(url, revision))
    }

    func load(_ url: URL, revision: Date) async -> NSImage? {
        if let image = cached(url, revision: revision) { return image }
        let data = await Task.detached(priority: .utility) { LibraryStore.thumbnail(at: url) }.value
        guard let data, let image = NSImage(data: data) else { return nil }
        cache.setObject(image, forKey: key(url, revision))
        return image
    }
}
```

(`import Library` for `LibraryStore`.)

- [ ] **Step 2: `LibraryOpener`**

```swift
import AppKit
import Library

@MainActor
enum LibraryOpener {
    /// Clic su una miniatura: porta avanti la finestra che la mostra già, la sostituisce nella finestra se questa mostra una
    /// cattura dell'archivio (già salvata), altrimenti apre una finestra nuova.
    static func open(_ item: LibraryItem, from window: NSWindow?, newWindow: Bool = false) {
        let library = AppEnvironment.shared.library
        let url = library.url(for: item).standardizedFileURL
        let existing = NSDocumentController.shared.documents.first { $0.fileURL?.standardizedFileURL == url }
        let current = window.flatMap { NSDocumentController.shared.document(for: $0) }
        let showsLibraryItem = current?.fileURL.flatMap { library.file(for: $0) } != nil
        let decision = newWindow && existing == nil ? .openNewWindow
            : LibraryOpenDecision.decide(targetAlreadyOpen: existing != nil, windowShowsLibraryItem: showsLibraryItem)
        switch decision {
        case .focusExisting:
            existing?.showWindows()
        case .openNewWindow:
            DocumentOpener.open(url: url)
        case .replaceInWindow:
            guard let current, let frame = window?.frame else { return DocumentOpener.open(url: url) }
            // Il documento è nell'archivio: si salva dove sta, poi la nuova cattura prende la stessa cornice.
            current.autosave(withImplicitCancellability: false) { _ in
                MainActor.assumeIsolated {
                    current.close()
                    DocumentOpener.open(url: url) { document in
                        document?.windowControllers.first?.window?.setFrame(frame, display: true)
                    }
                }
            }
        }
    }
}
```

Note: `EditorWindowController` sets `shouldCascadeWindows = true` and calls `window.center()`; `setFrame` after open overrides that. If the window visibly jumps, open with `display: false`, set the frame, then `showWindows()` — ledger as a ruling if changed.

- [ ] **Step 3: `LibraryThumbnailView`**

```swift
import AppKit
import Library
import SwiftUI

/// Una miniatura: immagine letta quando entra in vista, bordo di accento se è quella aperta, contorno se selezionata.
struct LibraryThumbnailView: View {
    let item: LibraryItem
    let url: URL
    let revision: Date
    let isCurrent: Bool
    let isSelected: Bool
    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else if failed {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary)
            } else {
                Color.secondary.opacity(0.12)
            }
        }
        .frame(width: 112, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(isCurrent ? Color.accentColor : isSelected ? Color.accentColor.opacity(0.5) : Color(nsColor: .separatorColor),
                              lineWidth: isCurrent || isSelected ? 2.5 : 0.5)
        }
        .help([item.appName, item.windowTitle].compactMap { $0 }.joined(separator: " — "))
        .accessibilityElement()
        .accessibilityLabel(item.file)
        .accessibilityIdentifier("pinxel.library.item")
        .task(id: revision) {
            image = await ThumbnailCache.shared.load(url, revision: revision)
            failed = image == nil
        }
    }
}
```

- [ ] **Step 4: `LibraryStrip`**

```swift
import AppKit
import Library
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class LibraryStripState {
    var filter = LibraryFilter()
    var selection: Set<String> = []
    /// Ultima miniatura cliccata senza ⇧: punto di partenza per ⇧-clic.
    var anchor: String?
}

/// Carosello in fondo all'editor: filtri sopra, miniature dalla più nuova (spec §2).
struct LibraryStrip: View {
    let library: LibraryModel
    @Bindable var state: LibraryStripState
    /// File della cattura aperta in questa finestra, se è nell'archivio.
    let currentFile: String?
    let open: (LibraryItem, _ newWindow: Bool) -> Void
    @FocusState private var focused: Bool

    private var items: [LibraryItem] { state.filter.apply(to: library.index) }

    var body: some View {
        VStack(spacing: 6) {
            filterBar
            if items.isEmpty {
                Text(library.index.items.isEmpty ? "Le tue catture compariranno qui." : "Nessuna cattura corrisponde al filtro.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 8) {
                        ForEach(items) { item in thumbnail(item) }
                    }
                    .padding(.horizontal, 12)
                }
                .scrollIndicators(.automatic)
            }
        }
        .padding(.vertical, 6)
        .frame(height: 110)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onDeleteCommand { library.delete(state.selection) }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            importDropped(providers)
            return true
        }
        .accessibilityIdentifier("pinxel.library.strip")
    }

    private func thumbnail(_ item: LibraryItem) -> some View {
        let url = library.url(for: item)
        return LibraryThumbnailView(item: item, url: url, revision: library.thumbnailRevision[item.file] ?? .distantPast,
                                    isCurrent: item.file == currentFile, isSelected: state.selection.contains(item.file))
            .onTapGesture { click(item) }
            .onDrag { dragProvider(for: item, url: url) }
            .contextMenu { contextMenu(for: item) }
    }

    // MARK: Selezione e clic

    private func click(_ item: LibraryItem) {
        focused = true
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if state.selection.contains(item.file) { state.selection.remove(item.file) } else { state.selection.insert(item.file) }
            state.anchor = item.file
        } else if flags.contains(.shift), let anchor = state.anchor,
                  let a = items.firstIndex(where: { $0.file == anchor }), let b = items.firstIndex(where: { $0.file == item.file }) {
            state.selection = Set(items[min(a, b)...max(a, b)].map(\.file))
        } else {
            state.selection = [item.file]
            state.anchor = item.file
            open(item, false)
        }
    }

    /// Il menu agisce sulla selezione se la contiene, altrimenti solo sulla miniatura.
    private func targets(_ item: LibraryItem) -> Set<String> {
        state.selection.contains(item.file) ? state.selection : [item.file]
    }

    // MARK: Barra dei filtri

    private var filterBar: some View {
        HStack(spacing: 8) {
            Menu(folderTitle) {
                Picker("Cartella", selection: $state.filter.folder) {
                    Text("Tutte").tag(FolderScope.all)
                    Text("Senza cartella").tag(FolderScope.unfiled)
                    ForEach(sortedFolders) { folder in Text(folder.name).tag(FolderScope.folder(folder.id)) }
                }
                .pickerStyle(.inline)
                Divider()
                Button("Nuova cartella…") {
                    if let name = askName(title: "Nuova cartella", initial: ""), let folder = library.createFolder(named: name) {
                        state.filter.folder = .folder(folder.id)
                    }
                }
                if case .folder(let id) = state.filter.folder, let folder = library.index.folder(id) {
                    Button("Rinomina cartella…") {
                        if let name = askName(title: "Rinomina cartella", initial: folder.name) { _ = library.renameFolder(id, to: name) }
                    }
                    Button("Elimina cartella") {
                        library.deleteFolder(id)
                        state.filter.folder = .all
                    }
                }
            }
            .fixedSize()
            .accessibilityIdentifier("pinxel.library.folderMenu")
            Menu(state.filter.tag.map { "#\($0)" } ?? "Etichetta") {
                Picker("Etichetta", selection: $state.filter.tag) {
                    Text("Tutte").tag(String?.none)
                    ForEach(library.index.allTags, id: \.self) { tag in Text(tag).tag(Optional(tag)) }
                }
                .pickerStyle(.inline)
            }
            .fixedSize()
            TextField("Cerca", text: $state.filter.text)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)
            Spacer()
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
    }

    private var sortedFolders: [LibraryFolder] {
        library.index.folders.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var folderTitle: String {
        switch state.filter.folder {
        case .all: "Tutte le cartelle"
        case .unfiled: "Senza cartella"
        case .folder(let id): library.index.folder(id)?.name ?? "Tutte le cartelle"
        }
    }

    // MARK: Menu contestuale

    @ViewBuilder private func contextMenu(for item: LibraryItem) -> some View {
        let files = targets(item)
        Button("Copia") { copy(files) }
        Button("Apri in una nuova finestra") { for target in items where files.contains(target.file) { open(target, true) } }
        Menu("Sposta in") {
            Button("Senza cartella") { library.move(files, to: nil) }
            ForEach(sortedFolders) { folder in Button(folder.name) { library.move(files, to: folder.id) } }
            Divider()
            Button("Nuova cartella…") {
                if let name = askName(title: "Nuova cartella", initial: ""), let folder = library.createFolder(named: name) {
                    library.move(files, to: folder.id)
                }
            }
        }
        Menu("Etichette") {
            ForEach(library.index.allTags, id: \.self) { tag in
                let all = files.allSatisfy { file in library.index.item(file)?.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame } ?? false }
                Toggle(tag, isOn: Binding(get: { all }, set: { on in on ? library.addTag(tag, to: files) : library.removeTag(tag, from: files) }))
            }
            Divider()
            Button("Nuova etichetta…") {
                if let tag = askName(title: "Nuova etichetta", initial: "") { library.addTag(tag, to: files) }
            }
        }
        Button("Mostra nel Finder") {
            NSWorkspace.shared.activateFileViewerSelecting(items.filter { files.contains($0.file) }.map { library.url(for: $0) })
        }
        Divider()
        Button("Elimina", role: .destructive) { library.delete(files) }
    }

    // MARK: Appunti, trascinamenti

    private func copy(_ files: Set<String>) {
        let images = items.filter { files.contains($0.file) }.compactMap { renderedPNG(library.url(for: $0)) }
        guard !images.isEmpty else { return NSSound.beep() }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(images.compactMap { NSImage(data: $0) })
    }

    /// PNG composito (annotazioni comprese) in un file temporaneo con il nome della cattura: Finder, altre app e tela.
    private func dragProvider(for item: LibraryItem, url: URL) -> NSItemProvider {
        guard let png = renderedPNG(url),
              let file = try? TemporaryFiles.uniqueURL(fileName: (item.file as NSString).deletingPathExtension + ".png"),
              (try? png.write(to: file)) != nil else { return NSItemProvider() }
        return NSItemProvider(contentsOf: file) ?? NSItemProvider()
    }

    private func renderedPNG(_ url: URL) -> Data? {
        guard let data = try? Data(contentsOf: url), let contents = try? PinxelArchive.read(data),
              let assets = try? contents.assetProvider(),
              let image = try? DocumentRenderer().renderImage(contents.document, assets: assets) else { return nil }
        return try? ImageCodec.encode(image, type: .png)
    }

    private func importDropped(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in library.importFiles([url]) }
            }
        }
    }

    private func askName(title: String, initial: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        let field = NSTextField(string: initial)
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Annulla")
        alert.window.initialFirstResponder = field
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }
}
```

Imports also needed: `AppCore` (`TemporaryFiles`), `Persistence` (`PinxelArchive`, `ImageCodec`), `Rendering` (`DocumentRenderer`). The drag from the strip should not be accepted by the strip's own `.onDrop` as an import: the provider for strip drags is a temporary PNG; guard `importDropped` by ignoring URLs inside `NSTemporaryDirectory()` (the folder used by `TemporaryFiles`).

- [ ] **Step 5: Put the strip in `EditorView` and the menu item**

`EditorWindowController` creates `let stripState = LibraryStripState()` and passes it to `EditorView(model:stripState:document:)`, where `document: () -> NSDocument?` returns `NSDocumentController.shared.document(for: window)`; simplest is to pass the `fileURL` lookup as a closure. `EditorView`:

```swift
    @AppStorage("libraryStripVisible") private var stripVisible = true
    let stripState: LibraryStripState
    let currentURL: () -> URL?

    var body: some View {
        VStack(spacing: 0) {
            CanvasRepresentable(model: model)
                .frame(minWidth: 320, minHeight: 240)
                .overlay(alignment: .bottomTrailing) { /* ZoomControls + CaptureDragHandle, unchanged */ }
            if stripVisible {
                LibraryStrip(library: AppEnvironment.shared.library, state: stripState,
                             currentFile: currentURL().flatMap { AppEnvironment.shared.library.file(for: $0) }) { item, newWindow in
                    LibraryOpener.open(item, from: NSApp.keyWindow, newWindow: newWindow)
                }
            }
        }
        // …modifiers unchanged; add to the toolbar:
        //   ToolbarItem(placement: .primaryAction) {
        //       Button { stripVisible.toggle() } label: { Label("Carosello", systemImage: "rectangle.bottomthird.inset.filled") }
        //           .help("Mostra o nascondi il carosello delle catture")
        //   }
    }
```

Because `ZoomControls` stay in the canvas overlay, they now sit above the strip automatically.

In `EditorCommands`, inside `CommandGroup(after: .toolbar)` before the zoom group:

```swift
            Button(UserDefaults.standard.object(forKey: "libraryStripVisible") as? Bool ?? true ? "Nascondi carosello" : "Mostra carosello") {
                let current = UserDefaults.standard.object(forKey: "libraryStripVisible") as? Bool ?? true
                UserDefaults.standard.set(!current, forKey: "libraryStripVisible")
            }
            .keyboardShortcut("l", modifiers: [.command, .control])
            Divider()
```

⌥⌘L is already Sblocca (unlock selection), so the strip uses **⌃⌘L**; the spec is updated accordingly.

`currentURL` must refresh after an autosave turns an untitled document into a file: `EditorView` observes nothing about `fileURL`, so `LibraryStrip` reads it on each render; renders happen on library changes (save notification bumps `thumbnailRevision`), which is enough.

- [ ] **Step 6: Build and try it**

Run: `xcodegen generate && xcodebuild -project Pinxel.xcodeproj -scheme Pinxel -configuration Debug build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`. Launch the debug app with `-PinxelLibraryFolder <scratchpad>/lib`, make two captures, check: strip shows both, newest first; click swaps; ⌘-click selects; context menu moves to a new folder; folder menu filters.

- [ ] **Step 7: Commit**

```bash
git add App/Pinxel
git commit -m "feat(library): thumbnail strip under the editor canvas"
```

---

### Task 8: UI tests, manual checklist, docs

**Files:**
- Create: `App/PinxelUITests/LibraryUITests.swift`, `docs/manual-tests/library.md`
- Modify: `docs/superpowers/specs/2026-10-19-pinxel-library-design.md` (status, rulings), `App/Pinxel/AppDelegate.swift` (if a launch hook is needed)

**Interfaces:**
- Consumes: launch args `-PinxelUITestFakeCapture`, `-PinxelUITestCaptureOnLaunch`, `-PinxelUITestPostCapture`, `-PinxelLibraryFolder`; accessibility ids `pinxel.library.strip`, `pinxel.library.item`, `pinxel.library.folderMenu`, `pinxel.editor.canvas`.

- [ ] **Step 1: Write the UI tests**

```swift
import AppKit
import XCTest

final class LibraryUITests: XCTestCase {
    private var folder: URL!

    override func setUp() {
        continueAfterFailure = false
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("pinxel-uitest-lib-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-PinxelUITestFakeCapture", "-PinxelLibraryFolder", folder.path] + extra
        app.launch()
        return app
    }

    func testCaptureLandsInTheGivenLibraryAndInTheStrip() {
        let app = launch(["-PinxelUITestCaptureOnLaunch"])
        XCTAssertTrue(app.images["pinxel.editor.canvas"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.otherElements["pinxel.library.strip"].waitForExistence(timeout: 5) || app.groups["pinxel.library.strip"].exists)
        let items = app.descendants(matching: .any).matching(identifier: "pinxel.library.item")
        XCTAssertEqual(items.count, 1)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        XCTAssertEqual(files.filter { $0.hasSuffix(".pinxel") }.count, 1)
        XCTAssertTrue(files.contains("library.json"))
        app.terminate()
    }

    func testClipboardOnlyCaptureStillEntersTheLibrary() {
        let app = launch(["-PinxelUITestCaptureOnLaunch", "-PinxelUITestPostCapture", "clipboardOnly"])
        let deadline = Date().addingTimeInterval(15)
        var files: [String] = []
        while Date() < deadline {
            files = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasSuffix(".pinxel") }
            if !files.isEmpty { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertEqual(files.count, 1)
        app.terminate()
    }

    func testClickingAThumbnailReplacesTheCaptureInTheWindow() {
        // Prima esecuzione: due catture nella stessa libreria.
        var app = launch(["-PinxelUITestCaptureOnLaunch"])
        XCTAssertTrue(app.images["pinxel.editor.canvas"].waitForExistence(timeout: 15))
        app.terminate()
        app = launch(["-PinxelUITestCaptureOnLaunch"])
        XCTAssertTrue(app.images["pinxel.editor.canvas"].waitForExistence(timeout: 15))
        app.activate()
        let items = app.descendants(matching: .any).matching(identifier: "pinxel.library.item")
        XCTAssertEqual(items.count, 2)
        let windowTitle = app.windows.firstMatch.title
        items.element(boundBy: 1).click()
        let changed = NSPredicate(format: "title != %@", windowTitle)
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: changed, object: app.windows.firstMatch)], timeout: 5), .completed)
        XCTAssertEqual(app.windows.count, 1)
        app.terminate()
    }
}
```

The fake capture always uses the same capture date only if `FakeCaptureEngine` fixes it; if both captures get the same name, the second becomes "… 2.pinxel", and titles still differ.

- [ ] **Step 2: Run them**

Run: `caffeinate -dimsu xcodebuild -project Pinxel.xcodeproj -scheme Pinxel -destination 'platform=macOS' test -only-testing:PinxelUITests/LibraryUITests 2>&1 | tail -20`
Expected: 3 tests pass. If the strip's element type differs (`otherElements` vs `groups`), use `app.descendants(matching: .any)["pinxel.library.strip"]`.

- [ ] **Step 3: Manual checklist `docs/manual-tests/library.md`**

```markdown
# Prove a mano — Libreria

Avvia l'app normale (libreria in `~/Pictures/Pinxel/Libreria`).

| # | Prova | Atteso |
|---|-------|--------|
| L1 | Cattura un'area con "Solo appunti", poi Riapri l'ultima cattura | Si apre il file della libreria; la miniatura c'è |
| L2 | Annota, chiudi la finestra | Nessuna domanda di salvataggio; la miniatura mostra l'annotazione |
| L3 | Ritaglia una cattura, chiudi, riapri Pinxel | Dimensioni e miniatura aggiornate |
| L4 | Clic su un'altra miniatura | Sostituita nella stessa finestra, stessa posizione |
| L5 | Nuovo (⌘N), disegna, clic su una miniatura | Si apre una finestra nuova; il documento nuovo resta aperto |
| L6 | ⌘-clic su tre miniature, clic destro ▸ Sposta in ▸ Nuova cartella… "Lavoro" | Le tre stanno in Lavoro; il menu Cartella ▸ Lavoro mostra solo quelle |
| L7 | Etichette ▸ Nuova etichetta… "bug" su una, poi "BUG" su un'altra | Una sola etichetta "bug"; il filtro le mostra entrambe |
| L8 | Cerca "safari", poi la data di oggi (2026-10-19) | Filtri corretti; accenti e maiuscole ignorati |
| L9 | Elimina (⌫) una cattura aperta in un'altra finestra | La finestra si chiude; il file è nel Cestino |
| L10 | Trascina una miniatura sulla tela | Diventa un oggetto immagine, annotazioni comprese |
| L11 | Trascina una miniatura nel Finder | Arriva un PNG con il nome della cattura |
| L12 | Trascina un PNG dal Finder sulla striscia | Entra nella libreria; l'originale resta |
| L13 | Nascondi il carosello (toolbar, menu Vista o ⌃⌘L), apri un'altra cattura | Nascosto anche lì; riavviando resta nascosto |
| L14 | Esci da Pinxel, rovina `library.json` (scrivi "x"), riapri | Avviso; catture presenti, cartelle ed etichette perse; `library.json.rovinato` esiste |
| L15 | Cancella un `.pinxel` dal Finder, torna su Pinxel | La miniatura sparisce |
| L16 | Con 200+ catture (copia file nella cartella), scorri il carosello | Scorrimento fluido, miniature che arrivano senza bloccare |
```

- [ ] **Step 4: Spec status and rulings**

In the spec set `- **Stato:** approvata, implementata` and add any rulings ledgered during execution (e.g. the strip shortcut) to the decisions table.

- [ ] **Step 5: Full verification**

Run: `python3 <scratchpad>/pt.py` and the build command.
Expected: all package tests pass (453 + new); build succeeds.

- [ ] **Step 6: Commit**

```bash
git add App/PinxelUITests/LibraryUITests.swift docs
git commit -m "test(library): UI tests and manual checklist"
```
