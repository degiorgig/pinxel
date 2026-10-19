# Captures as Objects Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The captured image is always an ordinary, editable image object, and the canvas is always the rectangle that holds all content, growing and shrinking in every direction.

**Architecture:** `PinxelDocument` loses `background` and `imageOperations`; the capture becomes an `.image` annotation at the bottom of the stack. After every command the session appends a `FitCanvas` command (pure, in `DocumentModel`) that translates everything so the content rectangle starts at (0,0) and sets `canvasSize`; the canvas view shifts its scroll by the same amount so nothing jumps. Blur, pixelate and magnifier sample a render of the layers below them. Crop, resize and cut-out become pure functions over the annotation list (`ContentEditing`). Files move to format version 2; version 1 files are converted on read.

**Tech Stack:** Swift 6, macOS 15+, AppKit + SwiftUI, Core Graphics / Core Image, Swift Testing (package), XCTest (UI tests), XcodeGen.

**Spec:** `docs/superpowers/specs/2026-10-19-pinxel-objects-design.md`

## Global Constraints

- macOS 15+, Swift 6 strict concurrency; no third-party dependencies.
- The capture is always an object; the canvas is always the content rectangle (grows and shrinks), for every document.
- Content bounds include every object, rotation, stroke, arrow heads and shadow; rounded outward to whole pixels.
- The canvas adapts at the end of each command (on release), never during a gesture preview.
- Annotation coordinates always start at the top-left of the canvas: `FitCanvas` translates objects; one user action = one undo step.
- Largest side `PinxelDocument.maxImageSide` (32 768): beyond it the canvas stops, anchored at the content's top-left.
- Blur, pixelate, magnifier sample everything below them in the stack.
- `.pinxel` format version 2; version 1 files convert on open; the file on disk changes only when saved; versions > 2 open read-only.
- ⌘V replaces the bottom image keeping annotations; ⌥⌘V and drops add an image object; `ImageOperation.extend` and `growsCanvas` are removed from the editor.
- Dragging from an unselected image draws the selection marquee; clicking selects it; a marquee selects an image only if it contains it entirely.
- User-facing strings in Italian; code comments in Italian like the surrounding files; commits in English with the Co-Authored-By trailer.
- Never mention other screenshot products in the repo (public).
- Package tests: `python3 /private/tmp/claude-501/-Users-giovanni-work-reatool/d2d00140-beb8-4428-98e4-cbbc64479070/scratchpad/pt.py [filter]` (prints `exit | tests | problems`). App build: `xcodebuild -project Pinxel.xcodeproj -scheme Pinxel -configuration Debug build`. After adding app files run `xcodegen generate`.

## Review Focus

1. Hostile or corrupt files with enormous coordinates (1e300, NaN) must not crash `ContentFit` when it converts to `Int`. → Task 1 test `hugeCoordinatesDoNotCrash`.
2. A document whose last object was deleted must still save (thumbnail) and render an empty canvas, not fail the autosave. → Task 4 test `emptyDocumentMakesAThumbnail`.
3. Arrow-key nudges that move the object defining the canvas edge: each fit translates everything, so merging nudges across fits would undo to the wrong place. → Task 4 test `nudgesAcrossAFitUndoExactly`.
4. Large captures with a blur: the layers below must be rendered only for the effect's region, not the whole canvas, or every redraw stalls. → Task 2 test `layersAreRenderedOnlyForTheRegion`.
5. A version 1 file with crop and annotations, opened, saved and reopened, must look the same and keep its annotations. → Task 5 test `v1RoundTripThroughV2`.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `PinxelKit/Sources/DocumentModel/ContentFit.swift` (new) | `Annotation.visualBounds`, `ContentFit.bounds(of:)` |
| `PinxelKit/Sources/DocumentModel/EditCommand.swift` | `FitCanvas`, `SetAnnotations`; remove `ApplyImageOperation`, `ReplaceBackground` |
| `PinxelKit/Sources/DocumentModel/PinxelDocument.swift` | v2 document (no background, no operations) |
| `PinxelKit/Sources/DocumentModel/Validation.swift` | v2 validation (empty canvas allowed) |
| `PinxelKit/Sources/Rendering/DocumentRenderer.swift` | v2 render; layers-below images for effects |
| `PinxelKit/Sources/Rendering/AnnotationRenderer.swift`, `EffectRenderer.swift`, `EffectCache.swift` | effects read the layers below |
| `PinxelKit/Sources/Persistence/PinxelArchive.swift` | format v2; v1 conversion |
| `PinxelKit/Sources/Persistence/LegacyDocumentV1.swift` (new) | v1 JSON model, validation, conversion |
| `PinxelKit/Sources/Persistence/Thumbnailer.swift` | empty document thumbnail |
| `PinxelKit/Sources/AppCore/CaptureDocumentBuilder.swift` | capture = image object; blank = no objects |
| `PinxelKit/Sources/EditorUI/ContentEditing.swift` (new) | crop, scale, cut-out, replace bottom image over annotations |
| `PinxelKit/Sources/EditorUI/EditorSession.swift` | append `FitCanvas`, canvas shift callback, no coalescing across fits |
| `PinxelKit/Sources/EditorUI/ToolController.swift` | crop/cut requests; image press vs marquee |
| `PinxelKit/Sources/EditorUI/HitTesting.swift` | marquee needs whole images |
| `PinxelKit/Sources/EditorUI/CanvasView.swift` | paste/insert/crop/cut wiring, blank, shift compensation, no clip while previewing |
| `PinxelKit/Sources/EditorUI/Viewport.swift` | `shift(by:)`, `keepInView` |
| `PinxelKit/Sources/EditorUI/ImagePlacement.swift` | `centered(...)` without clamping |
| `PinxelKit/Sources/EditorUI/ImageEditing.swift` | `ResizeDraft.targetSize` |
| `App/Pinxel/AppEnvironment.swift`, `App/Pinxel/Editor/ImageSheets.swift` | new blank and resize calls |
| `PinxelKit/Tests/PinxelTestSupport/TestDocuments.swift` | v2 test documents with a capture image |
| `App/PinxelUITests/ObjectsUITests.swift` (new), `docs/manual-tests/objects.md` (new) | UI test, manual checks |

---

### Task 1: Content bounds and `FitCanvas`

**Files:**
- Create: `PinxelKit/Sources/DocumentModel/ContentFit.swift`
- Modify: `PinxelKit/Sources/DocumentModel/EditCommand.swift` (append `FitCanvas`)
- Test: `PinxelKit/Tests/DocumentModelTests/ContentFitTests.swift`

**Interfaces:**
- Consumes: `Annotation.bounds`, `Annotation.transformed(by:)`, `PointMapping`, `PinxelDocument.canvasSize`, `PinxelDocument.maxImageSide`.
- Produces:
  - `extension Annotation { public var visualBounds: CGRect }`
  - `public enum ContentFit { public static func bounds(of annotations: [Annotation]) -> PixelRect? }`
  - `public struct FitCanvas: EditCommand { public init?(in document: PinxelDocument); public let offset: CGVector; public let sizeAfter: PixelSize }`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import DocumentModel
import PinxelTestSupport

struct ContentFitTests {
    func image(_ rect: CGRect, rotation: Double = 0) -> Annotation {
        Annotation(kind: .image(PlacedImageData(rect: rect, asset: ImageAssetRef(name: "a.png"))), style: Style(stroke: nil, lineWidth: 0), rotation: rotation)
    }

    func document(_ annotations: [Annotation], size: PixelSize = PixelSize(width: 100, height: 100)) -> PinxelDocument {
        var document = TestDocuments.document(annotations: [], size: size)
        document.annotations = annotations
        return document
    }

    @Test func imagesGiveTheirRectangle() {
        #expect(ContentFit.bounds(of: [image(CGRect(x: 10, y: 20, width: 30, height: 40))]) == PixelRect(x: 10, y: 20, width: 30, height: 40))
    }

    @Test func boundsRoundOutward() {
        #expect(ContentFit.bounds(of: [image(CGRect(x: 0.5, y: 0.5, width: 10, height: 10))]) == PixelRect(x: 0, y: 0, width: 11, height: 11))
    }

    @Test func thickStrokeAndArrowHeadsCount() {
        let arrow = Annotation(kind: .arrow(ArrowData(line: LineGeometry(start: CGPoint(x: 0, y: 50), end: CGPoint(x: 100, y: 50)),
                                                      heads: ArrowHeads(start: .none, end: .triangle))),
                               style: Style(stroke: .black, lineWidth: 10))
        // Tratto 5 + punta max(30,10)*0.6 = 18 → 23 per lato.
        #expect(ContentFit.bounds(of: [arrow]) == PixelRect(x: -23, y: 27, width: 146, height: 46))
    }

    @Test func rotationCounts() throws {
        let rotated = image(CGRect(x: 0, y: 0, width: 100, height: 10), rotation: .pi / 2)
        let rect = try #require(ContentFit.bounds(of: [rotated]))
        #expect(rect.width == 10 && rect.height == 100)
    }

    @Test func shadowCounts() {
        var shape = Annotation(kind: .shape(ShapeData(rect: CGRect(x: 0, y: 0, width: 10, height: 10), shape: .rectangle)), style: Style(stroke: nil, lineWidth: 0))
        shape.style.shadow = Shadow(offset: CGSize(width: 0, height: 10), blur: 2, color: .black)
        #expect(ContentFit.bounds(of: [shape]) == PixelRect(x: -3, y: -3, width: 16, height: 26))
    }

    @Test func noObjectsNoBounds() {
        #expect(ContentFit.bounds(of: []) == nil)
    }

    @Test func hugeCoordinatesDoNotCrash() {
        let far = image(CGRect(x: 1e300, y: -1e300, width: 10, height: .nan))
        _ = ContentFit.bounds(of: [far, image(CGRect(x: 0, y: 0, width: 10, height: 10))])
        _ = FitCanvas(in: document([far]))
    }

    @Test func fitTranslatesToTheOriginAndSetsTheSize() throws {
        let doc = document([image(CGRect(x: -20, y: 10, width: 50, height: 30))])
        let fit = try #require(FitCanvas(in: doc))
        var after = doc
        fit.apply(to: &after)
        #expect(after.canvasSize == PixelSize(width: 50, height: 30))
        guard case .image(let data) = after.annotations[0].kind else { Issue.record("not an image"); return }
        #expect(data.rect == CGRect(x: 0, y: 0, width: 50, height: 30))
        #expect(fit.offset == CGVector(dx: 20, dy: -10))
        fit.revert(on: &after)
        #expect(after == doc)
    }

    @Test func alreadyFittedNeedsNoCommand() {
        #expect(FitCanvas(in: document([image(CGRect(x: 0, y: 0, width: 100, height: 100))])) == nil)
    }

    @Test func emptyDocumentFitsToZero() throws {
        let fit = try #require(FitCanvas(in: document([])))
        var after = document([])
        fit.apply(to: &after)
        #expect(after.canvasSize == PixelSize(width: 0, height: 0))
    }

    @Test func sizeStopsAtTheLimit() throws {
        let limit = PinxelDocument.maxImageSide
        let fit = try #require(FitCanvas(in: document([image(CGRect(x: 0, y: 0, width: Double(limit) + 500, height: 10))])))
        #expect(fit.sizeAfter == PixelSize(width: limit, height: 10))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `python3 …/pt.py ContentFitTests`
Expected: compile errors `cannot find 'ContentFit'` / `cannot find 'FitCanvas'`.

- [ ] **Step 3: Write `ContentFit.swift`**

```swift
import Foundation

extension Annotation {
    /// Rettangolo allineato agli assi che contiene tutto ciò che l'annotazione disegna: rotazione, tratto,
    /// punte delle frecce e ombra compresi. `.null` per i tipi sconosciuti o le geometrie non finite.
    public var visualBounds: CGRect {
        let base = bounds
        guard !base.isNull, base.minX.isFinite, base.minY.isFinite, base.width.isFinite, base.height.isFinite else { return .null }
        var outset = 0.0
        if style.stroke != nil { outset += max(style.lineWidth, 0) / 2 }
        if case .arrow = kind { outset += max(style.lineWidth * 3, 10) * 0.6 }
        var rect = base.insetBy(dx: -outset, dy: -outset)
        if rotation != 0, rotation.isFinite {
            let center = CGPoint(x: base.midX, y: base.midY)
            let cosine = cos(rotation), sine = sin(rotation)
            let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                           CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)].map { point in
                let dx = point.x - center.x, dy = point.y - center.y
                // Stessa convenzione di `AnnotationRenderer`: asse y verso il basso.
                return CGPoint(x: center.x + dx * cosine - dy * sine, y: center.y + dx * sine + dy * cosine)
            }
            rect = .bounding(corners)
        }
        if let shadow = style.shadow {
            let blur = max(shadow.blur, 0) * 1.5
            rect = rect.union(rect.offsetBy(dx: shadow.offset.width, dy: shadow.offset.height).insetBy(dx: -blur, dy: -blur))
        }
        return rect
    }
}

/// La tela segue il contenuto: il rettangolo che racchiude tutti gli oggetti.
public enum ContentFit {
    /// Rettangolo in pixel interi, arrotondato verso l'esterno; `nil` se non c'è niente da disegnare.
    public static func bounds(of annotations: [Annotation]) -> PixelRect? {
        let union = annotations.map(\.visualBounds).filter { !$0.isNull }.reduce(CGRect.null) { $0.union($1) }
        guard !union.isNull else { return nil }
        let minX = whole(union.minX.rounded(.down)), minY = whole(union.minY.rounded(.down))
        let maxX = whole(union.maxX.rounded(.up)), maxY = whole(union.maxY.rounded(.up))
        return PixelRect(x: minX, y: minY, width: max(maxX - minX, 1), height: max(maxY - minY, 1))
    }

    /// Coordinate da file ostili: niente overflow nella conversione a `Int`.
    private static func whole(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return Int(min(max(value, -1_000_000_000), 1_000_000_000))
    }
}
```

- [ ] **Step 4: Append `FitCanvas` to `EditCommand.swift`**

```swift
/// Porta il rettangolo del contenuto a partire da (0,0) e ci adatta la tela; la sessione lo aggiunge dopo ogni comando.
/// Tiene le annotazioni di prima: l'annullamento è esatto anche con rettangoli non normalizzati.
public struct FitCanvas: EditCommand {
    public let name = "Adatta tela"
    /// Spostamento applicato a tutti gli oggetti, in pixel interi del documento.
    public let offset: CGVector
    public let sizeAfter: PixelSize
    private let sizeBefore: PixelSize
    private let annotationsBefore: [Annotation]

    /// `nil` se la tela è già adattata al contenuto.
    public init?(in document: PinxelDocument) {
        let limit = PinxelDocument.maxImageSide
        let target = ContentFit.bounds(of: document.annotations)
        let offset = target.map { CGVector(dx: Double(-$0.x), dy: Double(-$0.y)) } ?? .zero
        let size = target.map { PixelSize(width: min($0.width, limit), height: min($0.height, limit)) } ?? PixelSize(width: 0, height: 0)
        guard offset != .zero || size != document.canvasSize else { return nil }
        self.offset = offset
        sizeAfter = size
        sizeBefore = document.canvasSize
        annotationsBefore = document.annotations
    }

    public func apply(to document: inout PinxelDocument) {
        let dx = offset.dx, dy = offset.dy
        let mapping = PointMapping { CGPoint(x: $0.x + dx, y: $0.y + dy) }
        document.annotations = offset == .zero ? annotationsBefore : annotationsBefore.map { $0.transformed(by: mapping) }
        document.canvasSize = sizeAfter
    }

    public func revert(on document: inout PinxelDocument) {
        document.annotations = annotationsBefore
        document.canvasSize = sizeBefore
    }
}
```

- [ ] **Step 5: Run the tests**

Run: `python3 …/pt.py ContentFitTests`
Expected: `exit 0 | tests 11 | problems 0`. If `shadowCounts` or `thickStrokeAndArrowHeadsCount` disagree only in the expected literal, recompute by hand from the formula above before changing anything.

- [ ] **Step 6: Run the whole suite and commit**

Run: `python3 …/pt.py` → `exit 0`.

```bash
git add PinxelKit/Sources/DocumentModel/ContentFit.swift PinxelKit/Sources/DocumentModel/EditCommand.swift PinxelKit/Tests/DocumentModelTests/ContentFitTests.swift
git commit -m "feat(model): content bounds and a FitCanvas command" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Effects read the layers below them

**Files:**
- Modify: `PinxelKit/Sources/Rendering/DocumentRenderer.swift`, `AnnotationRenderer.swift`, `EffectRenderer.swift`, `EffectCache.swift`
- Test: `PinxelKit/Tests/RenderingTests/LayerEffectTests.swift`; re-record `__Snapshots__/all-kinds.png`

**Interfaces:**
- Consumes: the current (v1) document with `background`.
- Produces:
  - `RenderContext` gains `index: Int`-aware drawing: `AnnotationRenderer.draw(_:index:in:context:)`.
  - `RenderContext.layers: (Int, PixelRect) -> CGImage?` — image of `region` (document pixels) with the background and annotations `0..<index`.
  - `RenderContext.contentSize: PixelSize` replaces `background` as the clamp for effect regions.
  - `EffectCache.misses: Int` (internal, for tests).

- [ ] **Step 1: Write the failing tests**

```swift
import CoreGraphics
import Foundation
import Testing
import DocumentModel
@testable import Rendering
import PinxelTestSupport

struct LayerEffectTests {
    let noiseRef = ImageAssetRef(name: "assets/noise.png")

    func render(_ annotations: [Annotation], renderer: DocumentRenderer = DocumentRenderer()) throws -> CGImage {
        let document = TestDocuments.document(annotations: annotations, size: PixelSize(width: 200, height: 200))
        let assets = DictionaryAssetProvider([
            TestDocuments.background: TestImages.solid(width: 200, height: 200, red: 1, green: 1, blue: 1),
            noiseRef: TestImages.noise(width: 100, height: 100),
        ])
        return try renderer.renderImage(document, assets: assets)
    }

    func variance(_ image: CGImage, _ rect: CGRect) -> Double {
        let pixels = PixelBuffer(image)
        var values: [Double] = []
        for y in Int(rect.minY)..<Int(rect.maxY) { for x in Int(rect.minX)..<Int(rect.maxX) { values.append(Double(pixels.pixel(x: x, y: y).r)) } }
        let mean = values.reduce(0, +) / Double(values.count)
        return values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
    }

    var placedNoise: Annotation {
        Annotation(kind: .image(PlacedImageData(rect: CGRect(x: 50, y: 50, width: 100, height: 100), asset: noiseRef)), style: Style(stroke: nil, lineWidth: 0))
    }

    @Test func blurCoversAPlacedImage() throws {
        let inner = CGRect(x: 70, y: 70, width: 60, height: 60)
        let before = variance(try render([placedNoise]), inner)
        let after = variance(try render([placedNoise, Annotation(kind: .blur(BlurData(rect: CGRect(x: 50, y: 50, width: 100, height: 100), radius: 8)))]), inner)
        #expect(after < before * 0.2, "variance \(before) → \(after)")
    }

    @Test func blurCoversAnArrowBelowButNotOneAbove() throws {
        let arrow = { (y: Double) in Annotation(kind: .arrow(ArrowData(line: LineGeometry(start: CGPoint(x: 20, y: y), end: CGPoint(x: 180, y: y)), heads: ArrowHeads(start: .none, end: .none))),
                                                style: Style(stroke: .black, lineWidth: 4)) }
        let blur = Annotation(kind: .blur(BlurData(rect: CGRect(x: 0, y: 0, width: 200, height: 200), radius: 10)))
        let below = PixelBuffer(try render([arrow(100), blur]))
        let above = PixelBuffer(try render([blur, arrow(100)]))
        #expect(below.pixel(x: 100, y: 100).r > 60)   // la freccia sotto è sfocata: niente più nero pieno
        #expect(above.pixel(x: 100, y: 100).r < 10)   // quella sopra resta nitida
    }

    @Test func magnifierShowsAPlacedImage() throws {
        let red = Annotation(kind: .image(PlacedImageData(rect: CGRect(x: 10, y: 10, width: 20, height: 20), asset: ImageAssetRef(name: "assets/red.png"))), style: Style(stroke: nil, lineWidth: 0))
        let magnifier = Annotation(kind: .magnifier(MagnifierData(source: CGRect(x: 12, y: 12, width: 10, height: 10), target: CGRect(x: 100, y: 100, width: 60, height: 60),
                                                                  shape: .rectangle, showsConnector: false)), style: Style(stroke: nil))
        let document = TestDocuments.document(annotations: [red, magnifier], size: PixelSize(width: 200, height: 200))
        let assets = DictionaryAssetProvider([
            TestDocuments.background: TestImages.solid(width: 200, height: 200, red: 1, green: 1, blue: 1),
            ImageAssetRef(name: "assets/red.png"): TestImages.solid(width: 20, height: 20, red: 1, green: 0, blue: 0),
        ])
        let pixel = PixelBuffer(try DocumentRenderer().renderImage(document, assets: assets)).pixel(x: 130, y: 130)
        #expect(pixel.r > 240 && pixel.g < 15)
    }

    @Test func farObjectsDoNotInvalidateTheEffect() throws {
        let renderer = DocumentRenderer()
        let blur = Annotation(kind: .blur(BlurData(rect: CGRect(x: 50, y: 50, width: 40, height: 40), radius: 4)))
        let far = { (x: Double) in Annotation(id: TestDocuments.id(50), kind: .shape(ShapeData(rect: CGRect(x: x, y: 170, width: 10, height: 10), shape: .rectangle))) }
        _ = try render([far(150), blur], renderer: renderer)
        let misses = renderer.effectCacheMisses
        _ = try render([far(160), blur], renderer: renderer)
        #expect(renderer.effectCacheMisses == misses)
    }

    @Test func layersAreRenderedOnlyForTheRegion() throws {
        let renderer = DocumentRenderer()
        _ = try render([Annotation(kind: .blur(BlurData(rect: CGRect(x: 10, y: 20, width: 30, height: 40), radius: 4)))], renderer: renderer)
        #expect(renderer.lastLayerSize == PixelSize(width: 30, height: 40))
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `python3 …/pt.py LayerEffectTests`
Expected: compile errors for `effectCacheMisses` and `lastLayerSize`.

- [ ] **Step 3: Count cache misses in `EffectCache.swift`**

```swift
/// Piccola cache LRU per sfocature, pixelature e livelli già calcolati.
final class EffectCache {
    private var storage: [String: CGImage] = [:]
    private var order: [String] = []
    private let capacity: Int
    /// Quante immagini sono state calcolate (per i test).
    private(set) var misses = 0

    init(capacity: Int = 64) {
        self.capacity = capacity
    }

    func image(for key: String, make: () -> CGImage?) -> CGImage? {
        if let hit = storage[key] { return hit }
        misses += 1
        guard let value = make() else { return nil }
        storage[key] = value
        order.append(key)
        if order.count > capacity {
            storage.removeValue(forKey: order.removeFirst())
        }
        return value
    }

    func removeAll() {
        storage.removeAll()
        order.removeAll()
    }
}
```

- [ ] **Step 4: Replace `RenderContext` and the draw entry point in `AnnotationRenderer.swift`**

```swift
struct RenderContext {
    /// Dimensioni del contenuto: le regioni degli effetti restano dentro.
    let contentSize: PixelSize
    let stepLabels: [UUID: String]
    let assets: any AssetProvider
    let outputScale: Double
    let effects: EffectCache
    /// Immagine della regione (pixel del documento) con tutto ciò che sta sotto l'annotazione di indice dato.
    let layers: (Int, PixelRect) -> CGImage?
}

enum AnnotationRenderer {
    static func draw(_ annotation: Annotation, index: Int, in ctx: CGContext, context: RenderContext) {
        // … corpo invariato fino a `drawContent`, che ora riceve anche `index` …
        drawContent(annotation, index: index, in: ctx, context: context)
        ctx.endTransparencyLayer()
    }

    private static func drawContent(_ annotation: Annotation, index: Int, in ctx: CGContext, context: RenderContext) {
        // … come prima, con:
        // case .blur(let data): EffectRenderer.drawBlur(data, index: index, context: context, in: ctx)
        // case .pixelate(let data): EffectRenderer.drawPixelate(data, index: index, context: context, in: ctx)
        // case .magnifier(let data): EffectRenderer.drawMagnifier(data, index: index, style: style, context: context, in: ctx)
    }
}
```

Keep every other line of `draw` and `drawContent` as it is today.

- [ ] **Step 5: Effects read `context.layers` in `EffectRenderer.swift`**

Replace `region(_:in:)`, `drawBlur`, `drawPixelate`, the private `blurred`/`pixelated` and the first lines of `drawMagnifier`:

```swift
    /// Regione intera di `rect` dentro il contenuto, o `nil` se vuota.
    static func region(_ rect: CGRect, in size: PixelSize) -> PixelRect? {
        let r = rect.standardized.integral
        guard r.minX.isFinite, r.minY.isFinite, r.width.isFinite, r.height.isFinite else { return nil }
        let pixel = PixelRect(
            x: ImageDrawing.clampedInt(r.minX), y: ImageDrawing.clampedInt(r.minY),
            width: ImageDrawing.clampedInt(r.width), height: ImageDrawing.clampedInt(r.height)
        ).clamped(to: size)
        return pixel.width > 0 && pixel.height > 0 ? pixel : nil
    }

    static func drawBlur(_ data: BlurData, index: Int, context: RenderContext, in ctx: CGContext) {
        guard data.radius > 0, let region = region(data.rect, in: context.contentSize),
              let below = context.layers(index, region) else { return }
        let key = "blur|\(ObjectIdentifier(below))|\(data.radius)"
        guard let image = context.effects.image(for: key, make: { blurred(below, radius: data.radius) }) else { return }
        ImageDrawing.draw(image, in: region.cgRect, context: ctx)
    }

    static func drawPixelate(_ data: PixelateData, index: Int, context: RenderContext, in ctx: CGContext) {
        guard let region = region(data.rect, in: context.contentSize), let below = context.layers(index, region) else { return }
        let key = "pixelate|\(ObjectIdentifier(below))|\(data.blockSize)"
        guard let image = context.effects.image(for: key, make: { pixelated(below, blockSize: data.blockSize) }) else { return }
        ImageDrawing.draw(image, in: region.cgRect, context: ctx)
    }

    private static func blurred(_ input: CGImage, radius: Double) -> CGImage? {
        let image = CIImage(cgImage: input)
        let output = image.clampedToExtent().applyingGaussianBlur(sigma: radius).cropped(to: image.extent)
        return ciContext.createCGImage(output, from: image.extent)
    }

    private static func pixelated(_ input: CGImage, blockSize: Double) -> CGImage? {
        guard let filter = CIFilter(name: "CIPixellate") else { return nil }
        let image = CIImage(cgImage: input)
        filter.setValue(image.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(max(blockSize, 1), forKey: kCIInputScaleKey)
        filter.setValue(CIVector(x: 0, y: 0), forKey: kCIInputCenterKey)
        guard let output = filter.outputImage?.cropped(to: image.extent) else { return nil }
        return ciContext.createCGImage(output, from: image.extent)
    }

    static func drawMagnifier(_ data: MagnifierData, index: Int, style: Style, context: RenderContext, in ctx: CGContext) {
        let target = data.target.standardized
        let source = data.source.standardized
        guard target.width > 0, target.height > 0, source.width > 0, source.height > 0,
              let region = region(data.source, in: context.contentSize),
              let crop = context.layers(index, region) else { return }
        // … resto invariato …
```

The layer image is cached by content (Step 6), so `ObjectIdentifier(below)` is stable while nothing under the effect changes. The pixelate key keeps the block alignment of today because the region origin does not change.

- [ ] **Step 6: `DocumentRenderer` builds the context and the layer images**

In `render(_:assets:in:options:)` replace the creation of `context` and the annotation loop with:

```swift
        let stepLabels = StepNumbering.labels(for: document.annotations)
        let content = document.imageSize
        let excluded = options.excludedAnnotationIDs
        var context: RenderContext!
        context = RenderContext(
            contentSize: content,
            stepLabels: stepLabels,
            assets: assets,
            outputScale: options.outputScale,
            effects: effects,
            layers: { [unowned self] index, region in
                self.layers(below: index, region: region, document: document, background: background,
                            excluded: excluded, context: context)
            }
        )
        ctx.translateBy(x: style.padding, y: style.padding)
        for (index, annotation) in document.annotations.enumerated() where !excluded.contains(annotation.id) {
            AnnotationRenderer.draw(annotation, index: index, in: ctx, context: context)
        }
```

and add to `DocumentRenderer`:

```swift
    /// Dimensioni dell'ultima immagine di livelli calcolata (per i test).
    private(set) var lastLayerSize: PixelSize?
    var effectCacheMisses: Int { effects.misses }

    /// La regione con lo sfondo e le annotazioni sotto `index`, a 1 pixel per pixel del documento.
    /// La chiave dipende solo da ciò che tocca la regione: spostare un oggetto lontano non la invalida.
    private func layers(below index: Int, region: PixelRect, document: PinxelDocument, background: CGImage?,
                        excluded: Set<UUID>, context: RenderContext) -> CGImage? {
        let area = region.cgRect
        let below = document.annotations.prefix(index).enumerated().filter { _, annotation in
            !excluded.contains(annotation.id) && annotation.visualBounds.intersects(area)
        }
        let backgroundKey = background.map { "\(ObjectIdentifier($0))" } ?? "-"
        let key = "layers|\(region)|\(backgroundKey)|\(below.map { "\($0.offset):\($0.element)" })"
        return effects.image(for: key) {
            guard let ctx = ImageDrawing.makeContext(width: region.width, height: region.height) else { return nil }
            lastLayerSize = PixelSize(width: region.width, height: region.height)
            ctx.translateBy(x: 0, y: CGFloat(region.height))
            ctx.scaleBy(x: 1, y: -1)
            ctx.translateBy(x: -CGFloat(region.x), y: -CGFloat(region.y))
            if let background {
                ImageDrawing.draw(background, in: CGRect(x: 0, y: 0, width: background.width, height: background.height), context: ctx)
            }
            let flat = RenderContext(contentSize: context.contentSize, stepLabels: context.stepLabels, assets: context.assets,
                                     outputScale: 1, effects: context.effects, layers: context.layers)
            for (offset, annotation) in below {
                AnnotationRenderer.draw(annotation, index: offset, in: ctx, context: flat)
            }
            return ctx.makeImage()
        }
    }
```

`background` here is the processed background already computed at the top of `render`. In Task 4 it becomes `nil`.

- [ ] **Step 7: Run the new tests and the rendering suite**

Run: `python3 …/pt.py LayerEffectTests` → `exit 0 | tests 5`.
Run: `python3 …/pt.py RenderingTests`.
Expected: everything passes except `allKindsSnapshot`, which now differs: in `TestDocuments.allKindsAnnotations()` the callout tail runs under the blur at (150,190) and the callout sits under the magnifier source.

- [ ] **Step 8: Re-record the snapshot and look at it**

Run: `PINXEL_RECORD_SNAPSHOTS=1 python3 …/pt.py allKindsSnapshot` then open `PinxelKit/Tests/RenderingTests/__Snapshots__/all-kinds.png` with the Read tool. Check: the callout tail is blurred inside the blur rectangle, the magnifier target shows part of the callout border, everything else looks as before. Run `python3 …/pt.py RenderingTests` → `exit 0`.

- [ ] **Step 9: Full suite and commit**

Run: `python3 …/pt.py` → `exit 0`.

```bash
git add PinxelKit/Sources/Rendering PinxelKit/Tests/RenderingTests
git commit -m "feat(rendering): blur, pixelate and magnifier read the layers below them" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Crop, scale and cut-out over the content

**Files:**
- Create: `PinxelKit/Sources/EditorUI/ContentEditing.swift`
- Test: `PinxelKit/Tests/EditorUITests/ContentEditingTests.swift`

**Interfaces:**
- Consumes: `Annotation.visualBounds` (Task 1), `ImageOperation.mapping(from:)`, `BackgroundProcessor.process(_:operations:)`, `CutOut`.
- Produces:

```swift
public enum ContentEditing {
    public typealias Images = (ImageAssetRef) -> CGImage?
    public typealias AddImage = (CGImage) -> ImageAssetRef?
    public static func cropped(_ annotations: [Annotation], to rect: PixelRect, images: Images, add: AddImage) -> [Annotation]
    public static func scaled(_ annotations: [Annotation], from size: PixelSize, to target: PixelSize) -> [Annotation]
    public static func cut(_ annotations: [Annotation], _ cut: CutOut, canvas: PixelSize, images: Images, add: AddImage) -> [Annotation]
    public static func replacingBottomImage(in annotations: [Annotation], asset: ImageAssetRef, size: CGSize, newID: UUID) -> any EditCommand
}
```

- [ ] **Step 1: Write the failing tests**

```swift
import CoreGraphics
import DocumentModel
import Foundation
import PinxelTestSupport
import Rendering
import Testing
@testable import EditorUI

struct ContentEditingTests {
    final class Images {
        var stored: [ImageAssetRef: CGImage] = [:]
        func image(_ ref: ImageAssetRef) -> CGImage? { stored[ref] }
        func add(_ image: CGImage) -> ImageAssetRef? {
            let ref = ImageAssetRef(name: "assets/\(stored.count).png")
            stored[ref] = image
            return ref
        }
    }

    func placed(_ rect: CGRect, _ ref: ImageAssetRef, rotation: Double = 0) -> Annotation {
        Annotation(kind: .image(PlacedImageData(rect: rect, asset: ref)), style: Style(stroke: nil, lineWidth: 0), rotation: rotation)
    }

    func rect(_ annotation: Annotation) -> CGRect? {
        if case .image(let data) = annotation.kind { return data.rect }
        return nil
    }

    func step(_ center: CGPoint) -> Annotation {
        Annotation(kind: .step(StepData(center: center, diameter: 20, label: StepLabel())), style: Style(stroke: nil, fill: .accentRed))
    }

    @Test func cropCutsImagePixelsAndDropsWhatIsOutside() throws {
        let images = Images()
        let capture = ImageAssetRef(name: "capture.png")
        images.stored[capture] = TestImages.quadrants(width: 400, height: 300)
        let result = ContentEditing.cropped([placed(CGRect(x: 0, y: 0, width: 400, height: 300), capture), step(CGPoint(x: 350, y: 250)), step(CGPoint(x: 100, y: 100))],
                                            to: PixelRect(x: 0, y: 0, width: 200, height: 150), images: images.image, add: images.add)
        #expect(result.count == 2)                       // lo step a (350,250) era tutto fuori
        #expect(rect(result[0]) == CGRect(x: 0, y: 0, width: 200, height: 150))
        guard case .image(let data) = result[0].kind, let pixels = images.stored[data.asset] else { Issue.record("no cropped image"); return }
        #expect(pixels.width == 200 && pixels.height == 150)
    }

    @Test func cropKeepsAnnotationsAcrossTheEdgeWhole() {
        let images = Images()
        let crossing = step(CGPoint(x: 200, y: 75))
        let result = ContentEditing.cropped([crossing], to: PixelRect(x: 0, y: 0, width: 200, height: 150), images: images.image, add: images.add)
        #expect(result == [crossing])
    }

    @Test func cropRespectsTheImageDensity() throws {
        let images = Images()
        let ref = ImageAssetRef(name: "retina.png")
        images.stored[ref] = TestImages.quadrants(width: 800, height: 600)   // 2 pixel dell'immagine per pixel del documento
        let result = ContentEditing.cropped([placed(CGRect(x: 0, y: 0, width: 400, height: 300), ref)], to: PixelRect(x: 100, y: 0, width: 100, height: 300),
                                            images: images.image, add: images.add)
        guard case .image(let data) = result[0].kind, let pixels = images.stored[data.asset] else { Issue.record("no cropped image"); return }
        #expect(data.rect == CGRect(x: 100, y: 0, width: 100, height: 300))
        #expect(pixels.width == 200 && pixels.height == 600)
    }

    @Test func rotatedImagesAcrossTheCropStayWhole() {
        let images = Images()
        let rotated = placed(CGRect(x: 150, y: 50, width: 100, height: 50), ImageAssetRef(name: "r.png"), rotation: 0.3)
        #expect(ContentEditing.cropped([rotated], to: PixelRect(x: 0, y: 0, width: 200, height: 200), images: images.image, add: images.add) == [rotated])
    }

    @Test func scaleMovesAndResizesEverything() {
        let result = ContentEditing.scaled([placed(CGRect(x: 0, y: 0, width: 400, height: 300), ImageAssetRef(name: "a.png")), step(CGPoint(x: 100, y: 100))],
                                           from: PixelSize(width: 400, height: 300), to: PixelSize(width: 200, height: 150))
        #expect(rect(result[0]) == CGRect(x: 0, y: 0, width: 200, height: 150))
        guard case .step(let data) = result[1].kind else { Issue.record("not a step"); return }
        #expect(data.center == CGPoint(x: 50, y: 50))
    }

    @Test func cutRemovesTheBandFromImagesAndPullsTheRestCloser() throws {
        let images = Images()
        let ref = ImageAssetRef(name: "c.png")
        images.stored[ref] = TestImages.quadrants(width: 400, height: 300)
        let cut = CutOut(axis: .horizontal, start: 100, length: 50)
        let result = ContentEditing.cut([placed(CGRect(x: 0, y: 0, width: 400, height: 300), ref), step(CGPoint(x: 50, y: 200))],
                                        cut, canvas: PixelSize(width: 400, height: 300), images: images.image, add: images.add)
        #expect(rect(result[0]) == CGRect(x: 0, y: 0, width: 400, height: 250))
        guard case .image(let data) = result[0].kind, let pixels = images.stored[data.asset] else { Issue.record("no cut image"); return }
        #expect(pixels.height == 250)
        guard case .step(let moved) = result[1].kind else { Issue.record("not a step"); return }
        #expect(moved.center == CGPoint(x: 50, y: 150))
    }

    @Test func cutThroughPartOfAnImage() throws {
        let images = Images()
        let ref = ImageAssetRef(name: "p.png")
        images.stored[ref] = TestImages.quadrants(width: 100, height: 100)
        let result = ContentEditing.cut([placed(CGRect(x: 0, y: 120, width: 100, height: 100), ref)], CutOut(axis: .horizontal, start: 100, length: 50),
                                        canvas: PixelSize(width: 100, height: 220), images: images.image, add: images.add)
        // La fascia 100..<150 toglie 30 righe dall'immagine (120..<150); l'immagine sale a 100.
        #expect(rect(result[0]) == CGRect(x: 0, y: 100, width: 100, height: 70))
    }

    @Test func rotatedImagesInTheBandMoveWithoutCutting() {
        let images = Images()
        let rotated = placed(CGRect(x: 0, y: 160, width: 100, height: 20), ImageAssetRef(name: "r.png"), rotation: 0.5)
        let result = ContentEditing.cut([rotated], CutOut(axis: .horizontal, start: 100, length: 50), canvas: PixelSize(width: 100, height: 200),
                                        images: images.image, add: images.add)
        #expect(rect(result[0]) == CGRect(x: 0, y: 110, width: 100, height: 20))
    }

    @Test func pasteReplacesTheBottomImageKeepingItsPlace() throws {
        let annotations = [step(CGPoint(x: 10, y: 10)), placed(CGRect(x: 30, y: 40, width: 400, height: 300), ImageAssetRef(name: "old.png"))]
        let command = ContentEditing.replacingBottomImage(in: annotations, asset: ImageAssetRef(name: "new.png"), size: CGSize(width: 100, height: 50), newID: UUID())
        var document = TestDocuments.document(annotations: [], size: PixelSize(width: 430, height: 340))
        document.annotations = annotations
        command.apply(to: &document)
        #expect(document.annotations.count == 2)
        guard case .image(let data) = document.annotations[1].kind else { Issue.record("not an image"); return }
        #expect(data.rect == CGRect(x: 30, y: 40, width: 100, height: 50) && data.asset.name == "new.png")
    }

    @Test func pasteWithoutImagesAddsOneAtTheBottom() {
        var document = TestDocuments.document(annotations: [], size: PixelSize(width: 10, height: 10))
        document.annotations = [step(CGPoint(x: 5, y: 5))]
        let id = UUID()
        ContentEditing.replacingBottomImage(in: document.annotations, asset: ImageAssetRef(name: "n.png"), size: CGSize(width: 10, height: 10), newID: id).apply(to: &document)
        #expect(document.annotations.first?.id == id)
    }
}
```

`TestDocuments.document(annotations: [])` still has a background in this task; the tests replace `annotations` directly, so they keep working after Task 4.

- [ ] **Step 2: Run them to verify they fail**

Run: `python3 …/pt.py ContentEditingTests` → compile error `cannot find 'ContentEditing'`.

- [ ] **Step 3: Write `ContentEditing.swift`**

```swift
import CoreGraphics
import DocumentModel
import Foundation
import Rendering

/// Ritaglio, ridimensiona e taglia e ricuci su tutto il contenuto (spec §5). Funzioni pure sulla lista degli oggetti:
/// i pixel nuovi passano da `add`, che li registra fra le immagini del documento.
public enum ContentEditing {
    public typealias Images = (ImageAssetRef) -> CGImage?
    public typealias AddImage = (CGImage) -> ImageAssetRef?

    /// Le immagini tagliate dal riquadro perdono i pixel fuori; gli oggetti del tutto fuori spariscono;
    /// annotazioni e immagini ruotate a cavallo del bordo restano intere.
    public static func cropped(_ annotations: [Annotation], to rect: PixelRect, images: Images, add: AddImage) -> [Annotation] {
        let area = rect.cgRect
        return annotations.compactMap { annotation in
            let bounds = annotation.visualBounds
            guard !bounds.isNull, bounds.intersects(area) else { return nil }
            guard case .image(var data) = annotation.kind, annotation.rotation == 0 else { return annotation }
            let frame = data.rect.standardized
            guard !area.contains(frame) else { return annotation }
            let inside = frame.intersection(area)
            var copy = annotation
            if let source = images(data.asset), let part = crop(source, frame: frame, to: inside), let ref = add(part) {
                data.asset = ref
            }
            data.rect = inside
            copy.kind = .image(data)
            return copy
        }
    }

    /// Tutto il contenuto scalato rispetto all'angolo in alto a sinistra; le immagini cambiano solo riquadro.
    public static func scaled(_ annotations: [Annotation], from size: PixelSize, to target: PixelSize) -> [Annotation] {
        let mapping = ImageOperation.resize(target).mapping(from: size)
        return annotations.map { $0.transformed(by: mapping) }
    }

    /// Toglie la fascia dalle immagini non ruotate che attraversa; tutto ciò che c'è oltre si avvicina.
    public static func cut(_ annotations: [Annotation], _ cut: CutOut, canvas: PixelSize, images: Images, add: AddImage) -> [Annotation] {
        let start = Double(cut.clampedStart(in: canvas))
        let end = start + Double(cut.clampedLength(in: canvas))
        let mapping = ImageOperation.cutOut(cut).mapping(from: canvas)
        let horizontal = cut.axis == .horizontal
        return annotations.map { annotation in
            guard case .image(var data) = annotation.kind, annotation.rotation == 0 else { return annotation.transformed(by: mapping) }
            let frame = data.rect.standardized
            let low = horizontal ? frame.minY : frame.minX
            let high = horizontal ? frame.maxY : frame.maxX
            let overlap = min(end, high) - max(start, low)
            guard overlap > 0 else { return annotation.transformed(by: mapping) }
            var copy = annotation
            let pixels = images(data.asset)
            let density = pixels.map { horizontal ? Double($0.height) / frame.height : Double($0.width) / frame.width } ?? 1
            let local = CutOut(axis: cut.axis, start: Int(((max(start, low) - low) * density).rounded()),
                               length: Int((overlap * density).rounded()), edge: cut.edge)
            if let pixels, let result = BackgroundProcessor.process(pixels, operations: [.cutOut(local)]), let ref = add(result) {
                data.asset = ref
            }
            let origin = mapping.map(frame.origin)
            data.rect = horizontal
                ? CGRect(x: frame.minX, y: origin.y, width: frame.width, height: frame.height - overlap)
                : CGRect(x: origin.x, y: frame.minY, width: frame.width - overlap, height: frame.height)
            copy.kind = .image(data)
            return copy
        }
    }

    /// ⌘V con un'immagine: prende il posto della prima immagine dal fondo, nello stesso angolo, tenendo le annotazioni;
    /// senza immagini ne aggiunge una in fondo.
    public static func replacingBottomImage(in annotations: [Annotation], asset: ImageAssetRef, size: CGSize, newID: UUID) -> any EditCommand {
        if let bottom = annotations.first(where: { if case .image = $0.kind { true } else { false } }),
           case .image(var data) = bottom.kind {
            var after = bottom
            data.asset = asset
            data.rect = CGRect(origin: data.rect.standardized.origin, size: size)
            after.kind = .image(data)
            after.rotation = 0
            return UpdateAnnotations(name: "Incolla immagine", before: [bottom], after: [after])
        }
        let image = Annotation(id: newID, kind: .image(PlacedImageData(rect: CGRect(origin: .zero, size: size), asset: asset)),
                               style: Style(stroke: nil, lineWidth: 0))
        return AddAnnotations([image], at: 0, name: "Incolla immagine")
    }

    /// I pixel dell'immagine che cadono in `inside` (coordinate del documento), alla densità dell'immagine.
    private static func crop(_ image: CGImage, frame: CGRect, to inside: CGRect) -> CGImage? {
        guard frame.width > 0, frame.height > 0 else { return nil }
        let sx = Double(image.width) / frame.width, sy = Double(image.height) / frame.height
        let pixels = CGRect(x: ((inside.minX - frame.minX) * sx).rounded(), y: ((inside.minY - frame.minY) * sy).rounded(),
                            width: (inside.width * sx).rounded(), height: (inside.height * sy).rounded())
        guard pixels.width >= 1, pixels.height >= 1 else { return nil }
        return image.cropping(to: pixels)
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `python3 …/pt.py ContentEditingTests` → `exit 0 | tests 10`.

- [ ] **Step 5: Full suite and commit**

Run: `python3 …/pt.py` → `exit 0`.

```bash
git add PinxelKit/Sources/EditorUI/ContentEditing.swift PinxelKit/Tests/EditorUITests/ContentEditingTests.swift
git commit -m "feat(editor): crop, scale, cut-out and paste over the whole content" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: The capture becomes an object (document v2)

This task switches the model; nothing compiles until Step 9. Work through the steps in order, then let the compiler list what remains.

**Files:**
- Modify: `PinxelKit/Sources/DocumentModel/PinxelDocument.swift`, `Validation.swift`, `EditCommand.swift`, `ImageOperation.swift` (comment only)
- Modify: `PinxelKit/Sources/Rendering/DocumentRenderer.swift`
- Modify: `PinxelKit/Sources/Persistence/PinxelArchive.swift`, `Thumbnailer.swift`
- Modify: `PinxelKit/Sources/AppCore/CaptureDocumentBuilder.swift`
- Modify: `PinxelKit/Sources/EditorUI/EditorSession.swift`, `ToolController.swift`, `CanvasView.swift`, `ImagePlacement.swift`, `ImageEditing.swift`
- Modify: `App/Pinxel/AppEnvironment.swift`, `App/Pinxel/Editor/ImageSheets.swift`
- Modify: `PinxelKit/Tests/PinxelTestSupport/TestDocuments.swift` and every test that fails to compile or now fails
- Test: `PinxelKit/Tests/EditorUITests/SessionFitTests.swift`, `PinxelKit/Tests/PersistenceTests/DocumentV2Tests.swift`

**Interfaces:**
- Consumes: `FitCanvas`, `ContentFit` (Task 1); `RenderContext.layers` (Task 2); `ContentEditing` (Task 3).
- Produces:
  - `PinxelDocument(canvasSize:scale:colorSpace:canvasStyle:annotations:metadata:)`, `var imageSize: PixelSize { canvasSize }`.
  - `public struct SetAnnotations: EditCommand { init(name: String, before: [Annotation], after: [Annotation]) }`.
  - `PinxelArchive.currentVersion == 2`.
  - `CaptureDocumentBuilder.make(image:scale:metadata:)` (capture image annotation at index 0, id random) and `CaptureDocumentBuilder.blank(scale:)`.
  - `EditorSession.perform` appends `FitCanvas`; `EditorSession.onCanvasShift: ((CGVector) -> Void)?` is called after perform/undo/redo with the shift applied to the objects.
  - `ToolResult.crop: PixelRect?`, `ToolResult.cut: CutOut?`.
  - `ResizeDraft.targetSize: PixelSize?` (replaces `operation`).
  - `ImagePlacement.centered(pixelSize:imageScale:documentScale:center:maxSide:) -> CGRect`.
  - Test support: `TestDocuments.captureID`, `TestDocuments.capture(size:)`, `PinxelDocument.userAnnotations` (test-only extension).

- [ ] **Step 1: Write the failing tests**

`PinxelKit/Tests/EditorUITests/SessionFitTests.swift`:

```swift
import DocumentModel
import Foundation
import PinxelTestSupport
import Rendering
import Testing
@testable import EditorUI

@MainActor
struct SessionFitTests {
    func makeSession() -> EditorSession {
        let undo = UndoManager()
        undo.groupsByEvent = false
        return EditorSession(document: TestDocuments.document(annotations: [], size: PixelSize(width: 400, height: 300), scale: 1),
                             assets: DictionaryAssetProvider([TestDocuments.background: TestImages.quadrants()]), undoManager: undo)
    }

    func captureRect(_ session: EditorSession) -> CGRect? {
        guard case .image(let data) = session.document.annotations.first(where: { $0.id == TestDocuments.captureID })?.kind else { return nil }
        return data.rect
    }

    @Test func movingTheCaptureLeftGrowsTheCanvasAndKeepsOriginZero() throws {
        let session = makeSession()
        let step = Annotation(kind: .step(StepData(center: CGPoint(x: 390, y: 290), diameter: 20, label: StepLabel())), style: Style(stroke: nil, fill: .accentRed))
        session.perform(AddAnnotations([step]))
        let capture = try #require(session.document.annotations.first { $0.id == TestDocuments.captureID })
        var shifts: [CGVector] = []
        session.onCanvasShift = { shifts.append($0) }
        session.perform(UpdateAnnotations(name: "Sposta", before: [capture], after: [AnnotationGeometry.moved(capture, by: CGSize(width: -100, height: 0))]))
        #expect(captureRect(session) == CGRect(x: 0, y: 0, width: 400, height: 300))
        #expect(session.document.canvasSize == PixelSize(width: 500, height: 300))
        #expect(shifts == [CGVector(dx: 100, dy: 0)])
        session.undoManager.undo()
        #expect(session.document.canvasSize == PixelSize(width: 400, height: 300))
        #expect(captureRect(session) == CGRect(x: 0, y: 0, width: 400, height: 300))
        #expect(shifts.last == CGVector(dx: -100, dy: 0))
    }

    @Test func deletingEverythingLeavesAnEmptyCanvas() {
        let session = makeSession()
        session.perform(DeleteAnnotations(ids: Set(session.document.annotations.map(\.id)), in: session.document))
        #expect(session.document.canvasSize == PixelSize(width: 0, height: 0))
        session.undoManager.undo()
        #expect(session.document.canvasSize == PixelSize(width: 400, height: 300))
    }

    @Test func oneActionIsOneUndoStep() throws {
        let session = makeSession()
        let capture = try #require(session.document.annotations.first)
        session.perform(UpdateAnnotations(name: "Sposta", before: [capture], after: [AnnotationGeometry.moved(capture, by: CGSize(width: 50, height: 50))]))
        #expect(session.undoManager.undoActionName == "Sposta")
        session.undoManager.undo()
        #expect(!session.undoManager.canUndo)
    }

    @Test func nudgesAcrossAFitUndoExactly() throws {
        let session = makeSession()
        let original = session.document
        session.selection = [TestDocuments.captureID]
        session.nudge(by: CGSize(width: -1, height: 0))
        session.nudge(by: CGSize(width: -1, height: 0))
        session.nudge(by: CGSize(width: 0, height: 5))
        while session.undoManager.canUndo { session.undoManager.undo() }
        #expect(session.document == original)
    }

    @Test func nudgesThatDoNotChangeTheCanvasStillMerge() throws {
        let session = makeSession()
        let step = Annotation(kind: .step(StepData(center: CGPoint(x: 100, y: 100), diameter: 20, label: StepLabel())), style: Style(stroke: nil, fill: .accentRed))
        session.perform(AddAnnotations([step]))
        session.selection = [step.id]
        session.nudge(by: CGSize(width: 1, height: 0))
        session.nudge(by: CGSize(width: 1, height: 0))
        session.undoManager.undo()
        guard case .step(let data) = session.document.annotations.last?.kind else { Issue.record("no step"); return }
        #expect(data.center == CGPoint(x: 100, y: 100))
    }
}
```

`PinxelKit/Tests/PersistenceTests/DocumentV2Tests.swift`:

```swift
import CoreGraphics
import Foundation
import Testing
import DocumentModel
@testable import Persistence
import Rendering
import AppCore
import PinxelTestSupport

struct DocumentV2Tests {
    @Test func captureIsAnImageObjectAtTheBottom() throws {
        let contents = try CaptureDocumentBuilder.make(image: TestImages.quadrants(), scale: 2, metadata: CaptureMetadata())
        #expect(contents.document.canvasSize == PixelSize(width: 400, height: 300))
        guard case .image(let data) = contents.document.annotations.first?.kind else { Issue.record("no image"); return }
        #expect(data.rect == CGRect(x: 0, y: 0, width: 400, height: 300))
        #expect(contents.images[data.asset] != nil)
    }

    @Test func roundTripKeepsTheDocument() throws {
        let contents = try CaptureDocumentBuilder.make(image: TestImages.quadrants(), scale: 2, metadata: CaptureMetadata())
        let data = try PinxelArchive.write(document: contents.document, images: contents.images, thumbnail: Data([1]), appVersion: "0.1.0")
        let reread = try PinxelArchive.read(data)
        #expect(reread.document == contents.document)
        #expect(!reread.isReadOnly)
    }

    @Test func emptyDocumentMakesAThumbnail() throws {
        let blank = try CaptureDocumentBuilder.blank(scale: 2)
        #expect(blank.document.annotations.isEmpty)
        #expect(blank.document.canvasSize == PixelSize(width: 0, height: 0))
        let thumbnail = try Thumbnailer.make(blank.document, assets: try blank.assetProvider())
        #expect(!thumbnail.isEmpty)
        _ = try PinxelArchive.write(document: blank.document, images: blank.images, thumbnail: thumbnail, appVersion: "0.1.0")
    }

    @Test func versionThreeIsReadOnly() throws {
        let contents = try CaptureDocumentBuilder.make(image: TestImages.quadrants(), scale: 2, metadata: CaptureMetadata())
        var zip = ZipWriter()
        let encoder = JSONEncoder()
        try zip.add(name: "manifest.json", data: encoder.encode(PinxelManifest(format: "pinxel", version: 3, appVersion: "9")), method: .deflate)
        try zip.add(name: "document.json", data: encoder.encode(contents.document), method: .deflate)
        for (ref, data) in contents.images { try zip.add(name: ref.name, data: data, method: .store) }
        #expect(try PinxelArchive.read(zip.finish()).isReadOnly)
    }
}
```

- [ ] **Step 2: The v2 document — `PinxelDocument.swift`**

Replace the `PinxelDocument` struct (keep `ImageAssetRef`, `ColorSpaceID`, `Border`, `CanvasStyle`, `CaptureMetadata` as they are):

```swift
public struct PinxelDocument: Codable, Equatable, Sendable {
    /// Dimensioni della tela in pixel: il rettangolo che racchiude il contenuto (`FitCanvas`). Zero se non c'è niente.
    public var canvasSize: PixelSize
    /// Pixel per punto (2 su Retina).
    public var scale: Double
    public var colorSpace: ColorSpaceID
    /// Margine, colore, bordo e ombra intorno al contenuto.
    public var canvasStyle: CanvasStyle
    /// Ordine = z-order (indice 0 = in fondo). La cattura è un'immagine come le altre.
    public var annotations: [Annotation]
    public var metadata: CaptureMetadata

    public init(
        canvasSize: PixelSize,
        scale: Double = 1,
        colorSpace: ColorSpaceID = .sRGB,
        canvasStyle: CanvasStyle = CanvasStyle(),
        annotations: [Annotation] = [],
        metadata: CaptureMetadata
    ) {
        self.canvasSize = canvasSize
        self.scale = scale
        self.colorSpace = colorSpace
        self.canvasStyle = canvasStyle
        self.annotations = annotations
        self.metadata = metadata
    }

    /// Dimensioni del contenuto (uguali alla tela): il nome che usano libreria, esportazione e strumenti.
    public var imageSize: PixelSize { canvasSize }
}
```

In `ImageOperation.swift` change the comment above `case extend` to `/// Solo nei file della versione 1: allargava la tela.` and leave the enum otherwise unchanged (Task 5 decodes v1 operations with it; the cut-out and resize mappings are used by `ContentEditing`).

- [ ] **Step 3: Validation — `Validation.swift`**

Replace the size checks at the top of `validationError()`:

```swift
        let limit = Self.maxImageSide
        guard (0...limit).contains(canvasSize.width), (0...limit).contains(canvasSize.height),
              (canvasSize.width == 0) == (canvasSize.height == 0) else {
            return "dimensioni della tela fuori dai limiti: \(canvasSize.width)×\(canvasSize.height)"
        }
```

Delete the `sizeError` helper and the loop over `imageOperations`; keep the scale, padding, border and duplicate-ID checks.

- [ ] **Step 4: Commands — `EditCommand.swift`**

Delete `ApplyImageOperation` and `ReplaceBackground`. Add after `UpdateAnnotations`:

```swift
/// Sostituisce tutta la lista degli oggetti (ritaglio, ridimensiona, taglia e ricuci): l'annullamento la rimette com'era.
public struct SetAnnotations: EditCommand {
    public let name: String
    public let before: [Annotation]
    public let after: [Annotation]

    public init(name: String, before: [Annotation], after: [Annotation]) {
        self.name = name
        self.before = before
        self.after = after
    }

    public func apply(to document: inout PinxelDocument) { document.annotations = after }
    public func revert(on document: inout PinxelDocument) { document.annotations = before }
}
```

- [ ] **Step 5: Rendering — `DocumentRenderer.swift`**

Delete `processedKey`, `processedImage`, `processedBackground(for:assets:)` and `RenderError.missingBackground`. Replace the body of `render(_:assets:in:options:)` up to the `RenderContext` creation with:

```swift
        let canvas = canvasSize(for: document)
        let style = document.canvasStyle
        let contentRect = CGRect(x: style.padding, y: style.padding, width: Double(document.imageSize.width), height: Double(document.imageSize.height))

        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.scaleBy(x: options.outputScale, y: options.outputScale)
        ctx.translateBy(x: 0, y: canvas.height)
        ctx.scaleBy(x: 1, y: -1)

        let fullCanvas = CGRect(origin: .zero, size: canvas)
        if let matte = options.matte {
            ctx.setFillColor(matte.cgColor)
            ctx.fill(fullCanvas)
        }
        if let fill = style.backgroundColor {
            ctx.setFillColor(fill.cgColor)
            ctx.fill(fullCanvas)
        }
```

then, after the `RenderContext` creation from Task 2 (pass `background: nil` to `layers`, and drop the `background` parameter from `layers(below:…)` together with its drawing block and key part), draw the content inside a transparency layer so the canvas shadow follows its silhouette, and the border around the content:

```swift
        ctx.saveGState()
        if let shadow = style.shadow {
            ShadowStyle.apply(shadow, to: ctx, outputScale: options.outputScale)
        }
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.translateBy(x: style.padding, y: style.padding)
        for (index, annotation) in document.annotations.enumerated() where !excluded.contains(annotation.id) {
            AnnotationRenderer.draw(annotation, index: index, in: ctx, context: context)
        }
        ctx.endTransparencyLayer()
        ctx.restoreGState()

        if let border = style.border, border.width > 0, !contentRect.isEmpty {
            ctx.setStrokeColor(border.color.cgColor)
            ctx.setLineWidth(border.width)
            ctx.setLineDash(phase: 0, lengths: [])
            ctx.stroke(contentRect.insetBy(dx: border.width / 2, dy: border.width / 2))
        }
```

The old code stroked the border before drawing annotations; drawing it after is intentional (spec §3.1: border around the content). `renderImage` keeps throwing `invalidSize` for a zero canvas.

- [ ] **Step 6: Persistence — `PinxelArchive.swift` and `Thumbnailer.swift`**

In `PinxelArchive`: `currentVersion = 2`; `requiredAssets(of:)` collects only `.image` assets:

```swift
    public static func requiredAssets(of document: PinxelDocument) -> [ImageAssetRef] {
        var refs: [ImageAssetRef] = []
        var seen: Set<ImageAssetRef> = []
        for annotation in document.annotations {
            if case .image(let data) = annotation.kind, seen.insert(data.asset).inserted { refs.append(data.asset) }
        }
        return refs
    }
```

and delete the `if ref == document.background, size != document.canvasSize` check in `read`. Fix `PinxelFileContents`'s comment on `images` ("Byte codificati (PNG/HEIC) di ogni immagine referenziata."). In this task a file with `manifest.version == 1` decodes as v2 but without its capture (the `background` key is ignored); Task 5 converts it properly. Do not ship between Task 4 and Task 5.

In `Thumbnailer.make`, before rendering:

```swift
        // Tela vuota (tutto eliminato): una miniatura trasparente di 1 pixel, così il salvataggio riesce.
        guard document.imageSize.width > 0, document.imageSize.height > 0 else {
            guard let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let empty = ctx.makeImage() else { throw RenderError.contextCreationFailed }
            return try ImageCodec.encode(empty, type: .png)
        }
```

(add `import CoreGraphics`).

- [ ] **Step 7: AppCore — `CaptureDocumentBuilder.swift`**

```swift
    /// Nuovo documento con la cattura come immagine in fondo alla pila, grande quanto la tela.
    public static func make(image: CGImage, scale: Double, metadata: CaptureMetadata) throws -> PinxelFileContents {
        let (ref, data) = try ImageCodec.encodeBackground(image)
        let size = PixelSize(width: image.width, height: image.height)
        let capture = Annotation(kind: .image(PlacedImageData(rect: CGRect(origin: .zero, size: size.cgSize), asset: ref)),
                                 style: Style(stroke: nil, lineWidth: 0))
        let document = PinxelDocument(canvasSize: size, scale: scale, annotations: [capture], metadata: metadata)
        return PinxelFileContents(document: document, images: [ref: data])
    }

    /// Documento vuoto, per cominciare senza cattura (Nuovo): poi si incolla, si trascina o si disegna.
    public static func blank(scale: Double) throws -> PinxelFileContents {
        PinxelFileContents(document: PinxelDocument(canvasSize: PixelSize(width: 0, height: 0), scale: scale, metadata: CaptureMetadata()), images: [:])
    }
```

In `App/Pinxel/AppEnvironment.swift` replace the `blank(pointSize: CGSize(width: 800, height: 500), scale: …)` call with `blank(scale: …)` keeping the same scale argument.

- [ ] **Step 8: Session — `EditorSession.swift`**

Add the callback and replace `perform`, `undo`, `redo`:

```swift
    /// Chiamata quando un comando, annulla o ripeti trasla tutti gli oggetti per adattare la tela:
    /// la vista sposta lo scorrimento della stessa quantità, così sullo schermo non salta niente.
    @ObservationIgnored public var onCanvasShift: ((CGVector) -> Void)?

    /// Esegue e registra un comando, poi adatta la tela al contenuto nello stesso passo di annulla.
    /// Con `coalescingKey`, un `UpdateAnnotations` che segue entro 1 s un altro con la stessa chiave sugli stessi oggetti
    /// si annulla insieme a lui, ma solo se nessuno dei due ha spostato la tela: dopo un adattamento le coordinate
    /// di `before` non sono più quelle del passo precedente.
    public func perform(_ command: any EditCommand, coalescingKey: String? = nil) {
        guard !isReadOnly else { return }
        preview = nil
        if let key = coalescingKey, let box = lastBox, let last = coalescing, last.key == key,
           now().timeIntervalSince(last.date) < Self.coalescingInterval,
           let previous = box.command as? UpdateAnnotations,
           let next = command as? UpdateAnnotations,
           let merged = previous.merged(with: next) {
            var trial = document
            next.apply(to: &trial)
            if FitCanvas(in: trial) == nil {
                document = trial
                box.command = merged
                coalescing = (key, now())
                pruneSelection()
                return
            }
        }
        command.apply(to: &document)
        var recorded = command
        if let fit = FitCanvas(in: document) {
            fit.apply(to: &document)
            recorded = CommandGroup(name: command.name, commands: [command, fit])
        }
        let box = CommandBox(recorded)
        if undoManager.groupsByEvent {
            registerUndo(box)
        } else {
            undoManager.beginUndoGrouping()
            registerUndo(box)
            undoManager.endUndoGrouping()
        }
        lastBox = recorded is UpdateAnnotations ? box : nil
        coalescing = recorded is UpdateAnnotations ? coalescingKey.map { ($0, now()) } : nil
        pruneSelection()
        notifyShift(of: recorded, sign: 1)
    }

    private func undo(_ box: CommandBox) {
        box.command.revert(on: &document)
        finishHistoryStep()
        undoManager.registerUndo(withTarget: self) { session in
            MainActor.assumeIsolated { session.redo(box) }
        }
        undoManager.setActionName(box.command.name)
        notifyShift(of: box.command, sign: -1)
    }

    private func redo(_ box: CommandBox) {
        box.command.apply(to: &document)
        finishHistoryStep()
        registerUndo(box)
        notifyShift(of: box.command, sign: 1)
    }

    private func notifyShift(of command: any EditCommand, sign: Double) {
        guard let fit = (command as? CommandGroup)?.commands.compactMap({ $0 as? FitCanvas }).first, fit.offset != .zero else { return }
        onCanvasShift?(CGVector(dx: fit.offset.dx * sign, dy: fit.offset.dy * sign))
    }
```

`replaceDocument` stays as is (no fit: the replaced document comes from disk).

- [ ] **Step 9: Editor wiring**

**`ImagePlacement.swift`** — add:

```swift
    /// Riquadro di un'immagine aggiunta (trascinata o ⌥⌘V), centrata in `center`, alla densità del documento;
    /// la tela si adatterà a lei, quindi non la si spinge dentro. Solo il lato massimo la rimpicciolisce.
    public static func centered(pixelSize: CGSize, imageScale: Double, documentScale: Double, center: CGPoint,
                                maxSide: Int = PinxelDocument.maxImageSide) -> CGRect {
        let factor = documentScale / max(imageScale, 1)
        var width = pixelSize.width * factor
        var height = pixelSize.height * factor
        let shrink = min(1, Double(maxSide) / max(width, 1), Double(maxSide) / max(height, 1))
        width = max(1, (width * shrink).rounded())
        height = max(1, (height * shrink).rounded())
        return CGRect(x: (center.x - width / 2).rounded(), y: (center.y - height / 2).rounded(), width: width, height: height)
    }
```

Keep `place(...)` for the ⌘V size computation (`adaptCanvas: true`), and delete its now unused non-adapt branch only if no caller remains.

**`CanvasView.swift`**:

1. `isBlank`:

```swift
    /// Documento di Nuovo ancora intatto: nessun oggetto e stile della tela di base.
    public var isBlank: Bool {
        session.document.annotations.isEmpty && session.document.canvasStyle == CanvasStyle()
    }
```

Delete `blankBackground` and `isFullyTransparent` if nothing else uses them (search the tests: `BlankCanvasTests` uses `isFullyTransparent`; rewrite those tests around `isBlank`).

2. `pasteImage(adaptCanvas: true)`: replace the `ReplaceBackground` block with

```swift
        guard let replacement = ImagePlacement.resized(cgImage, to: placement.imageSize),
              let asset = session.assets.add(replacement) else { return false }
        // Un'immagine nuova al posto della cattura: la si mostra intera, come appena aperta.
        followsWindow = true
        session.perform(ContentEditing.replacingBottomImage(in: document.annotations, asset: asset,
                                                            size: placement.imageSize.cgSize, newID: UUID()))
        session.selection = []
        return true
```

(`placement` is still computed with `adaptCanvas: true`, `imageSize: document.imageSize`.)

3. `insertImage`: drop the `growsCanvas` parameter (update both callers: `pasteImage` and `performDragOperation`) and its `.extend` block; compute the rect with

```swift
        let rect = ImagePlacement.centered(
            pixelSize: CGSize(width: cgImage.width, height: cgImage.height),
            imageScale: PixelDensity.scale(pixelWidth: original.width, pointWidth: image.size.width),
            documentScale: document.scale,
            center: viewPoint.map { documentPoint(fromView: $0) } ?? visibleDocumentCenter()
        )
        guard let asset = session.assets.add(cgImage) else { return false }
        let annotation = Annotation(kind: .image(PlacedImageData(rect: rect, asset: asset)), style: Style(stroke: nil, lineWidth: 0))
        session.perform(AddAnnotations([annotation], name: name))
        session.selection = [annotation.id]
        return true
```

Update the doc comment ("la tela si adatta all'oggetto"). In `visibleDocumentCenter()`, return the document point under the view centre when the canvas is empty (`image.isEmpty`): `documentPoint(fromView: viewCenter)`.

4. Crop and cut requests. In `ToolController.swift` add to `ToolResult` two properties with `nil` defaults in `init`:

```swift
    /// Ritaglio da applicare a tutto il contenuto (servono i pixel: lo fa la vista).
    public var crop: PixelRect?
    /// Fascia da togliere con Taglia e ricuci.
    public var cut: CutOut?
```

In `commitCrop` return `ToolResult(selection: [], tool: .select, crop: pixel)` instead of the `ApplyImageOperation` command; in `handleCut`'s `.up` return `ToolResult(selection: [], cut: cut)`.

In `CanvasView.apply(_:)` after `if let command = result.command { … }`:

```swift
        if let rect = result.crop { applyContentEdit("Ritaglia") { ContentEditing.cropped($0, to: rect, images: session.assets.image(for:), add: { session.assets.add($0) }) } }
        if let cut = result.cut {
            let canvas = session.document.imageSize
            applyContentEdit("Taglia e ricuci") { ContentEditing.cut($0, cut, canvas: canvas, images: session.assets.image(for:), add: { session.assets.add($0) }) }
        }
```

and add

```swift
    /// Un ritaglio o un taglio su tutto il contenuto: un solo passo di annulla (la sessione adatta la tela).
    private func applyContentEdit(_ name: String, _ edit: ([Annotation]) -> [Annotation]) {
        let before = session.document.annotations
        let after = edit(before)
        guard after != before else { return NSSound.beep() }
        session.perform(SetAnnotations(name: name, before: before, after: after))
    }
```

5. **`ImageEditing.swift`** — replace `ResizeDraft.operation` with

```swift
    /// `nil` se le dimensioni non cambiano.
    public var targetSize: PixelSize? {
        let size = PixelSize(width: width, height: height)
        return size == original ? nil : size
    }
```

and in `App/Pinxel/Editor/ImageSheets.swift` use `draft.targetSize == nil` for `.disabled` and:

```swift
    private func apply() {
        if let size = draft.targetSize {
            let session = model.session
            let before = session.document.annotations
            session.perform(SetAnnotations(name: "Ridimensiona", before: before,
                                           after: ContentEditing.scaled(before, from: draft.original, to: size)))
        }
        dismiss()
    }
```

- [ ] **Step 10: Test support — `TestDocuments.swift`**

```swift
    /// La cattura di ogni documento di prova: un'immagine in fondo alla pila, grande quanto la tela.
    public static let captureID = id(999)

    public static func capture(size: PixelSize) -> Annotation {
        Annotation(id: captureID, kind: .image(PlacedImageData(rect: CGRect(origin: .zero, size: size.cgSize), asset: background)),
                   style: Style(stroke: nil, lineWidth: 0))
    }

    public static func document(
        annotations: [Annotation] = allKindsAnnotations(),
        size: PixelSize = PixelSize(width: 400, height: 300),
        scale: Double = 2
    ) -> PinxelDocument {
        PinxelDocument(
            canvasSize: size,
            scale: scale,
            annotations: [capture(size: size)] + annotations,
            metadata: CaptureMetadata(
                captureDate: Date(timeIntervalSinceReferenceDate: 800_000_000),
                appName: "Finder",
                bundleIdentifier: "com.apple.finder",
                windowTitle: "Documenti"
            )
        )
    }
```

and, in a new file `PinxelKit/Tests/PinxelTestSupport/DocumentHelpers.swift`:

```swift
import DocumentModel

extension PinxelDocument {
    /// Gli oggetti del documento di prova senza la cattura in fondo.
    public var userAnnotations: [Annotation] { annotations.filter { $0.id != TestDocuments.captureID } }
}
```

- [ ] **Step 11: Build the package and migrate the tests**

Run: `python3 …/pt.py`. Fix every compile error, then every failure, with these rules (decide each case by what the user would see; never weaken an assertion to make it pass):

- `PinxelDocument(background:canvasSize:…)` → `PinxelDocument(canvasSize:…, annotations: [TestDocuments.capture(size: …)] + …)`.
- Counting or indexing `annotations` in a `TestDocuments.document(...)` → use `userAnnotations`, or index from the end.
- `ApplyImageOperation(.crop(r), in: d)` in tests → `SetAnnotations(name: "Ritaglia", before: d.annotations, after: ContentEditing.cropped(...))`, or drive the crop through `ToolController` and assert `result.crop`.
- `ReplaceBackground` tests → `ContentEditing.replacingBottomImage`.
- `.extend`/`growsCanvas` tests (`DropGrowsCanvasTests`) → rewrite as: dropping an image beyond the right edge grows the canvas to include it, and dropping beyond the left edge grows it to the left with the capture shifted right; one ⌘Z reverts both.
- Tests that expect a blur over a placed image to leave it sharp, or that compare against the old background-only sampling, follow the new rule (spec §4).
- `RenderError.missingBackground` expectations → a missing capture asset renders the grey placeholder (`placedImageAndMissingPlaceholder` already covers that).
- `HostileDocumentTests` / `PinxelArchiveTests` that build v1 JSON by hand: keep them for Task 5 (mark with `.disabled("v1 conversion: Task 5")` now and re-enable there); v2 hostile cases (huge `canvasSize`, duplicate IDs, missing asset) keep working.
- `BlankCanvasTests`: a blank document is `blank(scale:)` (no objects); `isBlank` is false as soon as anything is added.
- Snapshots: if `canvas-style.png` changes, re-record with `PINXEL_RECORD_SNAPSHOTS=1`, open it with Read, and check the shadow and border still surround the image exactly.

Expected at the end: `exit 0`, test count ≥ 497 + the new tests minus none removed (each deleted test is replaced by its v2 equivalent).

- [ ] **Step 12: Build the app**

Run: `xcodebuild -project Pinxel.xcodeproj -scheme Pinxel -configuration Debug build 2>&1 | tail -5` → `** BUILD SUCCEEDED **`. Fix remaining app references (`grep -rn "background:\|imageOperations\|ApplyImageOperation\|ReplaceBackground\|growsCanvas\|\.operation\b" App/Pinxel`).

- [ ] **Step 13: Commit**

```bash
git add -A PinxelKit App
git commit -m "feat(model): the capture is an image object and the canvas fits the content" -m "Document format 2: no background or image operations; every command is followed by FitCanvas in the same undo step. Crop, resize and cut-out work on all objects; paste replaces the bottom image." -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Version 1 files convert on open

**Files:**
- Create: `PinxelKit/Sources/Persistence/LegacyDocumentV1.swift`
- Modify: `PinxelKit/Sources/Persistence/PinxelArchive.swift`
- Test: `PinxelKit/Tests/PersistenceTests/LegacyConversionTests.swift`; re-enable the tests disabled in Task 4

**Interfaces:**
- Consumes: `ImageOperation`, `BackgroundProcessor.process`, `ImageCodec`, `FitCanvas`.
- Produces: `struct LegacyDocumentV1: Codable` (internal) with `validationError()`, `imageSize`, `converted(capture: ImageAssetRef) -> PinxelDocument`; `PinxelArchive.read`/`readDocument` accept version 1.

- [ ] **Step 1: Write the failing tests**

```swift
import CoreGraphics
import Foundation
import Testing
import DocumentModel
@testable import Persistence
import Rendering
import PinxelTestSupport

struct LegacyConversionTests {
    func v1Archive(operations: [ImageOperation], annotations: [Annotation], background: CGImage = TestImages.quadrants()) throws -> Data {
        let legacy = LegacyDocumentV1(background: ImageAssetRef(name: "background.png"), canvasSize: PixelSize(width: background.width, height: background.height),
                                      scale: 2, colorSpace: .sRGB, imageOperations: operations, canvasStyle: CanvasStyle(),
                                      annotations: annotations, metadata: CaptureMetadata(captureDate: Date(timeIntervalSinceReferenceDate: 1)))
        var zip = ZipWriter()
        let encoder = JSONEncoder()
        try zip.add(name: "manifest.json", data: encoder.encode(PinxelManifest(format: "pinxel", version: 1, appVersion: "0.1.0")), method: .deflate)
        try zip.add(name: "document.json", data: encoder.encode(legacy), method: .deflate)
        try zip.add(name: "background.png", data: ImageCodec.encode(background, type: .png), method: .store)
        return try zip.finish()
    }

    var step: Annotation { Annotation(id: TestDocuments.id(7), kind: .step(StepData(center: CGPoint(x: 50, y: 50), diameter: 20, label: StepLabel())), style: Style(stroke: nil, fill: .accentRed)) }

    @Test func plainCaptureBecomesAnImageObject() throws {
        let contents = try PinxelArchive.read(try v1Archive(operations: [], annotations: [step]))
        #expect(contents.document.canvasSize == PixelSize(width: 400, height: 300))
        #expect(contents.document.annotations.count == 2)
        guard case .image(let data) = contents.document.annotations[0].kind else { Issue.record("no image"); return }
        #expect(data.rect == CGRect(x: 0, y: 0, width: 400, height: 300))
        #expect(data.asset.name == "background.png")
        #expect(contents.document.annotations[1] == step)
    }

    @Test(arguments: [
        ImageOperation.crop(PixelRect(x: 10, y: 20, width: 200, height: 100)),
        .resize(PixelSize(width: 200, height: 150)),
        .cutOut(CutOut(axis: .vertical, start: 100, length: 50)),
        .extend(PixelSize(width: 500, height: 400)),
    ])
    func operationsAreBakedIntoTheImage(_ operation: ImageOperation) throws {
        let contents = try PinxelArchive.read(try v1Archive(operations: [operation], annotations: []))
        let expected = operation.resultSize(from: PixelSize(width: 400, height: 300))
        guard case .image(let data) = contents.document.annotations[0].kind else { Issue.record("no image"); return }
        let pixels = try #require(try contents.assetProvider().image(for: data.asset))
        #expect(PixelSize(width: pixels.width, height: pixels.height) == expected)
        #expect(contents.document.canvasSize == expected)
    }

    @Test func renderMatchesTheProcessedBackground() throws {
        let operation = ImageOperation.crop(PixelRect(x: 200, y: 0, width: 200, height: 150))
        let contents = try PinxelArchive.read(try v1Archive(operations: [operation], annotations: []))
        let rendered = try DocumentRenderer().renderImage(contents.document, assets: try contents.assetProvider())
        let reference = try #require(BackgroundProcessor.process(TestImages.quadrants(), operations: [operation]))
        #expect(PixelBuffer(rendered).differingPixelFraction(from: PixelBuffer(reference), channelTolerance: 1) == 0)
    }

    @Test func annotationOutsideTheImageGrowsTheCanvas() throws {
        let outside = Annotation(kind: .step(StepData(center: CGPoint(x: 420, y: 150), diameter: 20, label: StepLabel())), style: Style(stroke: nil, fill: .accentRed))
        let contents = try PinxelArchive.read(try v1Archive(operations: [], annotations: [outside]))
        #expect(contents.document.canvasSize == PixelSize(width: 430, height: 300))
    }

    @Test func lightReadConvertsWithoutPixels() throws {
        let document = try PinxelArchive.readDocument(try v1Archive(operations: [.crop(PixelRect(x: 0, y: 0, width: 120, height: 80))], annotations: []))
        #expect(document.imageSize == PixelSize(width: 120, height: 80))
    }

    @Test func v1RoundTripThroughV2() throws {
        let first = try PinxelArchive.read(try v1Archive(operations: [.crop(PixelRect(x: 0, y: 0, width: 300, height: 200))], annotations: [step]))
        let saved = try PinxelArchive.write(document: first.document, images: first.images, thumbnail: Data([1]), appVersion: "0.1.0")
        let second = try PinxelArchive.read(saved)
        #expect(second.document == first.document)
        let a = try DocumentRenderer().renderImage(first.document, assets: try first.assetProvider())
        let b = try DocumentRenderer().renderImage(second.document, assets: try second.assetProvider())
        #expect(PixelBuffer(a).differingPixelFraction(from: PixelBuffer(b), channelTolerance: 0) == 0)
    }

    @Test func invalidV1IsRejected() throws {
        let data = try v1Archive(operations: [.resize(PixelSize(width: 0, height: 10))], annotations: [])
        #expect(throws: (any Error).self) { try PinxelArchive.read(data) }
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `python3 …/pt.py LegacyConversionTests` → compile error `cannot find 'LegacyDocumentV1'`.

- [ ] **Step 3: Write `LegacyDocumentV1.swift`**

```swift
import DocumentModel
import Foundation

/// Il documento della versione 1 del formato: cattura come sfondo fisso più operazioni sull'immagine.
/// Si legge solo per convertirlo; Pinxel salva sempre la versione 2.
struct LegacyDocumentV1: Codable, Equatable {
    var background: ImageAssetRef
    var canvasSize: PixelSize
    var scale: Double
    var colorSpace: ColorSpaceID
    var imageOperations: [ImageOperation]
    var canvasStyle: CanvasStyle
    var annotations: [Annotation]
    var metadata: CaptureMetadata

    /// Dimensioni dello sfondo dopo le operazioni.
    var imageSize: PixelSize {
        imageOperations.reduce(canvasSize) { size, operation in operation.resultSize(from: size) }
    }

    /// Le regole della versione 1: sfondo e ogni risultato intermedio dentro i limiti.
    func validationError() -> String? {
        let limit = PinxelDocument.maxImageSide
        func sizeError(_ size: PixelSize, _ what: String) -> String? {
            guard (1...limit).contains(size.width), (1...limit).contains(size.height) else {
                return "\(what) fuori dai limiti: \(size.width)×\(size.height)"
            }
            return nil
        }
        if let error = sizeError(canvasSize, "dimensioni immagine") { return error }
        var size = canvasSize
        for operation in imageOperations {
            size = operation.resultSize(from: size)
            if let error = sizeError(size, "risultato di \(operation.name)") { return error }
        }
        return nil
    }

    /// Documento della versione 2: lo sfondo elaborato (`capture`) diventa l'immagine in fondo, le annotazioni restano
    /// dove sono (erano già nello spazio dopo le operazioni), poi la tela si adatta al contenuto.
    func converted(capture: ImageAssetRef) -> PinxelDocument {
        let size = imageSize
        let image = Annotation(kind: .image(PlacedImageData(rect: CGRect(origin: .zero, size: size.cgSize), asset: capture)),
                               style: Style(stroke: nil, lineWidth: 0))
        var document = PinxelDocument(canvasSize: size, scale: scale, colorSpace: colorSpace, canvasStyle: canvasStyle,
                                      annotations: [image] + annotations, metadata: metadata)
        FitCanvas(in: document)?.apply(to: &document)
        return document
    }
}
```

- [ ] **Step 4: Read version 1 in `PinxelArchive.swift`**

Change `manifestAndDocument` to return the legacy document when `manifest.version < 2`:

```swift
    /// Manifest e documento validati, senza leggere le immagini. Un file della versione 1 torna anche come `legacy`.
    private static func manifestAndDocument(_ zip: ZipReader) throws -> (PinxelManifest, PinxelDocument, LegacyDocumentV1?) {
        // … lettura e controllo del manifest come oggi …
        let json: Data
        do { json = try zip.data(for: "document.json") } catch ZipError.missingEntry(_) {
            throw PinxelArchiveError.invalidDocument("document.json missing")
        }
        if manifest.version < 2 {
            let legacy: LegacyDocumentV1
            do { legacy = try decoder.decode(LegacyDocumentV1.self, from: json) } catch {
                throw PinxelArchiveError.invalidDocument(String(describing: error))
            }
            if let reason = legacy.validationError() { throw PinxelArchiveError.invalidDocument(reason) }
            let document = legacy.converted(capture: legacy.background)
            if let reason = document.validationError() { throw PinxelArchiveError.invalidDocument(reason) }
            return (manifest, document, legacy)
        }
        let document: PinxelDocument
        do { document = try decoder.decode(PinxelDocument.self, from: json) } catch {
            throw PinxelArchiveError.invalidDocument(String(describing: error))
        }
        if let reason = document.validationError() { throw PinxelArchiveError.invalidDocument(reason) }
        return (manifest, document, nil)
    }
```

Keep the existing `ZipError` re-throw behaviour for errors other than a missing entry. `readDocument` returns `.1`.

In `read`, after the asset loop, when `legacy != nil`:

```swift
        if let legacy {
            guard let backgroundData = images[legacy.background],
                  let size = ImageCodec.pixelSize(of: backgroundData), size == legacy.canvasSize else {
                throw PinxelArchiveError.invalidDocument("lo sfondo non corrisponde alle dimensioni del documento")
            }
            // Senza operazioni lo sfondo resta il file che è; altrimenti lo si elabora una volta e lo si salva come PNG.
            if !legacy.imageOperations.isEmpty {
                guard let processed = BackgroundProcessor.process(try ImageCodec.decode(backgroundData), operations: legacy.imageOperations) else {
                    throw PinxelArchiveError.invalidDocument("impossibile elaborare lo sfondo")
                }
                let ref = ImageAssetRef(name: "assets/capture-v1.png")
                images[legacy.background] = nil
                images[ref] = try ImageCodec.encode(processed, type: .png)
                document = legacy.converted(capture: ref)
            }
        }
```

(`document` becomes `var`.) `requiredAssets(of: document)` already lists `background.png` for the converted plain capture, so the asset loop reads it. `isReadOnly: manifest.version > currentVersion` is unchanged.

- [ ] **Step 5: Run the tests and re-enable the disabled ones**

Run: `python3 …/pt.py LegacyConversionTests` → `exit 0 | tests 10`. Remove the `.disabled("v1 conversion: Task 5")` traits added in Task 4 and run `python3 …/pt.py PersistenceTests` → `exit 0`.

- [ ] **Step 6: Full suite and commit**

Run: `python3 …/pt.py` → `exit 0`.

```bash
git add PinxelKit/Sources/Persistence PinxelKit/Tests/PersistenceTests
git commit -m "feat(persistence): version 1 files convert to image objects on open" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Nothing jumps when the canvas adapts

**Files:**
- Modify: `PinxelKit/Sources/EditorUI/Viewport.swift`, `PinxelKit/Sources/EditorUI/CanvasView.swift`
- Test: `PinxelKit/Tests/EditorUITests/CanvasShiftTests.swift`

**Interfaces:**
- Consumes: `EditorSession.onCanvasShift` (Task 4).
- Produces: `Viewport.shift(byCanvas offset: CGVector)`, `Viewport.keepInView(canvasSize:in:margin:)`.

- [ ] **Step 1: Write the failing tests**

```swift
import AppKit
import DocumentModel
import PinxelTestSupport
import Rendering
import Testing
@testable import EditorUI

@MainActor
struct CanvasShiftTests {
    func makeCanvas() -> CanvasView {
        let undo = UndoManager()
        undo.groupsByEvent = false
        let step = Annotation(id: TestDocuments.id(1), kind: .step(StepData(center: CGPoint(x: 300, y: 200), diameter: 20, label: StepLabel())),
                              style: Style(stroke: nil, fill: .accentRed))
        let session = EditorSession(document: TestDocuments.document(annotations: [step], size: PixelSize(width: 400, height: 300), scale: 1),
                                    assets: DictionaryAssetProvider([TestDocuments.background: TestImages.quadrants()]), undoManager: undo)
        let canvas = CanvasView(model: EditorModel(session: session))
        canvas.frame = NSRect(x: 0, y: 0, width: 1000, height: 800)
        canvas.needsLayout = true
        canvas.layoutSubtreeIfNeeded()
        return canvas
    }

    func stepCenter(_ canvas: CanvasView) -> CGPoint? {
        guard case .step(let data) = canvas.model.session.document.annotations.first(where: { $0.id == TestDocuments.id(1) })?.kind else { return nil }
        return canvas.viewPoint(fromDocument: data.center)
    }

    @Test func movingTheCaptureLeftKeepsOtherObjectsInPlace() throws {
        let canvas = makeCanvas()
        let before = try #require(stepCenter(canvas))
        let session = canvas.model.session
        let capture = try #require(session.document.annotations.first { $0.id == TestDocuments.captureID })
        session.perform(UpdateAnnotations(name: "Sposta", before: [capture], after: [AnnotationGeometry.moved(capture, by: CGSize(width: -150, height: -50))]))
        canvas.layoutSubtreeIfNeeded()
        let after = try #require(stepCenter(canvas))
        #expect(abs(after.x - before.x) < 0.5 && abs(after.y - before.y) < 0.5)
        session.undoManager.undo()
        canvas.layoutSubtreeIfNeeded()
        let undone = try #require(stepCenter(canvas))
        #expect(abs(undone.x - before.x) < 0.5 && abs(undone.y - before.y) < 0.5)
    }

    @Test func keepInViewDoesNotRecenterAVisibleCanvas() {
        var viewport = Viewport(documentScale: 1, zoom: 1, origin: CGPoint(x: 30, y: 40))
        viewport.keepInView(canvasSize: CGSize(width: 100, height: 100), in: CGSize(width: 1000, height: 800))
        #expect(viewport.origin == CGPoint(x: 30, y: 40))
    }

    @Test func keepInViewBringsBackACanvasThatLeftTheView() {
        var viewport = Viewport(documentScale: 1, zoom: 1, origin: CGPoint(x: 990, y: 40))
        viewport.keepInView(canvasSize: CGSize(width: 100, height: 100), in: CGSize(width: 1000, height: 800))
        #expect(viewport.origin.x == 1000 - 100 - 20)
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `python3 …/pt.py CanvasShiftTests` → compile error `keepInView` not found.

- [ ] **Step 3: `Viewport.swift`**

```swift
    /// Gli oggetti sono stati traslati di `offset` (pixel del documento) per adattare la tela: la si sposta al contrario,
    /// così sullo schermo restano dove erano.
    public mutating func shift(byCanvas offset: CGVector) {
        origin.x -= offset.dx * pointsPerPixel
        origin.y -= offset.dy * pointsPerPixel
    }

    /// Dopo una modifica: la tela resta dov'è finché se ne vede abbastanza; non si ricentra (gli oggetti salterebbero).
    /// Una tela più piccola della vista resta tutta dentro, una più grande non lascia vuoti oltre `margin`.
    public mutating func keepInView(canvasSize: CGSize, in viewSize: CGSize, margin: Double = 20) {
        func axis(_ origin: Double, content: Double, view: Double) -> Double {
            if content + 2 * margin <= view { return min(max(origin, margin), view - content - margin) }
            return min(margin, max(view - content - margin, origin))
        }
        origin = CGPoint(x: axis(origin.x, content: canvasSize.width * pointsPerPixel, view: viewSize.width),
                         y: axis(origin.y, content: canvasSize.height * pointsPerPixel, view: viewSize.height))
    }
```

- [ ] **Step 4: `CanvasView.swift`**

1. In `init`, after `observeModel()`:

```swift
        model.session.onCanvasShift = { [weak self] offset in
            guard let self else { return }
            // Da qui la tela non segue più la finestra: ricentrarla farebbe saltare gli oggetti.
            self.followsWindow = false
            self.viewport.shift(byCanvas: offset)
        }
```

2. In the `observeModel` `onChange` block and in `layout()`, replace `viewport.constrain(canvasSize:in:)` with `viewport.keepInView(canvasSize:in:)` (leave `pan`, zoom commands and `fit` as they are).

3. In `draw(_:)`: clip to the canvas only when no gesture preview is shown, so an object dragged past the edge stays visible until the canvas adapts on release:

```swift
        ctx.saveGState()
        if session.preview == nil { ctx.clip(to: canvasRect) }
```

4. The empty canvas (`imageSize` zero) has nothing to fit: in `layout()` and `observeModel`, skip `viewport.fit` when `canvasSize` is zero (the guard in `Viewport.fit` already returns early; check that `followsWindow` stays true so the first pasted or dropped image is shown whole).

- [ ] **Step 5: Run the tests**

Run: `python3 …/pt.py CanvasShiftTests` → `exit 0 | tests 3`. Run `python3 …/pt.py EditorUITests` → `exit 0` (tests that relied on recentring after a crop now use `keepInView`; if one fails, check whether the user would see a jump before changing it).

- [ ] **Step 6: Full suite and commit**

Run: `python3 …/pt.py` → `exit 0`.

```bash
git add PinxelKit/Sources/EditorUI PinxelKit/Tests/EditorUITests
git commit -m "feat(editor): objects stay in place on screen when the canvas adapts" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Selecting images without losing the marquee

**Files:**
- Modify: `PinxelKit/Sources/EditorUI/ToolController.swift`, `PinxelKit/Sources/EditorUI/HitTesting.swift`
- Test: `PinxelKit/Tests/EditorUITests/ImageSelectionTests.swift`

**Interfaces:**
- Consumes: `ToolController.handle(_:document:selection:)`.
- Produces: `Gesture.pressImage(start: CGPoint, id: UUID, base: Set<UUID>, shift: Bool)` (private); `HitTesting.ids(intersecting:in:)` requires images to be wholly inside.

- [ ] **Step 1: Write the failing tests**

```swift
import DocumentModel
import Foundation
import PinxelTestSupport
import Testing
@testable import EditorUI

struct ImageSelectionTests {
    let step = Annotation(id: TestDocuments.id(1), kind: .step(StepData(center: CGPoint(x: 100, y: 100), diameter: 20, label: StepLabel())),
                          style: Style(stroke: nil, fill: .accentRed))
    var document: PinxelDocument { TestDocuments.document(annotations: [step], size: PixelSize(width: 400, height: 300)) }

    func controller() -> ToolController {
        let controller = ToolController()
        controller.tool = .select
        return controller
    }

    @Test func clickOnTheCaptureSelectsIt() {
        let tool = controller()
        _ = tool.handle(.down(CGPoint(x: 300, y: 200), [], clickCount: 1), document: document, selection: [])
        let up = tool.handle(.up(CGPoint(x: 300, y: 200), []), document: document, selection: [])
        #expect(up.selection == [TestDocuments.captureID])
    }

    @Test func dragFromAnUnselectedCaptureDrawsTheMarquee() {
        let tool = controller()
        _ = tool.handle(.down(CGPoint(x: 80, y: 80), [], clickCount: 1), document: document, selection: [])
        let drag = tool.handle(.drag(CGPoint(x: 130, y: 130), []), document: document, selection: [])
        #expect(drag.marquee != nil)
        #expect(drag.preview == nil)
        let up = tool.handle(.up(CGPoint(x: 130, y: 130), []), document: document, selection: [])
        #expect(up.selection == [step.id])
        #expect(up.command == nil)
    }

    @Test func dragFromTheSelectedCaptureMovesIt() throws {
        let tool = controller()
        _ = tool.handle(.down(CGPoint(x: 300, y: 200), [], clickCount: 1), document: document, selection: [TestDocuments.captureID])
        _ = tool.handle(.drag(CGPoint(x: 320, y: 200), []), document: document, selection: [TestDocuments.captureID])
        let up = tool.handle(.up(CGPoint(x: 320, y: 200), []), document: document, selection: [TestDocuments.captureID])
        let update = try #require(up.command as? UpdateAnnotations)
        #expect(update.after.map(\.id) == [TestDocuments.captureID])
    }

    @Test func shiftClickAddsTheCapture() {
        let tool = controller()
        _ = tool.handle(.down(CGPoint(x: 300, y: 200), [.shift], clickCount: 1), document: document, selection: [step.id])
        let up = tool.handle(.up(CGPoint(x: 300, y: 200), [.shift]), document: document, selection: [step.id])
        #expect(up.selection == [step.id, TestDocuments.captureID])
    }

    @Test func annotationsStillMoveImmediately() throws {
        let tool = controller()
        _ = tool.handle(.down(CGPoint(x: 100, y: 100), [], clickCount: 1), document: document, selection: [])
        _ = tool.handle(.drag(CGPoint(x: 120, y: 100), []), document: document, selection: [step.id])
        let up = tool.handle(.up(CGPoint(x: 120, y: 100), []), document: document, selection: [step.id])
        #expect(up.command is UpdateAnnotations)
    }

    @Test func marqueeSelectsImagesOnlyWhenWhollyInside() {
        let annotations = document.annotations
        #expect(HitTesting.ids(intersecting: CGRect(x: 50, y: 50, width: 100, height: 100), in: annotations) == [step.id])
        #expect(HitTesting.ids(intersecting: CGRect(x: -10, y: -10, width: 420, height: 320), in: annotations) == [step.id, TestDocuments.captureID])
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `python3 …/pt.py ImageSelectionTests` → `dragFromAnUnselectedCaptureDrawsTheMarquee`, `clickOnTheCaptureSelectsIt` (the down already selects), and `marqueeSelectsImagesOnlyWhenWhollyInside` fail.

- [ ] **Step 3: `HitTesting.ids(intersecting:in:)`**

```swift
    /// ID delle annotazioni il cui riquadro (ruotato) interseca `rect`. Le immagini contano solo se ci stanno tutte:
    /// la cattura copre la tela e altrimenti ogni riquadro la prenderebbe.
    public static func ids(intersecting rect: CGRect, in annotations: [Annotation]) -> Set<UUID> {
        let area = rect.standardized
        return Set(annotations.filter { annotation in
            let bounds = worldBounds(annotation)
            guard !bounds.isNull else { return false }
            if case .image = annotation.kind { return area.contains(bounds) }
            return bounds.intersects(area)
        }.map(\.id))
    }
```

- [ ] **Step 4: `ToolController` — press on an unselected image**

Add the gesture case:

```swift
        /// Premuto su un'immagine non selezionata: un clic la seleziona, un trascinamento disegna il riquadro.
        case pressImage(start: CGPoint, id: UUID, base: Set<UUID>, shift: Bool)
```

In `handleSelect` `.down`, right after `if let hit = HitTesting.annotation(...) {` and the double-click branch:

```swift
                if case .image = hit.kind, !selection.contains(hit.id) {
                    gesture = .pressImage(start: point, id: hit.id, base: modifiers.contains(.shift) ? selection : [], shift: modifiers.contains(.shift))
                    return ToolResult()
                }
```

In `.drag`:

```swift
            case .pressImage(let start, _, let base, _):
                guard start.distance(to: point) >= dragThreshold else { return ToolResult() }
                gesture = .marquee(start: start, base: base)
                let rect = CGRect.bounding([start, point])
                return ToolResult(selection: base.union(HitTesting.ids(intersecting: rect, in: annotations)), marquee: rect)
```

In `.up`:

```swift
            case .pressImage(_, let id, _, let shift):
                return ToolResult(selection: shift ? selection.union([id]) : [id])
```

Add `.pressImage` to the `case .idle, .create:` lists that return `ToolResult()` where the switch must be exhaustive.

- [ ] **Step 5: Run the tests**

Run: `python3 …/pt.py ImageSelectionTests` → `exit 0 | tests 6`; `python3 …/pt.py EditorUITests` → `exit 0` (tests that clicked a placed image and dragged at once now need a click first: update them only where the spec rule applies).

- [ ] **Step 6: Full suite and commit**

Run: `python3 …/pt.py` → `exit 0`.

```bash
git add PinxelKit/Sources/EditorUI PinxelKit/Tests/EditorUITests
git commit -m "feat(editor): click selects an image, dragging from an unselected one draws the marquee" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: UI test, manual checks, docs

**Files:**
- Create: `App/PinxelUITests/ObjectsUITests.swift`, `docs/manual-tests/objects.md`
- Modify: `docs/superpowers/specs/2026-10-19-pinxel-objects-design.md` (status), `docs/manual-tests/library.md` (L10 now "the canvas grows in any direction")

- [ ] **Step 1: Write the UI test**

Model it on `App/PinxelUITests/LibraryUITests.swift` (same launch arguments: `-ApplePersistenceIgnoreState YES` first, `-PinxelUITestLibraryName <uuid>`, then `-PinxelUITestOpenSample`; `PasteboardGuard`).

```swift
import XCTest

final class ObjectsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-PinxelUITestLibraryName", UUID().uuidString, "-PinxelUITestOpenSample"]
        app.launch()
        app.activate()
    }

    override func tearDown() { app.terminate() }

    /// Clic sulla cattura, poi trascinata a destra: la tela si allarga (il valore di accessibilità riporta le dimensioni).
    func testMovingTheCaptureGrowsTheCanvas() throws {
        let canvas = app.descendants(matching: .any)["pinxel.editor.canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        let before = canvas.value as? String ?? ""
        let center = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.click()
        center.click(forDuration: 0.2, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)))
        let grown = NSPredicate { _, _ in (canvas.value as? String ?? "") != before }
        expectation(for: grown, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        XCTAssertTrue((canvas.value as? String ?? "").contains("immagine:"))
    }
}
```

Run `xcodegen generate`, then: `caffeinate -dimsu xcodebuild -project Pinxel.xcodeproj -scheme Pinxel -destination 'platform=macOS' test -only-testing:PinxelUITests/ObjectsUITests 2>&1 | tail -20` → `** TEST SUCCEEDED **`. If it times out with "Timed out while enabling automation mode", ask the user to step away from the Mac and rerun; that is environmental.

Also rerun `-only-testing:PinxelUITests/LibraryUITests` → passes.

- [ ] **Step 2: Manual checklist `docs/manual-tests/objects.md`**

```markdown
# Prove a mano — immagini come oggetti

| # | Prova | Atteso |
|---|-------|--------|
| O1 | Cattura un'area, clic sulla cattura | È selezionata con le maniglie |
| O2 | Trascina la cattura selezionata a sinistra | La tela si allarga a sinistra al rilascio; frecce e testi restano fermi sullo schermo |
| O3 | Riportala dov'era | La tela si stringe |
| O4 | Trascina partendo dalla cattura non selezionata | Compare il riquadro di selezione; la cattura non si sposta |
| O5 | Disegna una freccia che esce dal bordo | La tela si allarga per contenerla |
| O6 | Sfocatura sopra un'immagine trascinata dal carosello | L'immagine sotto è sfocata |
| O7 | Sfocatura sopra un numero, poi Porta in primo piano il numero | Prima sfocato, poi nitido |
| O8 | Ritaglio con una freccia a cavallo del bordo | La freccia resta intera, la tela la include |
| O9 | Immagine ▸ Ridimensiona al 50% | Tutto si rimpicciolisce insieme |
| O10 | Taglia e ricuci attraverso cattura e immagine trascinata | La fascia sparisce da entrambe |
| O11 | ⌘V di uno screenshot su una cattura annotata | L'immagine in fondo cambia, le annotazioni restano |
| O12 | Elimina tutto | Tela vuota con il suggerimento; ⌘Z la riporta |
| O13 | Apri una cattura vecchia (salvata prima di questa versione) | Identica a prima; la cattura ora si seleziona |
| O14 | ⌘Z dopo O2 | Un solo passo riporta cattura e tela com'erano |
```

- [ ] **Step 3: Docs**

- Spec header: `**Stato:** approvata, implementata`; add a row "Immagini ruotate nel ritaglio | restano intere come le annotazioni (scelta del piano)" to §2.
- `docs/manual-tests/library.md` L10: "Trascina una miniatura oltre il bordo sinistro della tela: la tela si allarga da quella parte; un ⌘Z annulla".

- [ ] **Step 4: Commit**

```bash
git add App/PinxelUITests/ObjectsUITests.swift Pinxel.xcodeproj docs
git commit -m "test(objects): UI test, manual checklist and docs for captures as objects" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

## Self-review notes

- Spec §5.1 asked rotated images to be cropped in their own space with transparent corners; the plan keeps rotated images whole (like annotations) and records it in the spec (Task 8). Cost if wrong: one more function in `ContentEditing`.
- Spec §8 "Ritaglio che non contiene nessun oggetto: pulsante disattivato": the plan beeps and changes nothing (`applyContentEdit`). Cost if wrong: one menu validation.
- `nudge` coalescing is skipped whenever a fit happens (each arrow press that moves the canvas edge is its own undo step). Cost if wrong: more undo steps, never a wrong undo.
