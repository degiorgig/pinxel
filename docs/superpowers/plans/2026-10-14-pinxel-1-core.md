# Pinxel 1 — PinxelKit Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the headless core of Pinxel — document model with undoable commands, a single rendering path for canvas and export, and the `.pinxel` file format with export to PNG/JPEG/HEIC/PDF — as a Swift package fully covered by `swift test`.

**Architecture:** A local Swift package `PinxelKit` with three library targets: `DocumentModel` (pure Swift value types + `EditCommand`s), `Rendering` (Core Graphics / Core Text / Core Image drawing into any `CGContext`), `Persistence` (minimal ZIP reader/writer, `.pinxel` archive, image codecs, exporter). A non-test helper target `PinxelTestSupport` provides deterministic images and pixel comparison for the test targets. No UI and no app target in this plan; the app (plan 2) and the editor (plan 3) consume these modules.

**Tech Stack:** Swift 6.0 language mode (toolchain 6.4), SwiftPM, macOS 15+, Foundation, CoreGraphics, CoreText, CoreImage, ImageIO, UniformTypeIdentifiers, Compression, Swift Testing. No third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-10-14-pinxel-capture-editor-design.md` (sections 3, 5, 6.4, 8, 9, 10, 11 are implemented here).

## Global Constraints

- Platform floor: `macOS 15`; `swift-tools-version: 6.0` (Swift 6 strict concurrency, warnings are acceptable, errors are not).
- No external dependencies ("Nessuna dipendenza esterna nella v1").
- `DocumentModel` must not import AppKit, SwiftUI, CoreText, CoreImage or ImageIO (Foundation only; `CGPoint`/`CGRect`/`CGSize` come from Foundation).
- All document coordinates are pixels in image space after image operations, origin top-left, y down. Zoom/scroll are never persisted.
- The original background image is never modified; crop/resize/cut-out are `ImageOperation`s applied at render time.
- One drawing path: every export goes through `DocumentRenderer.render`.
- `.pinxel` = ZIP with `manifest.json` (`{"format":"pinxel","version":1,"appVersion":…}`), `document.json`, `background.png` (or `background.heic` if the PNG exceeds 20 MB), `assets/<uuid>.png`, `thumbnail.png` (long side 512 px). JSON deflated, images stored.
- Reading limits: total decompressed size ≤ 2 GB, ≤ 1000 entries, no path traversal in entry names.
- Bundle/UTI identifiers use the prefix `com.degiorgi.pinxel`.
- User-visible strings (command names) are in Italian.
- Snapshot references live in `PinxelKit/Tests/RenderingTests/__Snapshots__/` and are reviewed by a human before commit.
- This plan does not require Xcode: everything runs with `swift build` / `swift test` from `PinxelKit/`.

## Review Focus

1. **Very large captures** (e.g. 6000×4000 px, multi-monitor at 2x): rendering must succeed without crashing, and a background whose PNG exceeds 20 MB must be stored as HEIC → tests in Task 9 (`largeCanvasRenders`) and Task 11 (`largeBackgroundIsStoredAsHEIC`).
2. **Annotations that end up outside the image after a crop or cut-out**: they must be kept (not dropped), render without crashing, and come back exactly on undo → test in Task 5 (`cropKeepsAnnotationsOutsideAndRevertsExactly`).
3. **Degenerate input from a click without drag** (zero-length arrow, zero-size shape, single-point pen, magnifier whose source lies outside the image, huge/NaN coordinates): no crash, no NaN, nothing drawn where nothing makes sense → tests in Task 7 (`degenerateAnnotationsDoNotCrash`) and Task 9 (`magnifierWithSourceOutsideImageDrawsNothing`).
4. **Hostile or damaged `.pinxel` files** (path traversal, zip bomb with lying sizes, truncated file, bad checksum, too many entries, random bytes): a typed error, never a crash or unbounded allocation → tests in Task 10.
5. **Unusual text** (empty string, emoji with skin-tone modifiers, Arabic RTL, CJK): survives the JSON round-trip byte-exactly and renders without crashing → tests in Task 2 (`unicodeTextRoundTrips`) and Task 8 (`unicodeTextRenders`, `emptyTextDrawsNothing`).

---

## File Structure

```
PinxelKit/
├── Package.swift
├── Sources/
│   ├── DocumentModel/
│   │   ├── Geometry.swift            LineGeometry, PathGeometry, PixelSize, PixelRect, CGRect.bounding
│   │   ├── RGBA.swift                RGBA color
│   │   ├── Style.swift               Style, DashPattern, Shadow
│   │   ├── RichText.swift            RichText, TextRun, RichTextAlignment
│   │   ├── JSONValue.swift           JSONValue (unknown-kind preservation)
│   │   ├── AnnotationKinds.swift     payload structs per annotation kind
│   │   ├── Annotation.swift          Annotation, Annotation.Kind (+ Codable), bounds
│   │   ├── ImageOperation.swift      ImageOperation, CutOut, PointMapping
│   │   ├── PinxelDocument.swift      PinxelDocument, CanvasStyle, Border, CaptureMetadata, ImageAssetRef, ColorSpaceID
│   │   ├── AnnotationTransform.swift Annotation.transformed(by:)
│   │   ├── StepNumbering.swift       automatic step labels
│   │   └── EditCommand.swift         EditCommand + concrete commands
│   ├── Rendering/
│   │   ├── ImageDrawing.swift        bitmap contexts, flipped image drawing, RGBA.cgColor
│   │   ├── BackgroundProcessor.swift applies ImageOperations to the background
│   │   ├── EffectCache.swift         small LRU of computed effect images
│   │   ├── StrokeStyle.swift         StrokeStyle, ShadowStyle
│   │   ├── ShapeRenderer.swift       arrow, line, shape, pen, highlight
│   │   ├── TextRenderer.swift        text, callout, step
│   │   ├── EffectRenderer.swift      blur, pixelate, magnifier, placed image
│   │   ├── AnnotationRenderer.swift  per-annotation dispatcher (rotation, opacity, shadow)
│   │   └── DocumentRenderer.swift    AssetProvider, RenderOptions, DocumentRenderer
│   └── Persistence/
│       ├── CRC32.swift
│       ├── Deflate.swift             raw DEFLATE via Compression, bounded inflate
│       ├── ByteReader.swift          bounds-checked little-endian reads
│       ├── Zip.swift                 ZipError, ZipLimits, ZipWriter, ZipReader, ZipEntry
│       ├── ImageCodec.swift          PNG/JPEG/HEIC encode/decode, background encoding
│       ├── PinxelArchive.swift       .pinxel read/write
│       ├── Thumbnailer.swift
│       └── Exporter.swift            ExportFormat, ExportScale, Exporter
└── Tests/
    ├── PinxelTestSupport/            (regular target, no `import Testing`)
    │   ├── TestImages.swift
    │   ├── PixelBuffer.swift
    │   └── TestDocuments.swift
    ├── DocumentModelTests/
    ├── RenderingTests/
    │   ├── Snapshot.swift
    │   └── __Snapshots__/
    └── PersistenceTests/
```

All shell commands below assume the working directory is `/Users/giovanni/work/reatool/PinxelKit` unless they start with `cd`.

---

### Task 1: Package scaffold and basic value types

**Files:**
- Create: `PinxelKit/Package.swift`
- Create: `PinxelKit/Sources/DocumentModel/Geometry.swift`
- Create: `PinxelKit/Sources/DocumentModel/RGBA.swift`
- Create: `PinxelKit/Sources/DocumentModel/Style.swift`
- Create: `PinxelKit/Tests/PinxelTestSupport/TestImages.swift`
- Create: `PinxelKit/Tests/PinxelTestSupport/PixelBuffer.swift`
- Create: `PinxelKit/Tests/DocumentModelTests/TestSupport.swift`
- Create: `PinxelKit/Tests/DocumentModelTests/BasicTypesTests.swift`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `struct LineGeometry { var start: CGPoint; var end: CGPoint }`
  - `struct PathGeometry { var points: [CGPoint] }`
  - `struct PixelSize { var width: Int; var height: Int; var cgSize: CGSize }`
  - `struct PixelRect { var x, y, width, height: Int; var cgRect: CGRect; func clamped(to: PixelSize) -> PixelRect }`
  - `extension CGRect { static func bounding(_ points: [CGPoint]) -> CGRect }`
  - `struct RGBA { var red, green, blue, alpha: Double }` with statics `.black .white .clear .accentRed .highlightYellow`
  - `enum DashPattern: String { solid, dashed, dotted }`
  - `struct Shadow { var offset: CGSize; var blur: Double; var color: RGBA }`
  - `struct Style { var stroke: RGBA?; var fill: RGBA?; var lineWidth: Double; var dash: DashPattern; var opacity: Double; var shadow: Shadow? }` with `init(stroke: RGBA? = .accentRed, fill: RGBA? = nil, lineWidth: Double = 4, dash: DashPattern = .solid, opacity: Double = 1, shadow: Shadow? = nil)`
  - Test support: `TestImages.quadrants(width:height:)`, `TestImages.solid(width:height:red:green:blue:)`, `TestImages.noise(width:height:seed:)`, `TestImages.makeContext(width:height:)`, `PixelBuffer(_:)`, `PixelBuffer.pixel(x:y:) -> RGBA8`, `PixelBuffer.differingPixelFraction(from:channelTolerance:)`, `struct RGBA8 { r, g, b, a: UInt8 }`.

- [ ] **Step 1: Create the package manifest**

`PinxelKit/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PinxelKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "DocumentModel", targets: ["DocumentModel"]),
    ],
    targets: [
        .target(name: "DocumentModel"),
        .target(
            name: "PinxelTestSupport",
            dependencies: ["DocumentModel"],
            path: "Tests/PinxelTestSupport"
        ),
        .testTarget(
            name: "DocumentModelTests",
            dependencies: ["DocumentModel", "PinxelTestSupport"]
        ),
    ]
)
```

Append to `/Users/giovanni/work/reatool/.gitignore`:

```
*.actual.png
```

- [ ] **Step 2: Write the test support target**

`PinxelKit/Tests/PinxelTestSupport/TestImages.swift`:

```swift
import CoreGraphics
import Foundation

/// Immagini deterministiche per i test. Coordinate dei commenti: origine in alto a sinistra.
public enum TestImages {
    nonisolated(unsafe) public static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    public static func makeContext(width: Int, height: Int) -> CGContext {
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
    }

    /// Quattro quadranti: in alto rosso | verde, in basso blu | giallo.
    public static func quadrants(width: Int = 400, height: Int = 300) -> CGImage {
        let ctx = makeContext(width: width, height: height)
        let w = CGFloat(width), h = CGFloat(height)
        // Il contesto bitmap ha origine in basso a sinistra: la metà superiore è y >= h/2.
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: h / 2, width: w / 2, height: h / 2))
        ctx.setFillColor(CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: w / 2, y: h / 2, width: w / 2, height: h / 2))
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w / 2, height: h / 2))
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: w / 2, y: 0, width: w / 2, height: h / 2))
        return ctx.makeImage()!
    }

    public static func solid(width: Int, height: Int, red: CGFloat, green: CGFloat, blue: CGFloat) -> CGImage {
        let ctx = makeContext(width: width, height: height)
        ctx.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    /// Rumore RGB opaco, deterministico (LCG), praticamente incomprimibile.
    public static func noise(width: Int, height: Int, seed: UInt64 = 42) -> CGImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        var state = seed
        bytes.withUnsafeMutableBufferPointer { buffer in
            var i = 0
            while i < buffer.count {
                for c in 0..<3 {
                    state = state &* 6364136223846793005 &+ 1442695040888963407
                    buffer[i + c] = UInt8(truncatingIfNeeded: state >> 56)
                }
                i += 4
            }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: sRGB,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
    }
}
```

`PinxelKit/Tests/PinxelTestSupport/PixelBuffer.swift`:

```swift
import CoreGraphics

public struct RGBA8: Equatable, Sendable, CustomStringConvertible {
    public var r: UInt8, g: UInt8, b: UInt8, a: UInt8
    public init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }
    public var description: String { "RGBA8(\(r), \(g), \(b), \(a))" }
}

/// Pixel RGBA8 premoltiplicati in sRGB; la riga 0 è quella in alto.
public struct PixelBuffer: Equatable {
    public let width: Int
    public let height: Int
    public let bytes: [UInt8]

    public init(_ image: CGImage) {
        width = image.width
        height = image.height
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        data.withUnsafeMutableBytes { buffer in
            let ctx = CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: TestImages.sRGB,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        bytes = data
    }

    public func pixel(x: Int, y: Int) -> RGBA8 {
        let i = (y * width + x) * 4
        return RGBA8(r: bytes[i], g: bytes[i + 1], b: bytes[i + 2], a: bytes[i + 3])
    }

    /// Frazione (0...1) di pixel con almeno un canale che differisce più di `channelTolerance`.
    /// Restituisce 1 se le dimensioni sono diverse.
    public func differingPixelFraction(from other: PixelBuffer, channelTolerance: Int = 8) -> Double {
        guard width == other.width, height == other.height else { return 1 }
        var differing = 0
        var i = 0
        while i < bytes.count {
            for c in 0..<4 where abs(Int(bytes[i + c]) - Int(other.bytes[i + c])) > channelTolerance {
                differing += 1
                break
            }
            i += 4
        }
        return Double(differing) / Double(max(width * height, 1))
    }
}
```

- [ ] **Step 3: Write the failing tests**

`PinxelKit/Tests/DocumentModelTests/TestSupport.swift`:

```swift
import Foundation

func roundTrip<T: Codable>(_ value: T) throws -> T {
    let data = try JSONEncoder().encode(value)
    return try JSONDecoder().decode(T.self, from: data)
}
```

`PinxelKit/Tests/DocumentModelTests/BasicTypesTests.swift`:

```swift
import Foundation
import Testing
@testable import DocumentModel

struct BasicTypesTests {
    @Test func styleRoundTrips() throws {
        let style = Style(
            stroke: .accentRed, fill: .highlightYellow, lineWidth: 3, dash: .dotted, opacity: 0.5,
            shadow: Shadow(offset: CGSize(width: 2, height: 3), blur: 4, color: .black)
        )
        #expect(try roundTrip(style) == style)
    }

    @Test func styleWithoutColorsRoundTrips() throws {
        let style = Style(stroke: nil)
        #expect(try roundTrip(style) == style)
        #expect(style.fill == nil)
    }

    @Test func pixelRectClampsToImage() {
        let size = PixelSize(width: 100, height: 50)
        #expect(PixelRect(x: -10, y: 10, width: 50, height: 100).clamped(to: size)
            == PixelRect(x: 0, y: 10, width: 40, height: 40))
        #expect(PixelRect(x: 200, y: 0, width: 10, height: 10).clamped(to: size).width == 0)
    }

    @Test func boundingRectOfPoints() {
        let rect = CGRect.bounding([CGPoint(x: 5, y: 9), CGPoint(x: -1, y: 2), CGPoint(x: 3, y: 4)])
        #expect(rect == CGRect(x: -1, y: 2, width: 6, height: 7))
        #expect(CGRect.bounding([]).isNull)
    }

    @Test func lineAndPathRoundTrip() throws {
        let line = LineGeometry(start: CGPoint(x: 1, y: 2), end: CGPoint(x: 3.5, y: 4))
        let path = PathGeometry(points: [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)])
        #expect(try roundTrip(line) == line)
        #expect(try roundTrip(path) == path)
    }
}
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `cd /Users/giovanni/work/reatool/PinxelKit && swift test --filter BasicTypesTests`
Expected: build FAILS with errors such as `cannot find 'Style' in scope` (the `DocumentModel` target has no sources yet; SwiftPM may also report the target as empty).

- [ ] **Step 5: Implement the value types**

`PinxelKit/Sources/DocumentModel/Geometry.swift`:

```swift
import Foundation

public struct LineGeometry: Codable, Equatable, Sendable {
    public var start: CGPoint
    public var end: CGPoint

    public init(start: CGPoint, end: CGPoint) {
        self.start = start
        self.end = end
    }
}

public struct PathGeometry: Codable, Equatable, Sendable {
    public var points: [CGPoint]

    public init(points: [CGPoint]) {
        self.points = points
    }
}

public struct PixelSize: Codable, Equatable, Hashable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var cgSize: CGSize { CGSize(width: width, height: height) }
}

public struct PixelRect: Codable, Equatable, Hashable, Sendable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }

    /// Intersezione con l'immagine `0..<size`; larghezza/altezza 0 se fuori.
    public func clamped(to size: PixelSize) -> PixelRect {
        let minX = max(0, min(x, size.width))
        let minY = max(0, min(y, size.height))
        let maxX = max(minX, min(x + width, size.width))
        let maxY = max(minY, min(y + height, size.height))
        return PixelRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

extension CGRect {
    /// Il più piccolo rettangolo che contiene tutti i punti; `.null` se non ci sono punti.
    public static func bounding(_ points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .null }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for point in points.dropFirst() {
            minX = Swift.min(minX, point.x)
            minY = Swift.min(minY, point.y)
            maxX = Swift.max(maxX, point.x)
            maxY = Swift.max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
```

`PinxelKit/Sources/DocumentModel/RGBA.swift`:

```swift
import Foundation

/// Colore con componenti 0...1 nello spazio colore del documento.
public struct RGBA: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let black = RGBA(red: 0, green: 0, blue: 0)
    public static let white = RGBA(red: 1, green: 1, blue: 1)
    public static let clear = RGBA(red: 0, green: 0, blue: 0, alpha: 0)
    public static let accentRed = RGBA(red: 0.9, green: 0.16, blue: 0.2)
    public static let highlightYellow = RGBA(red: 1, green: 0.92, blue: 0.23)
}
```

`PinxelKit/Sources/DocumentModel/Style.swift`:

```swift
import Foundation

public enum DashPattern: String, Codable, Sendable {
    case solid, dashed, dotted
}

public struct Shadow: Codable, Equatable, Sendable {
    /// Spostamento in pixel del documento (y positivo = verso il basso).
    public var offset: CGSize
    public var blur: Double
    public var color: RGBA

    public init(offset: CGSize = CGSize(width: 0, height: 3), blur: Double = 6, color: RGBA = RGBA(red: 0, green: 0, blue: 0, alpha: 0.5)) {
        self.offset = offset
        self.blur = blur
        self.color = color
    }
}

public struct Style: Codable, Equatable, Sendable {
    public var stroke: RGBA?
    public var fill: RGBA?
    public var lineWidth: Double
    public var dash: DashPattern
    /// 0...1, applicata all'annotazione come gruppo.
    public var opacity: Double
    public var shadow: Shadow?

    public init(
        stroke: RGBA? = .accentRed,
        fill: RGBA? = nil,
        lineWidth: Double = 4,
        dash: DashPattern = .solid,
        opacity: Double = 1,
        shadow: Shadow? = nil
    ) {
        self.stroke = stroke
        self.fill = fill
        self.lineWidth = lineWidth
        self.dash = dash
        self.opacity = opacity
        self.shadow = shadow
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --filter BasicTypesTests`
Expected: PASS, 5 tests.

- [ ] **Step 7: Commit**

```bash
cd /Users/giovanni/work/reatool
git add .gitignore PinxelKit
git commit -m "feat(core): scaffold PinxelKit with geometry, color and style types"
```

---

### Task 2: Annotations, rich text and unknown-kind preservation

**Files:**
- Create: `PinxelKit/Sources/DocumentModel/RichText.swift`
- Create: `PinxelKit/Sources/DocumentModel/JSONValue.swift`
- Create: `PinxelKit/Sources/DocumentModel/AnnotationKinds.swift`
- Create: `PinxelKit/Sources/DocumentModel/Annotation.swift`
- Create: `PinxelKit/Sources/DocumentModel/PinxelDocument.swift` (only `ImageAssetRef` in this task; the rest in Task 3)
- Create: `PinxelKit/Tests/PinxelTestSupport/TestDocuments.swift`
- Test: `PinxelKit/Tests/DocumentModelTests/AnnotationTests.swift`

**Interfaces:**
- Consumes: Task 1 types.
- Produces:
  - `enum RichTextAlignment: String { left, center, right }`
  - `struct TextRun { var text: String; var bold, italic, underline: Bool; var color: RGBA? }` — `init(text:bold:italic:underline:color:)` all but `text` defaulted.
  - `struct RichText { var runs: [TextRun]; var fontFamily: String; var fontSize: Double; var color: RGBA; var alignment: RichTextAlignment; var plainText: String }` — `init(_ plain: String, fontFamily: String = "Helvetica", fontSize: Double = 24, color: RGBA = .black, alignment: RichTextAlignment = .left)` and `init(runs:fontFamily:fontSize:color:alignment:)`.
  - `enum JSONValue { null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue]) }`
  - `struct ImageAssetRef: Hashable { var name: String }`
  - Payloads: `HeadStyle { none, triangle, open, circle }`, `ArrowHeads(start:end:)`, `ShapeType { rectangle, roundedRectangle(cornerRadius: Double), ellipse }`, `CalloutTail(tip: CGPoint, baseWidth: Double = 24)`, `StepSequence { numbers, uppercaseLetters, lowercaseLetters }`, `StepLabel(sequence: = .numbers, override: String? = nil)`, `ArrowData(line:heads:)`, `LineData(line:)`, `ShapeData(rect:shape:)`, `TextData(rect:text:)`, `CalloutData(rect:text:tail:)`, `StepData(center:diameter:label:)`, `MagnifierData(source:target:shape:showsConnector:)`, `BlurData(rect:radius:)`, `PixelateData(rect:blockSize:)`, `HighlightData(path:)`, `PenData(path:smoothing:)`, `PlacedImageData(rect:asset:)`.
  - `struct Annotation: Identifiable, Codable, Equatable { let id: UUID; var kind: Kind; var style: Style; var rotation: Double; var isLocked: Bool; var bounds: CGRect }` — `init(id: UUID = UUID(), kind: Kind, style: Style = Style(), rotation: Double = 0, isLocked: Bool = false)`. `rotation` is radians, clockwise on screen, around `bounds` center.
  - `enum Annotation.Kind { arrow(ArrowData), line(LineData), shape(ShapeData), text(TextData), callout(CalloutData), step(StepData), magnifier(MagnifierData), blur(BlurData), pixelate(PixelateData), highlight(HighlightData), pen(PenData), image(PlacedImageData), unknown(type: String, raw: JSONValue); var typeName: String }`
  - JSON shape of an annotation: `{"id","type","data","rotation","style","isLocked"}`.
  - Test support: `TestDocuments.background`, `TestDocuments.placedImage`, `TestDocuments.id(_:)`, `TestDocuments.allKindsAnnotations()` (document builder added in Task 3).

- [ ] **Step 1: Write the failing tests**

`PinxelKit/Tests/DocumentModelTests/AnnotationTests.swift`:

```swift
import Foundation
import Testing
@testable import DocumentModel
import PinxelTestSupport

struct AnnotationTests {
    @Test func everyKindRoundTrips() throws {
        let annotations = TestDocuments.allKindsAnnotations()
        #expect(annotations.count == 14)
        for annotation in annotations {
            #expect(try roundTrip(annotation) == annotation, "kind \(annotation.kind.typeName)")
        }
    }

    @Test func jsonShapeUsesTypeAndData() throws {
        let annotation = TestDocuments.allKindsAnnotations()[0]
        let json = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(annotation))
        guard case .object(let object) = json else {
            Issue.record("annotation must encode as an object")
            return
        }
        #expect(object["type"] == .string("arrow"))
        #expect(object["data"] != nil)
        #expect(object["style"] != nil)
    }

    @Test func unknownKindIsPreserved() throws {
        let json = #"""
        {"id":"00000000-0000-0000-0000-000000000099","type":"sticker",
         "data":{"emoji":"🔥","size":3,"ratio":1.5,"flags":[true,null],"nested":{"a":"b"}},
         "rotation":0.5,"style":{"lineWidth":4,"dash":"solid","opacity":1},"isLocked":true}
        """#
        let decoded = try JSONDecoder().decode(Annotation.self, from: Data(json.utf8))
        guard case .unknown(let type, let raw) = decoded.kind else {
            Issue.record("expected unknown kind, got \(decoded.kind.typeName)")
            return
        }
        #expect(type == "sticker")
        #expect(decoded.rotation == 0.5)
        #expect(decoded.isLocked)

        let reencoded = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(decoded))
        let original = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        guard case .object(let a) = reencoded, case .object(let b) = original else {
            Issue.record("expected objects")
            return
        }
        #expect(a["data"] == b["data"])
        #expect(a["type"] == .string("sticker"))
        #expect(raw == b["data"])
    }

    @Test func jsonValueKeepsNumbersAndBoolsApart() throws {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"n":1,"b":true,"z":0,"f":false}"#.utf8))
        #expect(value == .object(["n": .number(1), "b": .bool(true), "z": .number(0), "f": .bool(false)]))
        #expect(try roundTrip(value) == value)
    }

    @Test func unicodeTextRoundTrips() throws {
        for sample in ["", "👋🏽 Ciao — مرحبا — 日本語", "a\nb\tc \"quoted\" \\ /"] {
            let text = RichText(runs: [TextRun(text: sample, bold: true), TextRun(text: sample, italic: true, color: .accentRed)])
            let annotation = Annotation(kind: .text(TextData(rect: CGRect(x: 0, y: 0, width: 10, height: 10), text: text)))
            let decoded = try roundTrip(annotation)
            #expect(decoded == annotation)
            if case .text(let data) = decoded.kind {
                #expect(data.text.plainText == sample + sample)
            }
        }
    }

    @Test func boundsPerKind() {
        let byID = Dictionary(uniqueKeysWithValues: TestDocuments.allKindsAnnotations().map { ($0.id, $0) })
        #expect(byID[TestDocuments.id(1)]?.bounds == CGRect(x: 20, y: 20, width: 120, height: 60))
        #expect(byID[TestDocuments.id(3)]?.bounds == CGRect(x: 180, y: 20, width: 100, height: 60))
        #expect(byID[TestDocuments.id(7)]?.bounds == CGRect(x: 22, y: 212, width: 36, height: 36))
        #expect(byID[TestDocuments.id(13)]?.bounds == CGRect(x: 190, y: 90, width: 190, height: 70))
        // Il callout include la punta della coda.
        #expect(byID[TestDocuments.id(6)]?.bounds == CGRect(x: 180, y: 110, width: 180, height: 110))
    }

    @Test func boundsNormalizeNegativeRects() {
        let annotation = Annotation(kind: .shape(ShapeData(rect: CGRect(x: 50, y: 50, width: -20, height: -10), shape: .rectangle)))
        #expect(annotation.bounds == CGRect(x: 30, y: 40, width: 20, height: 10))
    }
}
```

`PinxelKit/Tests/PinxelTestSupport/TestDocuments.swift`:

```swift
import Foundation
import DocumentModel

public enum TestDocuments {
    public static let background = ImageAssetRef(name: "background.png")
    public static let placedImage = ImageAssetRef(name: "assets/00000000-0000-0000-0000-000000000001.png")

    public static func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
    }

    /// Una annotazione per ogni tipo, disposte su un'immagine 400×300.
    public static func allKindsAnnotations() -> [Annotation] {
        [
            Annotation(id: id(1), kind: .arrow(ArrowData(
                line: LineGeometry(start: CGPoint(x: 20, y: 20), end: CGPoint(x: 140, y: 80)),
                heads: ArrowHeads(start: .none, end: .triangle)))),
            Annotation(id: id(2), kind: .line(LineData(
                line: LineGeometry(start: CGPoint(x: 20, y: 120), end: CGPoint(x: 140, y: 120)))),
                style: Style(stroke: .black, lineWidth: 2, dash: .dashed)),
            Annotation(id: id(3), kind: .shape(ShapeData(
                rect: CGRect(x: 180, y: 20, width: 100, height: 60), shape: .roundedRectangle(cornerRadius: 10)))),
            Annotation(id: id(4), kind: .shape(ShapeData(
                rect: CGRect(x: 300, y: 20, width: 80, height: 60), shape: .ellipse)),
                style: Style(stroke: .black, fill: .highlightYellow, lineWidth: 3)),
            Annotation(id: id(5), kind: .text(TextData(
                rect: CGRect(x: 20, y: 150, width: 160, height: 40), text: RichText("Ciao Pinxel"))),
                style: Style(stroke: nil)),
            Annotation(id: id(6), kind: .callout(CalloutData(
                rect: CGRect(x: 200, y: 110, width: 160, height: 60),
                text: RichText("Clicca qui", fontSize: 18),
                tail: CalloutTail(tip: CGPoint(x: 180, y: 220)))),
                style: Style(stroke: .accentRed, fill: .white, lineWidth: 2)),
            Annotation(id: id(7), kind: .step(StepData(center: CGPoint(x: 40, y: 230), diameter: 36, label: StepLabel())),
                style: Style(stroke: nil, fill: .accentRed)),
            Annotation(id: id(8), kind: .step(StepData(center: CGPoint(x: 90, y: 230), diameter: 36, label: StepLabel())),
                style: Style(stroke: nil, fill: .accentRed)),
            Annotation(id: id(9), kind: .highlight(HighlightData(
                path: PathGeometry(points: [CGPoint(x: 120, y: 270), CGPoint(x: 260, y: 270)]))),
                style: Style(stroke: .highlightYellow, lineWidth: 16, opacity: 0.5)),
            Annotation(id: id(10), kind: .pen(PenData(
                path: PathGeometry(points: [CGPoint(x: 280, y: 200), CGPoint(x: 300, y: 240), CGPoint(x: 330, y: 210), CGPoint(x: 360, y: 250)]),
                smoothing: 1))),
            Annotation(id: id(11), kind: .blur(BlurData(rect: CGRect(x: 150, y: 190, width: 50, height: 40), radius: 8))),
            Annotation(id: id(12), kind: .pixelate(PixelateData(rect: CGRect(x: 210, y: 190, width: 50, height: 40), blockSize: 10))),
            Annotation(id: id(13), kind: .magnifier(MagnifierData(
                source: CGRect(x: 190, y: 140, width: 20, height: 20),
                target: CGRect(x: 320, y: 90, width: 60, height: 60),
                shape: .ellipse, showsConnector: true)),
                style: Style(stroke: .black, lineWidth: 2)),
            Annotation(id: id(14), kind: .image(PlacedImageData(
                rect: CGRect(x: 330, y: 250, width: 40, height: 30), asset: placedImage))),
        ]
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter AnnotationTests`
Expected: build FAILS with `cannot find 'Annotation' in scope` / `cannot find 'RichText' in scope`.

- [ ] **Step 3: Implement rich text, JSONValue and asset reference**

`PinxelKit/Sources/DocumentModel/RichText.swift`:

```swift
import Foundation

public enum RichTextAlignment: String, Codable, Sendable {
    case left, center, right
}

public struct TextRun: Codable, Equatable, Sendable {
    public var text: String
    public var bold: Bool
    public var italic: Bool
    public var underline: Bool
    /// `nil` = usa `RichText.color`.
    public var color: RGBA?

    public init(text: String, bold: Bool = false, italic: Bool = false, underline: Bool = false, color: RGBA? = nil) {
        self.text = text
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.color = color
    }
}

public struct RichText: Codable, Equatable, Sendable {
    public var runs: [TextRun]
    public var fontFamily: String
    public var fontSize: Double
    public var color: RGBA
    public var alignment: RichTextAlignment

    public init(
        runs: [TextRun],
        fontFamily: String = "Helvetica",
        fontSize: Double = 24,
        color: RGBA = .black,
        alignment: RichTextAlignment = .left
    ) {
        self.runs = runs
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.color = color
        self.alignment = alignment
    }

    public init(
        _ plain: String,
        fontFamily: String = "Helvetica",
        fontSize: Double = 24,
        color: RGBA = .black,
        alignment: RichTextAlignment = .left
    ) {
        self.init(runs: [TextRun(text: plain)], fontFamily: fontFamily, fontSize: fontSize, color: color, alignment: alignment)
    }

    public var plainText: String { runs.map(\.text).joined() }
}
```

`PinxelKit/Sources/DocumentModel/JSONValue.swift`:

```swift
import Foundation

/// JSON arbitrario, usato per conservare intatti i tipi di annotazione sconosciuti.
public enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}
```

`PinxelKit/Sources/DocumentModel/PinxelDocument.swift` (this task only):

```swift
import Foundation

/// Riferimento a un'immagine dentro l'archivio `.pinxel` (es. "background.png", "assets/<uuid>.png").
public struct ImageAssetRef: Codable, Hashable, Sendable {
    public var name: String

    public init(name: String) {
        self.name = name
    }
}
```

- [ ] **Step 4: Implement payloads and Annotation**

`PinxelKit/Sources/DocumentModel/AnnotationKinds.swift`:

```swift
import Foundation

public enum HeadStyle: String, Codable, Sendable {
    case none, triangle, open, circle
}

public struct ArrowHeads: Codable, Equatable, Sendable {
    public var start: HeadStyle
    public var end: HeadStyle

    public init(start: HeadStyle = .none, end: HeadStyle = .triangle) {
        self.start = start
        self.end = end
    }
}

public enum ShapeType: Codable, Equatable, Sendable {
    case rectangle
    case roundedRectangle(cornerRadius: Double)
    case ellipse
}

public struct CalloutTail: Codable, Equatable, Sendable {
    /// Punta della coda, in coordinate assolute del documento.
    public var tip: CGPoint
    public var baseWidth: Double

    public init(tip: CGPoint, baseWidth: Double = 24) {
        self.tip = tip
        self.baseWidth = baseWidth
    }
}

public enum StepSequence: String, Codable, Sendable {
    case numbers, uppercaseLetters, lowercaseLetters
}

public struct StepLabel: Codable, Equatable, Sendable {
    public var sequence: StepSequence
    /// Se impostato, sostituisce il valore calcolato automaticamente.
    public var override: String?

    public init(sequence: StepSequence = .numbers, override: String? = nil) {
        self.sequence = sequence
        self.override = override
    }
}

public struct ArrowData: Codable, Equatable, Sendable {
    public var line: LineGeometry
    public var heads: ArrowHeads
    public init(line: LineGeometry, heads: ArrowHeads = ArrowHeads()) { self.line = line; self.heads = heads }
}

public struct LineData: Codable, Equatable, Sendable {
    public var line: LineGeometry
    public init(line: LineGeometry) { self.line = line }
}

public struct ShapeData: Codable, Equatable, Sendable {
    public var rect: CGRect
    public var shape: ShapeType
    public init(rect: CGRect, shape: ShapeType) { self.rect = rect; self.shape = shape }
}

public struct TextData: Codable, Equatable, Sendable {
    public var rect: CGRect
    public var text: RichText
    public init(rect: CGRect, text: RichText) { self.rect = rect; self.text = text }
}

public struct CalloutData: Codable, Equatable, Sendable {
    public var rect: CGRect
    public var text: RichText
    public var tail: CalloutTail
    public init(rect: CGRect, text: RichText, tail: CalloutTail) { self.rect = rect; self.text = text; self.tail = tail }
}

public struct StepData: Codable, Equatable, Sendable {
    public var center: CGPoint
    public var diameter: Double
    public var label: StepLabel
    public init(center: CGPoint, diameter: Double, label: StepLabel = StepLabel()) {
        self.center = center; self.diameter = diameter; self.label = label
    }
}

public struct MagnifierData: Codable, Equatable, Sendable {
    public var source: CGRect
    public var target: CGRect
    public var shape: ShapeType
    public var showsConnector: Bool
    public init(source: CGRect, target: CGRect, shape: ShapeType = .ellipse, showsConnector: Bool = true) {
        self.source = source; self.target = target; self.shape = shape; self.showsConnector = showsConnector
    }
}

public struct BlurData: Codable, Equatable, Sendable {
    public var rect: CGRect
    public var radius: Double
    public init(rect: CGRect, radius: Double = 12) { self.rect = rect; self.radius = radius }
}

public struct PixelateData: Codable, Equatable, Sendable {
    public var rect: CGRect
    public var blockSize: Double
    public init(rect: CGRect, blockSize: Double = 12) { self.rect = rect; self.blockSize = blockSize }
}

public struct HighlightData: Codable, Equatable, Sendable {
    public var path: PathGeometry
    public init(path: PathGeometry) { self.path = path }
}

public struct PenData: Codable, Equatable, Sendable {
    public var path: PathGeometry
    public var smoothing: Double
    public init(path: PathGeometry, smoothing: Double = 1) { self.path = path; self.smoothing = smoothing }
}

public struct PlacedImageData: Codable, Equatable, Sendable {
    public var rect: CGRect
    public var asset: ImageAssetRef
    public init(rect: CGRect, asset: ImageAssetRef) { self.rect = rect; self.asset = asset }
}
```

`PinxelKit/Sources/DocumentModel/Annotation.swift`:

```swift
import Foundation

public struct Annotation: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var kind: Kind
    public var style: Style
    /// Radianti, in senso orario sullo schermo, attorno al centro di `bounds`.
    public var rotation: Double
    public var isLocked: Bool

    public init(id: UUID = UUID(), kind: Kind, style: Style = Style(), rotation: Double = 0, isLocked: Bool = false) {
        self.id = id
        self.kind = kind
        self.style = style
        self.rotation = rotation
        self.isLocked = isLocked
    }
}

extension Annotation {
    public enum Kind: Equatable, Sendable {
        case arrow(ArrowData)
        case line(LineData)
        case shape(ShapeData)
        case text(TextData)
        case callout(CalloutData)
        case step(StepData)
        case magnifier(MagnifierData)
        case blur(BlurData)
        case pixelate(PixelateData)
        case highlight(HighlightData)
        case pen(PenData)
        case image(PlacedImageData)
        /// Tipo non riconosciuto (file di una versione futura): conservato e risalvato identico.
        case unknown(type: String, raw: JSONValue)

        public var typeName: String {
            switch self {
            case .arrow: "arrow"
            case .line: "line"
            case .shape: "shape"
            case .text: "text"
            case .callout: "callout"
            case .step: "step"
            case .magnifier: "magnifier"
            case .blur: "blur"
            case .pixelate: "pixelate"
            case .highlight: "highlight"
            case .pen: "pen"
            case .image: "image"
            case .unknown(let type, _): type
            }
        }
    }

    /// Rettangolo normalizzato che contiene la geometria (senza rotazione né spessore del tratto).
    public var bounds: CGRect {
        switch kind {
        case .arrow(let data): .bounding([data.line.start, data.line.end])
        case .line(let data): .bounding([data.line.start, data.line.end])
        case .shape(let data): data.rect.standardized
        case .text(let data): data.rect.standardized
        case .callout(let data): data.rect.standardized.union(CGRect(origin: data.tail.tip, size: .zero))
        case .step(let data):
            CGRect(x: data.center.x - data.diameter / 2, y: data.center.y - data.diameter / 2,
                   width: data.diameter, height: data.diameter)
        case .magnifier(let data): data.source.standardized.union(data.target.standardized)
        case .blur(let data): data.rect.standardized
        case .pixelate(let data): data.rect.standardized
        case .highlight(let data): .bounding(data.path.points)
        case .pen(let data): .bounding(data.path.points)
        case .image(let data): data.rect.standardized
        case .unknown: .null
        }
    }
}

extension Annotation: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, type, data, rotation, style, isLocked
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        style = try c.decode(Style.self, forKey: .style)
        rotation = try c.decodeIfPresent(Double.self, forKey: .rotation) ?? 0
        isLocked = try c.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "arrow": kind = .arrow(try c.decode(ArrowData.self, forKey: .data))
        case "line": kind = .line(try c.decode(LineData.self, forKey: .data))
        case "shape": kind = .shape(try c.decode(ShapeData.self, forKey: .data))
        case "text": kind = .text(try c.decode(TextData.self, forKey: .data))
        case "callout": kind = .callout(try c.decode(CalloutData.self, forKey: .data))
        case "step": kind = .step(try c.decode(StepData.self, forKey: .data))
        case "magnifier": kind = .magnifier(try c.decode(MagnifierData.self, forKey: .data))
        case "blur": kind = .blur(try c.decode(BlurData.self, forKey: .data))
        case "pixelate": kind = .pixelate(try c.decode(PixelateData.self, forKey: .data))
        case "highlight": kind = .highlight(try c.decode(HighlightData.self, forKey: .data))
        case "pen": kind = .pen(try c.decode(PenData.self, forKey: .data))
        case "image": kind = .image(try c.decode(PlacedImageData.self, forKey: .data))
        default: kind = .unknown(type: type, raw: try c.decode(JSONValue.self, forKey: .data))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind.typeName, forKey: .type)
        try c.encode(style, forKey: .style)
        try c.encode(rotation, forKey: .rotation)
        try c.encode(isLocked, forKey: .isLocked)
        switch kind {
        case .arrow(let data): try c.encode(data, forKey: .data)
        case .line(let data): try c.encode(data, forKey: .data)
        case .shape(let data): try c.encode(data, forKey: .data)
        case .text(let data): try c.encode(data, forKey: .data)
        case .callout(let data): try c.encode(data, forKey: .data)
        case .step(let data): try c.encode(data, forKey: .data)
        case .magnifier(let data): try c.encode(data, forKey: .data)
        case .blur(let data): try c.encode(data, forKey: .data)
        case .pixelate(let data): try c.encode(data, forKey: .data)
        case .highlight(let data): try c.encode(data, forKey: .data)
        case .pen(let data): try c.encode(data, forKey: .data)
        case .image(let data): try c.encode(data, forKey: .data)
        case .unknown(_, let raw): try c.encode(raw, forKey: .data)
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter AnnotationTests`
Expected: PASS, 7 tests. If `jsonValueKeepsNumbersAndBoolsApart` fails because the decoder turns `1` into `true`, move the `Double` branch above the `Bool` branch in `JSONValue.init(from:)` and re-run; the test must pass with one of the two orders.

- [ ] **Step 6: Commit**

```bash
cd /Users/giovanni/work/reatool
git add PinxelKit
git commit -m "feat(core): add annotation kinds, rich text and unknown-kind preservation"
```

---

### Task 3: Document, image operations and coordinate mapping

**Files:**
- Modify: `PinxelKit/Sources/DocumentModel/PinxelDocument.swift`
- Create: `PinxelKit/Sources/DocumentModel/ImageOperation.swift`
- Create: `PinxelKit/Sources/DocumentModel/AnnotationTransform.swift`
- Modify: `PinxelKit/Tests/PinxelTestSupport/TestDocuments.swift` (add `document(...)`)
- Test: `PinxelKit/Tests/DocumentModelTests/DocumentTests.swift`

**Interfaces:**
- Consumes: Task 1–2 types.
- Produces:
  - `enum ColorSpaceID: String { sRGB, displayP3 }`
  - `struct Border { var color: RGBA; var width: Double }`
  - `struct CanvasStyle { var padding: Double = 0; var backgroundColor: RGBA? = nil; var border: Border? = nil; var shadow: Shadow? = nil }`
  - `struct CaptureMetadata { var captureDate: Date; var appName, bundleIdentifier, windowTitle, url: String? }`
  - `struct PinxelDocument { background, canvasSize, scale, colorSpace, imageOperations, canvasStyle, annotations, metadata; var imageSize: PixelSize }` with `init(background:canvasSize:scale: = 1, colorSpace: = .sRGB, imageOperations: = [], canvasStyle: = CanvasStyle(), annotations: = [], metadata:)`.
  - `enum Axis: String { horizontal, vertical }` (`horizontal` removes a band of rows), `enum CutEdge: String { straight, zigzag }`
  - `struct CutOut { axis, start: Int, length: Int, edge; func clampedStart(in: PixelSize) -> Int; func clampedLength(in: PixelSize) -> Int }`
  - `enum ImageOperation { crop(PixelRect), resize(PixelSize), cutOut(CutOut); func resultSize(from: PixelSize) -> PixelSize; func mapping(from: PixelSize) -> PointMapping; var name: String }`
  - `struct PointMapping { let map: @Sendable (CGPoint) -> CGPoint; let lengthScale: Double }`
  - `extension Annotation { func transformed(by: PointMapping) -> Annotation }`
  - Test support: `TestDocuments.document(annotations:size:scale:) -> PinxelDocument`.

- [ ] **Step 1: Write the failing tests**

`PinxelKit/Tests/DocumentModelTests/DocumentTests.swift`:

```swift
import Foundation
import Testing
@testable import DocumentModel
import PinxelTestSupport

struct DocumentTests {
    let size = PixelSize(width: 400, height: 300)

    @Test func documentRoundTrips() throws {
        var document = TestDocuments.document()
        document.imageOperations = [.crop(PixelRect(x: 10, y: 10, width: 300, height: 200)), .resize(PixelSize(width: 150, height: 100))]
        document.canvasStyle = CanvasStyle(padding: 12, backgroundColor: .white, border: Border(color: .black, width: 2), shadow: Shadow())
        #expect(try roundTrip(document) == document)
    }

    @Test func imageSizeFollowsOperations() {
        var document = TestDocuments.document(size: size)
        #expect(document.imageSize == size)
        document.imageOperations = [
            .crop(PixelRect(x: 50, y: 50, width: 300, height: 200)),
            .cutOut(CutOut(axis: .horizontal, start: 50, length: 40, edge: .straight)),
            .resize(PixelSize(width: 150, height: 80)),
        ]
        #expect(document.imageSize == PixelSize(width: 150, height: 80))
    }

    @Test func cropOutsideImageIsClamped() {
        let op = ImageOperation.crop(PixelRect(x: 350, y: -20, width: 200, height: 100))
        #expect(op.resultSize(from: size) == PixelSize(width: 50, height: 80))
    }

    @Test func cropMappingTranslates() {
        let mapping = ImageOperation.crop(PixelRect(x: 30, y: 40, width: 100, height: 100)).mapping(from: size)
        #expect(mapping.map(CGPoint(x: 30, y: 40)) == CGPoint(x: 0, y: 0))
        #expect(mapping.map(CGPoint(x: 10, y: 10)) == CGPoint(x: -20, y: -30))
        #expect(mapping.lengthScale == 1)
    }

    @Test func resizeMappingScales() {
        let mapping = ImageOperation.resize(PixelSize(width: 200, height: 75)).mapping(from: size)
        #expect(mapping.map(CGPoint(x: 100, y: 100)) == CGPoint(x: 50, y: 25))
        #expect(abs(mapping.lengthScale - (0.5 * 0.25).squareRoot()) < 1e-9)
    }

    @Test func cutOutMappingCollapsesBand() {
        let cut = CutOut(axis: .horizontal, start: 100, length: 50, edge: .zigzag)
        let mapping = ImageOperation.cutOut(cut).mapping(from: size)
        #expect(mapping.map(CGPoint(x: 7, y: 80)) == CGPoint(x: 7, y: 80))
        #expect(mapping.map(CGPoint(x: 7, y: 120)) == CGPoint(x: 7, y: 100))
        #expect(mapping.map(CGPoint(x: 7, y: 200)) == CGPoint(x: 7, y: 150))
        #expect(ImageOperation.cutOut(cut).resultSize(from: size) == PixelSize(width: 400, height: 250))

        let vertical = ImageOperation.cutOut(CutOut(axis: .vertical, start: 380, length: 100, edge: .straight))
        #expect(vertical.resultSize(from: size) == PixelSize(width: 380, height: 300))
        #expect(vertical.mapping(from: size).map(CGPoint(x: 390, y: 5)) == CGPoint(x: 380, y: 5))
    }

    @Test func transformedMovesEveryGeometry() {
        let mapping = ImageOperation.crop(PixelRect(x: 10, y: 20, width: 300, height: 200)).mapping(from: size)
        for annotation in TestDocuments.allKindsAnnotations() {
            let moved = annotation.transformed(by: mapping)
            #expect(moved.id == annotation.id)
            #expect(moved.style == annotation.style)
            let expected = annotation.bounds.offsetBy(dx: -10, dy: -20)
            #expect(abs(moved.bounds.minX - expected.minX) < 1e-9, "\(annotation.kind.typeName)")
            #expect(abs(moved.bounds.minY - expected.minY) < 1e-9, "\(annotation.kind.typeName)")
            #expect(abs(moved.bounds.width - expected.width) < 1e-9, "\(annotation.kind.typeName)")
        }
    }

    @Test func resizeScalesStepDiameter() {
        let step = Annotation(kind: .step(StepData(center: CGPoint(x: 100, y: 100), diameter: 40)))
        let moved = step.transformed(by: ImageOperation.resize(PixelSize(width: 200, height: 150)).mapping(from: size))
        guard case .step(let data) = moved.kind else {
            Issue.record("expected step")
            return
        }
        #expect(data.center == CGPoint(x: 50, y: 50))
        #expect(abs(data.diameter - 20) < 1e-9)
    }
}
```

Add to `PinxelKit/Tests/PinxelTestSupport/TestDocuments.swift`, inside `enum TestDocuments`:

```swift
    public static func document(
        annotations: [Annotation] = allKindsAnnotations(),
        size: PixelSize = PixelSize(width: 400, height: 300),
        scale: Double = 2
    ) -> PinxelDocument {
        PinxelDocument(
            background: background,
            canvasSize: size,
            scale: scale,
            annotations: annotations,
            metadata: CaptureMetadata(
                captureDate: Date(timeIntervalSinceReferenceDate: 800_000_000),
                appName: "Finder",
                bundleIdentifier: "com.apple.finder",
                windowTitle: "Documenti"
            )
        )
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter DocumentTests`
Expected: build FAILS with `cannot find 'PinxelDocument' in scope` / `cannot find 'ImageOperation' in scope`.

- [ ] **Step 3: Implement the document**

Replace the whole content of `PinxelKit/Sources/DocumentModel/PinxelDocument.swift`:

```swift
import Foundation

/// Riferimento a un'immagine dentro l'archivio `.pinxel` (es. "background.png", "assets/<uuid>.png").
public struct ImageAssetRef: Codable, Hashable, Sendable {
    public var name: String

    public init(name: String) {
        self.name = name
    }
}

public enum ColorSpaceID: String, Codable, Sendable {
    case sRGB, displayP3
}

public struct Border: Codable, Equatable, Sendable {
    public var color: RGBA
    public var width: Double

    public init(color: RGBA, width: Double) {
        self.color = color
        self.width = width
    }
}

public struct CanvasStyle: Codable, Equatable, Sendable {
    /// Margine attorno all'immagine, in pixel del documento.
    public var padding: Double
    public var backgroundColor: RGBA?
    public var border: Border?
    public var shadow: Shadow?

    public init(padding: Double = 0, backgroundColor: RGBA? = nil, border: Border? = nil, shadow: Shadow? = nil) {
        self.padding = padding
        self.backgroundColor = backgroundColor
        self.border = border
        self.shadow = shadow
    }
}

public struct CaptureMetadata: Codable, Equatable, Sendable {
    public var captureDate: Date
    public var appName: String?
    public var bundleIdentifier: String?
    public var windowTitle: String?
    public var url: String?

    public init(captureDate: Date = Date(), appName: String? = nil, bundleIdentifier: String? = nil, windowTitle: String? = nil, url: String? = nil) {
        self.captureDate = captureDate
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
        self.url = url
    }
}

public struct PinxelDocument: Codable, Equatable, Sendable {
    /// Immagine originale, mai modificata.
    public var background: ImageAssetRef
    /// Dimensioni in pixel dell'immagine originale.
    public var canvasSize: PixelSize
    /// Pixel per punto (2 su Retina).
    public var scale: Double
    public var colorSpace: ColorSpaceID
    public var imageOperations: [ImageOperation]
    public var canvasStyle: CanvasStyle
    /// Ordine = z-order (indice 0 = in fondo).
    public var annotations: [Annotation]
    public var metadata: CaptureMetadata

    public init(
        background: ImageAssetRef,
        canvasSize: PixelSize,
        scale: Double = 1,
        colorSpace: ColorSpaceID = .sRGB,
        imageOperations: [ImageOperation] = [],
        canvasStyle: CanvasStyle = CanvasStyle(),
        annotations: [Annotation] = [],
        metadata: CaptureMetadata
    ) {
        self.background = background
        self.canvasSize = canvasSize
        self.scale = scale
        self.colorSpace = colorSpace
        self.imageOperations = imageOperations
        self.canvasStyle = canvasStyle
        self.annotations = annotations
        self.metadata = metadata
    }

    /// Dimensioni dell'immagine dopo tutte le operazioni.
    public var imageSize: PixelSize {
        imageOperations.reduce(canvasSize) { size, operation in operation.resultSize(from: size) }
    }
}
```

- [ ] **Step 4: Implement image operations and transforms**

`PinxelKit/Sources/DocumentModel/ImageOperation.swift`:

```swift
import Foundation

public enum Axis: String, Codable, Sendable {
    /// Rimuove una fascia orizzontale (righe), l'altezza diminuisce.
    case horizontal
    /// Rimuove una fascia verticale (colonne), la larghezza diminuisce.
    case vertical
}

public enum CutEdge: String, Codable, Sendable {
    case straight, zigzag
}

public struct CutOut: Codable, Equatable, Sendable {
    public var axis: Axis
    public var start: Int
    public var length: Int
    public var edge: CutEdge

    public init(axis: Axis, start: Int, length: Int, edge: CutEdge = .straight) {
        self.axis = axis
        self.start = start
        self.length = length
        self.edge = edge
    }

    private func extent(of size: PixelSize) -> Int {
        axis == .horizontal ? size.height : size.width
    }

    public func clampedStart(in size: PixelSize) -> Int {
        max(0, min(start, extent(of: size)))
    }

    public func clampedLength(in size: PixelSize) -> Int {
        max(0, min(length, extent(of: size) - clampedStart(in: size)))
    }
}

/// Trasformazione dei punti del documento prodotta da un'operazione immagine.
public struct PointMapping: Sendable {
    public let map: @Sendable (CGPoint) -> CGPoint
    /// Fattore per le lunghezze isotrope (es. diametro degli step).
    public let lengthScale: Double

    public init(lengthScale: Double = 1, map: @escaping @Sendable (CGPoint) -> CGPoint) {
        self.lengthScale = lengthScale
        self.map = map
    }
}

public enum ImageOperation: Codable, Equatable, Sendable {
    case crop(PixelRect)
    case resize(PixelSize)
    case cutOut(CutOut)

    public var name: String {
        switch self {
        case .crop: "Ritaglia"
        case .resize: "Ridimensiona"
        case .cutOut: "Taglia e ricuci"
        }
    }

    public func resultSize(from size: PixelSize) -> PixelSize {
        switch self {
        case .crop(let rect):
            let clamped = rect.clamped(to: size)
            return PixelSize(width: clamped.width, height: clamped.height)
        case .resize(let target):
            return target
        case .cutOut(let cut):
            let length = cut.clampedLength(in: size)
            switch cut.axis {
            case .horizontal: return PixelSize(width: size.width, height: size.height - length)
            case .vertical: return PixelSize(width: size.width - length, height: size.height)
            }
        }
    }

    public func mapping(from size: PixelSize) -> PointMapping {
        switch self {
        case .crop(let rect):
            let clamped = rect.clamped(to: size)
            let dx = Double(clamped.x), dy = Double(clamped.y)
            return PointMapping { CGPoint(x: $0.x - dx, y: $0.y - dy) }
        case .resize(let target):
            let sx = Double(target.width) / Double(max(size.width, 1))
            let sy = Double(target.height) / Double(max(size.height, 1))
            return PointMapping(lengthScale: (sx * sy).squareRoot()) { CGPoint(x: $0.x * sx, y: $0.y * sy) }
        case .cutOut(let cut):
            let start = Double(cut.clampedStart(in: size))
            let length = Double(cut.clampedLength(in: size))
            switch cut.axis {
            case .horizontal:
                return PointMapping { CGPoint(x: $0.x, y: collapse($0.y, start: start, length: length)) }
            case .vertical:
                return PointMapping { CGPoint(x: collapse($0.x, start: start, length: length), y: $0.y) }
            }
        }
    }
}

/// Coordinate oltre la fascia rimossa scorrono indietro; quelle dentro la fascia finiscono sul bordo.
private func collapse(_ value: Double, start: Double, length: Double) -> Double {
    if value >= start + length { return value - length }
    if value > start { return start }
    return value
}
```

`PinxelKit/Sources/DocumentModel/AnnotationTransform.swift`:

```swift
import Foundation

extension Annotation {
    /// Copia dell'annotazione con tutta la geometria trasformata da `mapping`.
    /// Stile e rotazione restano invariati.
    public func transformed(by mapping: PointMapping) -> Annotation {
        func rect(_ r: CGRect) -> CGRect {
            let r = r.standardized
            return .bounding([mapping.map(CGPoint(x: r.minX, y: r.minY)), mapping.map(CGPoint(x: r.maxX, y: r.maxY))])
        }
        func line(_ l: LineGeometry) -> LineGeometry {
            LineGeometry(start: mapping.map(l.start), end: mapping.map(l.end))
        }
        func path(_ p: PathGeometry) -> PathGeometry {
            PathGeometry(points: p.points.map { mapping.map($0) })
        }

        var copy = self
        switch kind {
        case .arrow(var data): data.line = line(data.line); copy.kind = .arrow(data)
        case .line(var data): data.line = line(data.line); copy.kind = .line(data)
        case .shape(var data): data.rect = rect(data.rect); copy.kind = .shape(data)
        case .text(var data): data.rect = rect(data.rect); copy.kind = .text(data)
        case .callout(var data):
            data.rect = rect(data.rect)
            data.tail.tip = mapping.map(data.tail.tip)
            copy.kind = .callout(data)
        case .step(var data):
            data.center = mapping.map(data.center)
            data.diameter *= mapping.lengthScale
            copy.kind = .step(data)
        case .magnifier(var data):
            data.source = rect(data.source)
            data.target = rect(data.target)
            copy.kind = .magnifier(data)
        case .blur(var data): data.rect = rect(data.rect); copy.kind = .blur(data)
        case .pixelate(var data): data.rect = rect(data.rect); copy.kind = .pixelate(data)
        case .highlight(var data): data.path = path(data.path); copy.kind = .highlight(data)
        case .pen(var data): data.path = path(data.path); copy.kind = .pen(data)
        case .image(var data): data.rect = rect(data.rect); copy.kind = .image(data)
        case .unknown: break
        }
        return copy
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter DocumentTests`
Expected: PASS, 8 tests. Also run `swift test` — all earlier tests still pass.

- [ ] **Step 6: Commit**

```bash
cd /Users/giovanni/work/reatool
git add PinxelKit
git commit -m "feat(core): add PinxelDocument, image operations and coordinate mapping"
```

---

### Task 4: Automatic step numbering

**Files:**
- Create: `PinxelKit/Sources/DocumentModel/StepNumbering.swift`
- Test: `PinxelKit/Tests/DocumentModelTests/StepNumberingTests.swift`

**Interfaces:**
- Consumes: `Annotation`, `StepData`, `StepLabel`, `StepSequence`.
- Produces: `enum StepNumbering { static func labels(for: [Annotation]) -> [UUID: String]; static func format(_ n: Int, _ sequence: StepSequence) -> String }`. Numbering follows z-order, counted separately per `StepSequence`; an `override` replaces the displayed label but still consumes its position.

- [ ] **Step 1: Write the failing tests**

`PinxelKit/Tests/DocumentModelTests/StepNumberingTests.swift`:

```swift
import Foundation
import Testing
@testable import DocumentModel

struct StepNumberingTests {
    func step(_ sequence: StepSequence = .numbers, override: String? = nil) -> Annotation {
        Annotation(kind: .step(StepData(center: .zero, diameter: 30, label: StepLabel(sequence: sequence, override: override))))
    }

    @Test func numbersFollowOrder() {
        let steps = [step(), step(), step()]
        let labels = StepNumbering.labels(for: steps)
        #expect(steps.map { labels[$0.id] } == ["1", "2", "3"])
    }

    @Test func deletingRenumbers() {
        var steps = [step(), step(), step()]
        steps.remove(at: 1)
        let labels = StepNumbering.labels(for: steps)
        #expect(steps.map { labels[$0.id] } == ["1", "2"])
    }

    @Test func sequencesAreIndependentAndIgnoreOtherKinds() {
        let arrow = Annotation(kind: .line(LineData(line: LineGeometry(start: .zero, end: .zero))))
        let items = [step(), step(.uppercaseLetters), arrow, step(), step(.lowercaseLetters), step(.uppercaseLetters)]
        let labels = StepNumbering.labels(for: items)
        #expect(items.map { labels[$0.id] } == ["1", "A", nil, "2", "a", "B"])
    }

    @Test func overrideReplacesLabelButKeepsPosition() {
        let items = [step(), step(override: "★"), step()]
        let labels = StepNumbering.labels(for: items)
        #expect(items.map { labels[$0.id] } == ["1", "★", "3"])
    }

    @Test func lettersContinuePastZ() {
        #expect(StepNumbering.format(26, .uppercaseLetters) == "Z")
        #expect(StepNumbering.format(27, .uppercaseLetters) == "AA")
        #expect(StepNumbering.format(28, .lowercaseLetters) == "ab")
        #expect(StepNumbering.format(702, .uppercaseLetters) == "ZZ")
        #expect(StepNumbering.format(703, .uppercaseLetters) == "AAA")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter StepNumberingTests`
Expected: build FAILS with `cannot find 'StepNumbering' in scope`.

- [ ] **Step 3: Implement**

`PinxelKit/Sources/DocumentModel/StepNumbering.swift`:

```swift
import Foundation

public enum StepNumbering {
    /// Etichetta visualizzata per ogni step, calcolata dall'ordine in `annotations`.
    public static func labels(for annotations: [Annotation]) -> [UUID: String] {
        var counters: [StepSequence: Int] = [:]
        var result: [UUID: String] = [:]
        for annotation in annotations {
            guard case .step(let data) = annotation.kind else { continue }
            let n = (counters[data.label.sequence] ?? 0) + 1
            counters[data.label.sequence] = n
            result[annotation.id] = data.label.override ?? format(n, data.label.sequence)
        }
        return result
    }

    /// 1 → "1" / "A" / "a"; le lettere usano la numerazione biiettiva in base 26 (27 → "AA").
    public static func format(_ n: Int, _ sequence: StepSequence) -> String {
        switch sequence {
        case .numbers:
            return String(n)
        case .uppercaseLetters, .lowercaseLetters:
            var value = max(n, 1)
            var letters: [Character] = []
            while value > 0 {
                value -= 1
                letters.append(Character(UnicodeScalar(UInt8(65 + value % 26))))
                value /= 26
            }
            let text = String(letters.reversed())
            return sequence == .uppercaseLetters ? text : text.lowercased()
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter StepNumberingTests`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
cd /Users/giovanni/work/reatool
git add PinxelKit
git commit -m "feat(core): add automatic step numbering"
```

---

### Task 5: Edit commands (undo/redo foundation)

**Files:**
- Create: `PinxelKit/Sources/DocumentModel/EditCommand.swift`
- Test: `PinxelKit/Tests/DocumentModelTests/EditCommandTests.swift`

**Interfaces:**
- Consumes: `PinxelDocument`, `Annotation`, `ImageOperation`, `CanvasStyle`, `Annotation.transformed(by:)`.
- Produces:
  - `protocol EditCommand: Sendable { var name: String { get }; func apply(to: inout PinxelDocument); func revert(on: inout PinxelDocument) }`
  - `AddAnnotations(_ annotations: [Annotation], at index: Int? = nil, name: String = "Aggiungi")`
  - `DeleteAnnotations(ids: Set<UUID>, in: PinxelDocument, name: String = "Elimina")`
  - `UpdateAnnotations(name: String = "Modifica", before: [Annotation], after: [Annotation])` + `func merged(with: UpdateAnnotations) -> UpdateAnnotations?`
  - `ReorderAnnotations(name: String = "Disponi", newOrder: [UUID], in: PinxelDocument)` + statics `bringToFront(_:in:)`, `sendToBack(_:in:)`, `bringForward(_:in:)`, `sendBackward(_:in:)` taking `Set<UUID>`.
  - `ApplyImageOperation(_ operation: ImageOperation, in: PinxelDocument)`
  - `UpdateCanvasStyle(before: CanvasStyle, after: CanvasStyle, name: String = "Stile tela")`
  - `CommandGroup(name: String, commands: [any EditCommand])`
  - Invariant: for every command `c` created from document `d`, `apply` then `revert` returns exactly `d`.

- [ ] **Step 1: Write the failing tests**

`PinxelKit/Tests/DocumentModelTests/EditCommandTests.swift`:

```swift
import Foundation
import Testing
@testable import DocumentModel
import PinxelTestSupport

struct EditCommandTests {
    let base = TestDocuments.document()

    func expectReversible(_ command: any EditCommand, on document: PinxelDocument, sourceLocation: SourceLocation = #_sourceLocation) {
        var working = document
        command.apply(to: &working)
        let applied = working
        #expect(applied != document, "command \(command.name) changed nothing", sourceLocation: sourceLocation)
        command.revert(on: &working)
        #expect(working == document, "revert of \(command.name) is not exact", sourceLocation: sourceLocation)
        command.apply(to: &working)
        #expect(working == applied, "redo of \(command.name) differs", sourceLocation: sourceLocation)
    }

    func newShape() -> Annotation {
        Annotation(kind: .shape(ShapeData(rect: CGRect(x: 1, y: 2, width: 3, height: 4), shape: .rectangle)))
    }

    @Test func addAppendsOrInserts() {
        let shape = newShape()
        var document = base
        AddAnnotations([shape]).apply(to: &document)
        #expect(document.annotations.last == shape)
        var inserted = base
        AddAnnotations([shape], at: 0).apply(to: &inserted)
        #expect(inserted.annotations.first == shape)
        expectReversible(AddAnnotations([shape]), on: base)
        expectReversible(AddAnnotations([shape], at: 3), on: base)
    }

    @Test func deleteRestoresOriginalPositions() {
        let ids: Set<UUID> = [TestDocuments.id(2), TestDocuments.id(5), TestDocuments.id(14)]
        let command = DeleteAnnotations(ids: ids, in: base)
        var document = base
        command.apply(to: &document)
        #expect(document.annotations.count == base.annotations.count - 3)
        expectReversible(command, on: base)
    }

    @Test func updateReplacesByID() {
        let before = base.annotations[2]
        var after = before
        after.style.lineWidth = 9
        after.rotation = 0.3
        let command = UpdateAnnotations(before: [before], after: [after])
        var document = base
        command.apply(to: &document)
        #expect(document.annotations[2] == after)
        expectReversible(command, on: base)
    }

    @Test func consecutiveUpdatesMerge() {
        let original = base.annotations[0]
        var step1 = original
        step1.rotation = 0.1
        var step2 = step1
        step2.rotation = 0.2
        let first = UpdateAnnotations(name: "Sposta", before: [original], after: [step1])
        let second = UpdateAnnotations(name: "Sposta", before: [step1], after: [step2])
        let merged = first.merged(with: second)
        #expect(merged?.before == [original])
        #expect(merged?.after == [step2])

        let unrelated = UpdateAnnotations(before: [base.annotations[1]], after: [base.annotations[1]])
        #expect(first.merged(with: unrelated) == nil)
    }

    @Test func reorderHelpers() {
        let order = base.annotations.map(\.id)
        let selected: Set<UUID> = [order[0], order[1]]

        var front = base
        ReorderAnnotations.bringToFront(selected, in: base).apply(to: &front)
        #expect(Array(front.annotations.map(\.id).suffix(2)) == [order[0], order[1]])

        var back = base
        ReorderAnnotations.sendToBack([order[5]], in: base).apply(to: &back)
        #expect(back.annotations.first?.id == order[5])

        var forward = base
        ReorderAnnotations.bringForward(selected, in: base).apply(to: &forward)
        #expect(Array(forward.annotations.map(\.id).prefix(3)) == [order[2], order[0], order[1]])

        var backward = base
        ReorderAnnotations.sendBackward([order[3]], in: base).apply(to: &backward)
        #expect(Array(backward.annotations.map(\.id).prefix(4)) == [order[0], order[1], order[3], order[2]])

        expectReversible(ReorderAnnotations.bringToFront(selected, in: base), on: base)
    }

    @Test func imageOperationTransformsAnnotations() {
        let command = ApplyImageOperation(.crop(PixelRect(x: 10, y: 20, width: 300, height: 200)), in: base)
        var document = base
        command.apply(to: &document)
        #expect(document.imageOperations.count == 1)
        #expect(document.imageSize == PixelSize(width: 300, height: 200))
        #expect(document.annotations[0].bounds.minX == base.annotations[0].bounds.minX - 10)
        #expect(command.name == "Ritaglia")
        expectReversible(command, on: base)
    }

    @Test func cropKeepsAnnotationsOutsideAndRevertsExactly() {
        // Ritaglio sulla metà destra: molte annotazioni finiscono a coordinate negative.
        let command = ApplyImageOperation(.crop(PixelRect(x: 200, y: 150, width: 200, height: 150)), in: base)
        var document = base
        command.apply(to: &document)
        #expect(document.annotations.count == base.annotations.count)
        #expect(document.annotations.contains { $0.bounds.maxX < 0 || $0.bounds.maxY < 0 })
        command.revert(on: &document)
        #expect(document == base)
    }

    @Test func canvasStyleAndGroup() {
        let style = UpdateCanvasStyle(before: base.canvasStyle, after: CanvasStyle(padding: 20, backgroundColor: .white))
        expectReversible(style, on: base)

        let shape = newShape()
        let group = CommandGroup(name: "Incolla", commands: [
            AddAnnotations([shape]),
            ReorderAnnotations(newOrder: [shape.id] + base.annotations.map(\.id), in: base),
        ])
        var document = base
        group.apply(to: &document)
        #expect(document.annotations.first == shape)
        // Il secondo comando è stato creato sul documento senza `shape`: il gruppo deve comunque tornare esattamente a `base`.
        group.revert(on: &document)
        #expect(document == base)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter EditCommandTests`
Expected: build FAILS with `cannot find type 'EditCommand' in scope`.

- [ ] **Step 3: Implement**

`PinxelKit/Sources/DocumentModel/EditCommand.swift`:

```swift
import Foundation

/// Modifica reversibile del documento. Per ogni comando creato da un documento `d`,
/// `apply` seguito da `revert` deve restituire esattamente `d`.
public protocol EditCommand: Sendable {
    /// Nome mostrato in "Annulla <nome>".
    var name: String { get }
    func apply(to document: inout PinxelDocument)
    func revert(on document: inout PinxelDocument)
}

public struct AddAnnotations: EditCommand {
    public let name: String
    public let annotations: [Annotation]
    public let index: Int?

    public init(_ annotations: [Annotation], at index: Int? = nil, name: String = "Aggiungi") {
        self.annotations = annotations
        self.index = index
        self.name = name
    }

    public func apply(to document: inout PinxelDocument) {
        if let index {
            document.annotations.insert(contentsOf: annotations, at: min(max(index, 0), document.annotations.count))
        } else {
            document.annotations.append(contentsOf: annotations)
        }
    }

    public func revert(on document: inout PinxelDocument) {
        let ids = Set(annotations.map(\.id))
        document.annotations.removeAll { ids.contains($0.id) }
    }
}

public struct DeleteAnnotations: EditCommand {
    private struct Removed: Sendable {
        let index: Int
        let annotation: Annotation
    }

    public let name: String
    private let removed: [Removed]

    public init(ids: Set<UUID>, in document: PinxelDocument, name: String = "Elimina") {
        self.name = name
        removed = document.annotations.enumerated()
            .filter { ids.contains($0.element.id) }
            .map { Removed(index: $0.offset, annotation: $0.element) }
    }

    public func apply(to document: inout PinxelDocument) {
        let ids = Set(removed.map(\.annotation.id))
        document.annotations.removeAll { ids.contains($0.id) }
    }

    public func revert(on document: inout PinxelDocument) {
        for item in removed {
            document.annotations.insert(item.annotation, at: min(item.index, document.annotations.count))
        }
    }
}

public struct UpdateAnnotations: EditCommand {
    public let name: String
    public let before: [Annotation]
    public let after: [Annotation]

    public init(name: String = "Modifica", before: [Annotation], after: [Annotation]) {
        self.name = name
        self.before = before
        self.after = after
    }

    public func apply(to document: inout PinxelDocument) { replace(with: after, in: &document) }
    public func revert(on document: inout PinxelDocument) { replace(with: before, in: &document) }

    /// Unisce due modifiche consecutive sugli stessi oggetti (es. spostamenti con le frecce).
    public func merged(with next: UpdateAnnotations) -> UpdateAnnotations? {
        guard Set(after.map(\.id)) == Set(next.before.map(\.id)),
              Set(before.map(\.id)) == Set(next.after.map(\.id)) else { return nil }
        return UpdateAnnotations(name: next.name, before: before, after: next.after)
    }

    private func replace(with annotations: [Annotation], in document: inout PinxelDocument) {
        for annotation in annotations {
            if let index = document.annotations.firstIndex(where: { $0.id == annotation.id }) {
                document.annotations[index] = annotation
            }
        }
    }
}

public struct ReorderAnnotations: EditCommand {
    public let name: String
    private let before: [UUID]
    private let after: [UUID]

    public init(name: String = "Disponi", newOrder: [UUID], in document: PinxelDocument) {
        self.name = name
        before = document.annotations.map(\.id)
        after = newOrder
    }

    public func apply(to document: inout PinxelDocument) { reorder(&document, to: after) }
    public func revert(on document: inout PinxelDocument) { reorder(&document, to: before) }

    private func reorder(_ document: inout PinxelDocument, to order: [UUID]) {
        let byID = Dictionary(uniqueKeysWithValues: document.annotations.map { ($0.id, $0) })
        let ordered = order.compactMap { byID[$0] }
        let listed = Set(order)
        // Le annotazioni non elencate restano in cima, nel loro ordine.
        document.annotations = ordered + document.annotations.filter { !listed.contains($0.id) }
    }

    public static func bringToFront(_ ids: Set<UUID>, in document: PinxelDocument) -> ReorderAnnotations {
        let order = document.annotations.map(\.id)
        return ReorderAnnotations(name: "Porta in primo piano", newOrder: order.filter { !ids.contains($0) } + order.filter { ids.contains($0) }, in: document)
    }

    public static func sendToBack(_ ids: Set<UUID>, in document: PinxelDocument) -> ReorderAnnotations {
        let order = document.annotations.map(\.id)
        return ReorderAnnotations(name: "Porta in fondo", newOrder: order.filter { ids.contains($0) } + order.filter { !ids.contains($0) }, in: document)
    }

    public static func bringForward(_ ids: Set<UUID>, in document: PinxelDocument) -> ReorderAnnotations {
        var order = document.annotations.map(\.id)
        var i = order.count - 2
        while i >= 0 {
            if ids.contains(order[i]) && !ids.contains(order[i + 1]) { order.swapAt(i, i + 1) }
            i -= 1
        }
        return ReorderAnnotations(name: "Porta avanti", newOrder: order, in: document)
    }

    public static func sendBackward(_ ids: Set<UUID>, in document: PinxelDocument) -> ReorderAnnotations {
        var order = document.annotations.map(\.id)
        var i = 1
        while i < order.count {
            if ids.contains(order[i]) && !ids.contains(order[i - 1]) { order.swapAt(i - 1, i) }
            i += 1
        }
        return ReorderAnnotations(name: "Porta indietro", newOrder: order, in: document)
    }
}

public struct ApplyImageOperation: EditCommand {
    public let operation: ImageOperation
    private let annotationsBefore: [Annotation]

    public var name: String { operation.name }

    public init(_ operation: ImageOperation, in document: PinxelDocument) {
        self.operation = operation
        annotationsBefore = document.annotations
    }

    public func apply(to document: inout PinxelDocument) {
        let mapping = operation.mapping(from: document.imageSize)
        document.annotations = annotationsBefore.map { $0.transformed(by: mapping) }
        document.imageOperations.append(operation)
    }

    public func revert(on document: inout PinxelDocument) {
        if !document.imageOperations.isEmpty { document.imageOperations.removeLast() }
        document.annotations = annotationsBefore
    }
}

public struct UpdateCanvasStyle: EditCommand {
    public let name: String
    public let before: CanvasStyle
    public let after: CanvasStyle

    public init(before: CanvasStyle, after: CanvasStyle, name: String = "Stile tela") {
        self.before = before
        self.after = after
        self.name = name
    }

    public func apply(to document: inout PinxelDocument) { document.canvasStyle = after }
    public func revert(on document: inout PinxelDocument) { document.canvasStyle = before }
}

public struct CommandGroup: EditCommand {
    public let name: String
    public let commands: [any EditCommand]

    public init(name: String, commands: [any EditCommand]) {
        self.name = name
        self.commands = commands
    }

    public func apply(to document: inout PinxelDocument) {
        for command in commands { command.apply(to: &document) }
    }

    public func revert(on document: inout PinxelDocument) {
        for command in commands.reversed() { command.revert(on: &document) }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter EditCommandTests`
Expected: PASS, 8 tests.

- [ ] **Step 5: Commit**

```bash
cd /Users/giovanni/work/reatool
git add PinxelKit
git commit -m "feat(core): add reversible edit commands"
```

---

### Task 6: Rendering skeleton — background processing and document renderer

**Files:**
- Modify: `PinxelKit/Package.swift`
- Create: `PinxelKit/Sources/Rendering/ImageDrawing.swift`
- Create: `PinxelKit/Sources/Rendering/BackgroundProcessor.swift`
- Create: `PinxelKit/Sources/Rendering/EffectCache.swift`
- Create: `PinxelKit/Sources/Rendering/StrokeStyle.swift`
- Create: `PinxelKit/Sources/Rendering/AnnotationRenderer.swift`
- Create: `PinxelKit/Sources/Rendering/DocumentRenderer.swift`
- Create: `PinxelKit/Tests/RenderingTests/Snapshot.swift`
- Create: `PinxelKit/Tests/RenderingTests/__Snapshots__/.gitkeep`
- Test: `PinxelKit/Tests/RenderingTests/BackgroundTests.swift`

**Interfaces:**
- Consumes: `PinxelDocument`, `ImageOperation`, `CutOut`, `PixelRect`, `RGBA`, `Shadow`, `Style`, `StepNumbering`.
- Produces:
  - `protocol AssetProvider { func image(for: ImageAssetRef) -> CGImage? }`; `struct DictionaryAssetProvider: AssetProvider { var images: [ImageAssetRef: CGImage]; init(_:) }`
  - `struct RenderOptions { var outputScale: Double = 1; var excludedAnnotationIDs: Set<UUID> = []; var matte: RGBA? = nil }`
  - `enum RenderError: Error, Equatable { missingBackground, invalidSize, contextCreationFailed }`
  - `final class DocumentRenderer { init(); func canvasSize(for:) -> CGSize; func processedBackground(for:assets:) throws -> CGImage; func render(_:assets:in:options:) throws; func renderImage(_:assets:options:) throws -> CGImage }`. `render` draws into any `CGContext` whose user space is the output in pixels with the default bottom-left origin (bitmap or PDF).
  - `enum BackgroundProcessor { static func process(_: CGImage, operations: [ImageOperation]) -> CGImage? }`
  - Internal: `ImageDrawing.sRGB`, `ImageDrawing.makeContext(width:height:)`, `ImageDrawing.draw(_:in:context:)` (draws an image in a top-left-origin context), `ImageDrawing.clampedInt(_:)`, `extension RGBA { var cgColor: CGColor }`, `EffectCache.image(for:make:)`, `EffectCache.removeAll()`, `StrokeStyle.apply(_:to:)`, `ShadowStyle.apply(_:to:outputScale:)`, `struct RenderContext { background, stepLabels, assets, outputScale, effects }`, `AnnotationRenderer.draw(_:in:context:)`.
  - Test helper: `Snapshot.assertMatches(_ image: CGImage, named: String, tolerance: Double = 0.01)`.

- [ ] **Step 1: Add the Rendering targets to the package**

Replace `PinxelKit/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PinxelKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "DocumentModel", targets: ["DocumentModel"]),
        .library(name: "Rendering", targets: ["Rendering"]),
    ],
    targets: [
        .target(name: "DocumentModel"),
        .target(name: "Rendering", dependencies: ["DocumentModel"]),
        .target(
            name: "PinxelTestSupport",
            dependencies: ["DocumentModel"],
            path: "Tests/PinxelTestSupport"
        ),
        .testTarget(
            name: "DocumentModelTests",
            dependencies: ["DocumentModel", "PinxelTestSupport"]
        ),
        .testTarget(
            name: "RenderingTests",
            dependencies: ["Rendering", "PinxelTestSupport"],
            exclude: ["__Snapshots__"]
        ),
    ]
)
```

Create the empty file `PinxelKit/Tests/RenderingTests/__Snapshots__/.gitkeep`.

- [ ] **Step 2: Write the snapshot helper and the failing tests**

`PinxelKit/Tests/RenderingTests/Snapshot.swift`:

```swift
import CoreGraphics
import Foundation
import ImageIO
import PinxelTestSupport
import Testing
import UniformTypeIdentifiers

/// Confronto con PNG di riferimento in `__Snapshots__/`.
/// Se il riferimento manca (o con PINXEL_RECORD_SNAPSHOTS=1) lo scrive e fa fallire il test:
/// controlla l'immagine a occhio, poi rilancia.
enum Snapshot {
    static func assertMatches(
        _ image: CGImage,
        named name: String,
        tolerance: Double = 0.01,
        filePath: String = #filePath,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let directory = URL(fileURLWithPath: filePath).deletingLastPathComponent().appendingPathComponent("__Snapshots__")
        let reference = directory.appendingPathComponent("\(name).png")
        let recording = ProcessInfo.processInfo.environment["PINXEL_RECORD_SNAPSHOTS"] == "1"

        if recording || !FileManager.default.fileExists(atPath: reference.path) {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try writePNG(image, to: reference)
                Issue.record("Snapshot '\(name)' registrato in \(reference.path): controllalo e rilancia i test.", sourceLocation: sourceLocation)
            } catch {
                Issue.record("Impossibile scrivere lo snapshot '\(name)': \(error)", sourceLocation: sourceLocation)
            }
            return
        }

        guard let source = CGImageSourceCreateWithURL(reference as CFURL, nil),
              let expected = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            Issue.record("Snapshot '\(name)' illeggibile", sourceLocation: sourceLocation)
            return
        }
        let difference = PixelBuffer(image).differingPixelFraction(from: PixelBuffer(expected))
        if difference > tolerance {
            let actual = directory.appendingPathComponent("\(name).actual.png")
            try? writePNG(image, to: actual)
            Issue.record(
                "Snapshot '\(name)' differisce del \(difference * 100)% (tolleranza \(tolerance * 100)%). Risultato in \(actual.path)",
                sourceLocation: sourceLocation
            )
        }
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}
```

`PinxelKit/Tests/RenderingTests/BackgroundTests.swift`:

```swift
import CoreGraphics
import Foundation
import Testing
import DocumentModel
@testable import Rendering
import PinxelTestSupport

let red = RGBA8(r: 255, g: 0, b: 0)
let green = RGBA8(r: 0, g: 255, b: 0)
let blue = RGBA8(r: 0, g: 0, b: 255)
let yellow = RGBA8(r: 255, g: 255, b: 0)
let white = RGBA8(r: 255, g: 255, b: 255)

func emptyDocument(size: PixelSize = PixelSize(width: 400, height: 300)) -> PinxelDocument {
    TestDocuments.document(annotations: [], size: size)
}

func assets(_ background: CGImage = TestImages.quadrants()) -> DictionaryAssetProvider {
    DictionaryAssetProvider([
        TestDocuments.background: background,
        TestDocuments.placedImage: TestImages.solid(width: 10, height: 10, red: 0, green: 0.6, blue: 1),
    ])
}

struct BackgroundTests {
    let quadrants = TestImages.quadrants()

    @Test func cropKeepsTopRightQuadrant() throws {
        let result = try #require(BackgroundProcessor.process(quadrants, operations: [.crop(PixelRect(x: 200, y: 0, width: 200, height: 150))]))
        #expect(result.width == 200 && result.height == 150)
        let pixels = PixelBuffer(result)
        #expect(pixels.pixel(x: 5, y: 5) == green)
        #expect(pixels.pixel(x: 195, y: 145) == green)
    }

    @Test func cropOutsideImageFails() {
        #expect(BackgroundProcessor.process(quadrants, operations: [.crop(PixelRect(x: 500, y: 0, width: 10, height: 10))]) == nil)
    }

    @Test func resizeHalvesImage() throws {
        let result = try #require(BackgroundProcessor.process(quadrants, operations: [.resize(PixelSize(width: 200, height: 150))]))
        #expect(result.width == 200 && result.height == 150)
        #expect(PixelBuffer(result).pixel(x: 50, y: 37) == red)
    }

    @Test func horizontalCutOutJoinsBands() throws {
        let cut = CutOut(axis: .horizontal, start: 100, length: 100, edge: .straight)
        let result = try #require(BackgroundProcessor.process(quadrants, operations: [.cutOut(cut)]))
        #expect(result.width == 400 && result.height == 200)
        let pixels = PixelBuffer(result)
        #expect(pixels.pixel(x: 10, y: 99) == red)   // riga 99 originale
        #expect(pixels.pixel(x: 10, y: 100) == blue) // riga 200 originale
    }

    @Test func verticalCutOutJoinsBands() throws {
        let cut = CutOut(axis: .vertical, start: 150, length: 100, edge: .straight)
        let result = try #require(BackgroundProcessor.process(quadrants, operations: [.cutOut(cut)]))
        #expect(result.width == 300 && result.height == 300)
        let pixels = PixelBuffer(result)
        #expect(pixels.pixel(x: 149, y: 10) == red)
        #expect(pixels.pixel(x: 150, y: 10) == green) // colonna 250 originale
    }

    @Test func zigzagCutOutDrawsSeam() throws {
        let cut = CutOut(axis: .horizontal, start: 100, length: 100, edge: .zigzag)
        let result = try #require(BackgroundProcessor.process(quadrants, operations: [.cutOut(cut)]))
        Snapshot.assertMatches(result, named: "cutout-zigzag")
    }

    @Test func emptyDocumentRendersBackgroundExactly() throws {
        let image = try DocumentRenderer().renderImage(emptyDocument(), assets: assets())
        #expect(PixelBuffer(image).differingPixelFraction(from: PixelBuffer(quadrants), channelTolerance: 1) == 0)
    }

    @Test func paddingAndBackgroundColor() throws {
        var document = emptyDocument()
        document.canvasStyle = CanvasStyle(padding: 10, backgroundColor: .white)
        let renderer = DocumentRenderer()
        #expect(renderer.canvasSize(for: document) == CGSize(width: 420, height: 320))
        let pixels = PixelBuffer(try renderer.renderImage(document, assets: assets()))
        #expect(pixels.width == 420 && pixels.height == 320)
        #expect(pixels.pixel(x: 5, y: 5) == white)
        #expect(pixels.pixel(x: 15, y: 15) == red)
        #expect(pixels.pixel(x: 405, y: 305) == yellow)
    }

    @Test func outputScaleChangesPixelSize() throws {
        let image = try DocumentRenderer().renderImage(emptyDocument(), assets: assets(), options: RenderOptions(outputScale: 0.5))
        #expect(image.width == 200 && image.height == 150)
    }

    @Test func missingBackgroundThrows() {
        #expect(throws: RenderError.missingBackground) {
            try DocumentRenderer().renderImage(emptyDocument(), assets: DictionaryAssetProvider([:]))
        }
    }

    @Test func operationsAreAppliedWhenRendering() throws {
        var document = emptyDocument()
        document.imageOperations = [.crop(PixelRect(x: 0, y: 150, width: 200, height: 150))]
        let image = try DocumentRenderer().renderImage(document, assets: assets())
        #expect(image.width == 200 && image.height == 150)
        #expect(PixelBuffer(image).pixel(x: 100, y: 75) == blue)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter BackgroundTests`
Expected: build FAILS with `cannot find 'BackgroundProcessor' in scope` (the `Rendering` target has no sources).

- [ ] **Step 4: Implement drawing helpers, background processor, cache and styles**

`PinxelKit/Sources/Rendering/ImageDrawing.swift`:

```swift
import CoreGraphics
import DocumentModel

enum ImageDrawing {
    nonisolated(unsafe) static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    static func makeContext(width: Int, height: Int) -> CGContext? {
        guard width > 0, height > 0 else { return nil }
        return CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    /// Disegna `image` in `rect` in un contesto già capovolto (origine in alto a sinistra).
    static func draw(_ image: CGImage, in rect: CGRect, context ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
        ctx.restoreGState()
    }

    /// Conversione sicura a Int anche per coordinate enormi.
    static func clampedInt(_ value: CGFloat) -> Int {
        Int(max(-10_000_000, min(10_000_000, value)))
    }
}

extension RGBA {
    var cgColor: CGColor {
        CGColor(colorSpace: ImageDrawing.sRGB, components: [red, green, blue, alpha])!
    }
}
```

`PinxelKit/Sources/Rendering/BackgroundProcessor.swift`:

```swift
import CoreGraphics
import DocumentModel

public enum BackgroundProcessor {
    /// Applica le operazioni in sequenza; `nil` se un'operazione produce un'immagine vuota.
    public static func process(_ image: CGImage, operations: [ImageOperation]) -> CGImage? {
        var current = image
        for operation in operations {
            guard let next = apply(operation, to: current) else { return nil }
            current = next
        }
        return current
    }

    static func apply(_ operation: ImageOperation, to image: CGImage) -> CGImage? {
        let size = PixelSize(width: image.width, height: image.height)
        switch operation {
        case .crop(let rect):
            let clamped = rect.clamped(to: size)
            guard clamped.width > 0, clamped.height > 0 else { return nil }
            return image.cropping(to: clamped.cgRect)
        case .resize(let target):
            guard let ctx = ImageDrawing.makeContext(width: target.width, height: target.height) else { return nil }
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(origin: .zero, size: target.cgSize))
            return ctx.makeImage()
        case .cutOut(let cut):
            return cutOut(cut, from: image, size: size)
        }
    }

    private static func cutOut(_ cut: CutOut, from image: CGImage, size: PixelSize) -> CGImage? {
        let start = cut.clampedStart(in: size)
        let length = cut.clampedLength(in: size)
        let result = ImageOperation.cutOut(cut).resultSize(from: size)
        guard let ctx = ImageDrawing.makeContext(width: result.width, height: result.height) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(result.height))
        ctx.scaleBy(x: 1, y: -1)

        let first: PixelRect
        let second: PixelRect
        let secondOrigin: CGPoint
        let seam: (CGPoint, CGPoint)
        switch cut.axis {
        case .horizontal:
            first = PixelRect(x: 0, y: 0, width: size.width, height: start)
            second = PixelRect(x: 0, y: start + length, width: size.width, height: size.height - start - length)
            secondOrigin = CGPoint(x: 0, y: start)
            seam = (CGPoint(x: 0, y: start), CGPoint(x: size.width, y: start))
        case .vertical:
            first = PixelRect(x: 0, y: 0, width: start, height: size.height)
            second = PixelRect(x: start + length, y: 0, width: size.width - start - length, height: size.height)
            secondOrigin = CGPoint(x: start, y: 0)
            seam = (CGPoint(x: start, y: 0), CGPoint(x: start, y: size.height))
        }
        if first.width > 0, first.height > 0, let part = image.cropping(to: first.cgRect) {
            ImageDrawing.draw(part, in: CGRect(x: 0, y: 0, width: first.width, height: first.height), context: ctx)
        }
        if second.width > 0, second.height > 0, let part = image.cropping(to: second.cgRect) {
            ImageDrawing.draw(part, in: CGRect(origin: secondOrigin, size: CGSize(width: second.width, height: second.height)), context: ctx)
        }
        if cut.edge == .zigzag, length > 0 {
            drawZigzag(from: seam.0, to: seam.1, in: ctx)
        }
        return ctx.makeImage()
    }

    private static func drawZigzag(from a: CGPoint, to b: CGPoint, in ctx: CGContext) {
        let horizontal = a.y == b.y
        let length = horizontal ? b.x - a.x : b.y - a.y
        let period: CGFloat = 12
        let amplitude: CGFloat = 4
        let path = CGMutablePath()
        path.move(to: a)
        var t: CGFloat = 0
        var up = true
        while t < length {
            t = min(t + period / 2, length)
            let offset = up ? -amplitude : amplitude
            path.addLine(to: horizontal ? CGPoint(x: a.x + t, y: a.y + offset) : CGPoint(x: a.x + offset, y: a.y + t))
            up.toggle()
        }
        ctx.setStrokeColor(CGColor(gray: 0.45, alpha: 1))
        ctx.setLineWidth(2)
        ctx.setLineJoin(.miter)
        ctx.addPath(path)
        ctx.strokePath()
    }
}
```

`PinxelKit/Sources/Rendering/EffectCache.swift`:

```swift
import CoreGraphics

/// Piccola cache LRU per sfocature/pixelature già calcolate.
final class EffectCache {
    private var storage: [String: CGImage] = [:]
    private var order: [String] = []
    private let capacity: Int

    init(capacity: Int = 64) {
        self.capacity = capacity
    }

    func image(for key: String, make: () -> CGImage?) -> CGImage? {
        if let hit = storage[key] { return hit }
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

`PinxelKit/Sources/Rendering/StrokeStyle.swift`:

```swift
import CoreGraphics
import DocumentModel

enum StrokeStyle {
    static func apply(_ style: Style, to ctx: CGContext) {
        ctx.setLineWidth(style.lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        if let stroke = style.stroke { ctx.setStrokeColor(stroke.cgColor) }
        switch style.dash {
        case .solid: ctx.setLineDash(phase: 0, lengths: [])
        case .dashed: ctx.setLineDash(phase: 0, lengths: [style.lineWidth * 3, style.lineWidth * 2])
        case .dotted: ctx.setLineDash(phase: 0, lengths: [0.01, style.lineWidth * 2])
        }
    }
}

enum ShadowStyle {
    /// Le ombre di Core Graphics ignorano la CTM: offset e blur vanno in pixel di output,
    /// e la y è invertita perché il contesto del documento è capovolto.
    static func apply(_ shadow: Shadow, to ctx: CGContext, outputScale: Double) {
        ctx.setShadow(
            offset: CGSize(width: shadow.offset.width * outputScale, height: -shadow.offset.height * outputScale),
            blur: shadow.blur * outputScale,
            color: shadow.color.cgColor
        )
    }
}
```

- [ ] **Step 5: Implement the dispatcher and the document renderer**

`PinxelKit/Sources/Rendering/AnnotationRenderer.swift`:

```swift
import CoreGraphics
import DocumentModel
import Foundation

struct RenderContext {
    /// Sfondo dopo le operazioni immagine, senza annotazioni (sorgente di sfocatura, pixel e lente).
    let background: CGImage
    let stepLabels: [UUID: String]
    let assets: any AssetProvider
    let outputScale: Double
    let effects: EffectCache
}

enum AnnotationRenderer {
    static func draw(_ annotation: Annotation, in ctx: CGContext, context: RenderContext) {
        let bounds = annotation.bounds
        guard !bounds.isNull,
              bounds.minX.isFinite, bounds.minY.isFinite,
              bounds.width.isFinite, bounds.height.isFinite else { return }

        ctx.saveGState()
        defer { ctx.restoreGState() }
        if annotation.rotation != 0 {
            ctx.translateBy(x: bounds.midX, y: bounds.midY)
            ctx.rotate(by: annotation.rotation)
            ctx.translateBy(x: -bounds.midX, y: -bounds.midY)
        }
        if let shadow = annotation.style.shadow {
            ShadowStyle.apply(shadow, to: ctx, outputScale: context.outputScale)
        }
        // L'evidenziatore si fonde in multiply con lo sfondo: il livello va composto in multiply.
        if case .highlight = annotation.kind { ctx.setBlendMode(.multiply) }
        ctx.setAlpha(annotation.style.opacity)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        drawContent(annotation, in: ctx, context: context)
        ctx.endTransparencyLayer()
    }

    private static func drawContent(_ annotation: Annotation, in ctx: CGContext, context: RenderContext) {
        switch annotation.kind {
        default:
            break
        }
    }
}
```

`PinxelKit/Sources/Rendering/DocumentRenderer.swift`:

```swift
import CoreGraphics
import DocumentModel
import Foundation

public protocol AssetProvider {
    func image(for ref: ImageAssetRef) -> CGImage?
}

public struct DictionaryAssetProvider: AssetProvider {
    public var images: [ImageAssetRef: CGImage]

    public init(_ images: [ImageAssetRef: CGImage]) {
        self.images = images
    }

    public func image(for ref: ImageAssetRef) -> CGImage? { images[ref] }
}

public struct RenderOptions: Sendable {
    /// Pixel di output per pixel del documento.
    public var outputScale: Double
    /// Annotazioni da non disegnare (es. il testo in modifica nell'editor).
    public var excludedAnnotationIDs: Set<UUID>
    /// Colore pieno sotto tutto (es. bianco per JPEG).
    public var matte: RGBA?

    public init(outputScale: Double = 1, excludedAnnotationIDs: Set<UUID> = [], matte: RGBA? = nil) {
        self.outputScale = outputScale
        self.excludedAnnotationIDs = excludedAnnotationIDs
        self.matte = matte
    }
}

public enum RenderError: Error, Equatable {
    case missingBackground
    case invalidSize
    case contextCreationFailed
}

/// Unico percorso di disegno per canvas, miniature ed export.
public final class DocumentRenderer {
    private var processedKey: String?
    private var processedImage: CGImage?
    private let effects = EffectCache()

    public init() {}

    /// Dimensioni della tela (immagine + padding) in pixel del documento.
    public func canvasSize(for document: PinxelDocument) -> CGSize {
        let image = document.imageSize
        let padding = document.canvasStyle.padding
        return CGSize(width: Double(image.width) + 2 * padding, height: Double(image.height) + 2 * padding)
    }

    public func processedBackground(for document: PinxelDocument, assets: any AssetProvider) throws -> CGImage {
        guard let original = assets.image(for: document.background) else { throw RenderError.missingBackground }
        let key = "\(ObjectIdentifier(original))|\(document.imageOperations)"
        if key == processedKey, let cached = processedImage { return cached }
        guard let processed = BackgroundProcessor.process(original, operations: document.imageOperations) else {
            throw RenderError.invalidSize
        }
        processedKey = key
        processedImage = processed
        effects.removeAll()
        return processed
    }

    /// Disegna il documento in `ctx`, il cui spazio utente è l'output in pixel con origine in basso a sinistra.
    public func render(_ document: PinxelDocument, assets: any AssetProvider, in ctx: CGContext, options: RenderOptions = RenderOptions()) throws {
        let background = try processedBackground(for: document, assets: assets)
        let canvas = canvasSize(for: document)
        let style = document.canvasStyle
        let imageRect = CGRect(x: style.padding, y: style.padding, width: Double(background.width), height: Double(background.height))

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

        ctx.saveGState()
        if let shadow = style.shadow {
            ShadowStyle.apply(shadow, to: ctx, outputScale: options.outputScale)
        }
        ImageDrawing.draw(background, in: imageRect, context: ctx)
        ctx.restoreGState()

        if let border = style.border, border.width > 0 {
            ctx.setStrokeColor(border.color.cgColor)
            ctx.setLineWidth(border.width)
            ctx.setLineDash(phase: 0, lengths: [])
            ctx.stroke(imageRect.insetBy(dx: border.width / 2, dy: border.width / 2))
        }

        let context = RenderContext(
            background: background,
            stepLabels: StepNumbering.labels(for: document.annotations),
            assets: assets,
            outputScale: options.outputScale,
            effects: effects
        )
        ctx.translateBy(x: style.padding, y: style.padding)
        for annotation in document.annotations where !options.excludedAnnotationIDs.contains(annotation.id) {
            AnnotationRenderer.draw(annotation, in: ctx, context: context)
        }
    }

    public func renderImage(_ document: PinxelDocument, assets: any AssetProvider, options: RenderOptions = RenderOptions()) throws -> CGImage {
        let canvas = canvasSize(for: document)
        let width = Int((canvas.width * options.outputScale).rounded())
        let height = Int((canvas.height * options.outputScale).rounded())
        guard width > 0, height > 0 else { throw RenderError.invalidSize }
        guard let ctx = ImageDrawing.makeContext(width: width, height: height) else { throw RenderError.contextCreationFailed }
        try render(document, assets: assets, in: ctx, options: options)
        guard let image = ctx.makeImage() else { throw RenderError.contextCreationFailed }
        return image
    }
}
```

- [ ] **Step 6: Run tests and record the first snapshot**

Run: `swift test --filter BackgroundTests`
Expected: 10 PASS, 1 FAIL — `zigzagCutOutDrawsSeam` reports `Snapshot 'cutout-zigzag' registrato in …`.

Open `PinxelKit/Tests/RenderingTests/__Snapshots__/cutout-zigzag.png` and check: 400×200, red|green on top, blue|yellow below, with a grey zigzag line across row 100. If it looks wrong, fix the code, delete the PNG and re-run.

- [ ] **Step 7: Run tests to verify they pass**

Run: `swift test --filter BackgroundTests`
Expected: PASS, 11 tests.

- [ ] **Step 8: Commit**

```bash
cd /Users/giovanni/work/reatool
git add PinxelKit
git commit -m "feat(rendering): add document renderer and background image operations"
```

---

### Task 7: Rendering lines, arrows, shapes, pen and highlighter

**Files:**
- Create: `PinxelKit/Sources/Rendering/ShapeRenderer.swift`
- Modify: `PinxelKit/Sources/Rendering/AnnotationRenderer.swift` (the `drawContent` switch)
- Test: `PinxelKit/Tests/RenderingTests/ShapeRenderingTests.swift`

**Interfaces:**
- Consumes: Task 6 internals (`StrokeStyle`, `RGBA.cgColor`, `RenderContext`), payloads from Task 2.
- Produces (internal): `ShapeRenderer.drawLine(_: LineGeometry, style:in:)`, `drawArrow(_: ArrowData, style:in:)`, `drawShape(_: ShapeData, style:in:)`, `drawPen(_: PenData, style:in:)`, `drawHighlight(_: HighlightData, style:in:)`, `shapePath(_: ShapeType, in: CGRect) -> CGPath`, `smoothedPath(_: [CGPoint], smoothing: Double) -> CGPath`.

- [ ] **Step 1: Write the failing tests**

`PinxelKit/Tests/RenderingTests/ShapeRenderingTests.swift`:

```swift
import CoreGraphics
import Foundation
import Testing
import DocumentModel
@testable import Rendering
import PinxelTestSupport

struct ShapeRenderingTests {
    let whiteBackground = TestImages.solid(width: 400, height: 300, red: 1, green: 1, blue: 1)

    func render(_ annotations: [Annotation], background: CGImage? = nil) throws -> CGImage {
        try DocumentRenderer().renderImage(TestDocuments.document(annotations: annotations), assets: assets(background ?? whiteBackground))
    }

    @Test func shapesSnapshot() throws {
        let annotations: [Annotation] = [
            Annotation(kind: .arrow(ArrowData(line: LineGeometry(start: CGPoint(x: 20, y: 30), end: CGPoint(x: 160, y: 30)), heads: ArrowHeads(start: .none, end: .triangle)))),
            Annotation(kind: .arrow(ArrowData(line: LineGeometry(start: CGPoint(x: 20, y: 70), end: CGPoint(x: 160, y: 70)), heads: ArrowHeads(start: .circle, end: .open))), style: Style(stroke: .black, lineWidth: 3)),
            Annotation(kind: .arrow(ArrowData(line: LineGeometry(start: CGPoint(x: 20, y: 140), end: CGPoint(x: 160, y: 100)), heads: ArrowHeads(start: .triangle, end: .triangle))), style: Style(lineWidth: 8)),
            Annotation(kind: .line(LineData(line: LineGeometry(start: CGPoint(x: 20, y: 170), end: CGPoint(x: 160, y: 170)))), style: Style(stroke: .black, lineWidth: 2)),
            Annotation(kind: .shape(ShapeData(rect: CGRect(x: 200, y: 20, width: 80, height: 50), shape: .rectangle))),
            Annotation(kind: .shape(ShapeData(rect: CGRect(x: 300, y: 20, width: 80, height: 50), shape: .roundedRectangle(cornerRadius: 12))), style: Style(stroke: .black, fill: .highlightYellow, lineWidth: 2)),
            Annotation(kind: .shape(ShapeData(rect: CGRect(x: 200, y: 90, width: 80, height: 50), shape: .ellipse)), style: Style(stroke: nil, fill: .accentRed)),
            Annotation(kind: .pen(PenData(path: PathGeometry(points: [CGPoint(x: 300, y: 100), CGPoint(x: 320, y: 140), CGPoint(x: 340, y: 100), CGPoint(x: 360, y: 140), CGPoint(x: 380, y: 100)]), smoothing: 1)), style: Style(stroke: .black, lineWidth: 3)),
            Annotation(kind: .highlight(HighlightData(path: PathGeometry(points: [CGPoint(x: 20, y: 220), CGPoint(x: 380, y: 220)]))), style: Style(stroke: .highlightYellow, lineWidth: 20)),
        ]
        Snapshot.assertMatches(try render(annotations), named: "shapes")
    }

    @Test func stylesSnapshot() throws {
        let rect = CGRect(x: 40, y: 40, width: 100, height: 60)
        let annotations: [Annotation] = [
            Annotation(kind: .shape(ShapeData(rect: rect, shape: .rectangle)), style: Style(lineWidth: 4, dash: .dashed)),
            Annotation(kind: .shape(ShapeData(rect: rect.offsetBy(dx: 160, dy: 0), shape: .rectangle)), style: Style(stroke: .black, lineWidth: 4, dash: .dotted)),
            Annotation(kind: .shape(ShapeData(rect: rect.offsetBy(dx: 0, dy: 120), shape: .rectangle)), style: Style(stroke: .accentRed, fill: .accentRed), rotation: .pi / 6),
            Annotation(kind: .shape(ShapeData(rect: rect.offsetBy(dx: 160, dy: 120), shape: .ellipse)),
                       style: Style(stroke: .black, fill: .highlightYellow, lineWidth: 3, opacity: 0.5, shadow: Shadow(offset: CGSize(width: 4, height: 6), blur: 6, color: .black))),
        ]
        Snapshot.assertMatches(try render(annotations), named: "styles")
    }

    @Test func highlighterMultipliesWithBackground() throws {
        // Giallo in multiply sul quadrante blu (in basso a sinistra) dà quasi nero.
        let highlight = Annotation(kind: .highlight(HighlightData(path: PathGeometry(points: [CGPoint(x: 20, y: 250), CGPoint(x: 180, y: 250)]))),
                                   style: Style(stroke: RGBA(red: 1, green: 1, blue: 0), lineWidth: 20))
        let pixels = PixelBuffer(try render([highlight], background: TestImages.quadrants()))
        let p = pixels.pixel(x: 100, y: 250)
        #expect(p.r < 30 && p.g < 30 && p.b < 30, "got \(p)")
    }

    @Test func degenerateAnnotationsDoNotCrash() throws {
        let nothing: [Annotation] = [
            Annotation(kind: .shape(ShapeData(rect: CGRect(x: 50, y: 50, width: 0, height: 0), shape: .roundedRectangle(cornerRadius: 30)))),
            Annotation(kind: .pen(PenData(path: PathGeometry(points: [])))),
            Annotation(kind: .shape(ShapeData(rect: CGRect(x: .nan, y: 10, width: 10, height: 10), shape: .rectangle))),
            Annotation(kind: .line(LineData(line: LineGeometry(start: CGPoint(x: .infinity, y: 0), end: CGPoint(x: 1, y: 1))))),
        ]
        let image = try render(nothing)
        #expect(PixelBuffer(image).differingPixelFraction(from: PixelBuffer(whiteBackground), channelTolerance: 1) == 0)

        // Freccia lunga zero e penna con un solo punto: un punto è accettabile, un crash no.
        let dots: [Annotation] = [
            Annotation(kind: .arrow(ArrowData(line: LineGeometry(start: CGPoint(x: 80, y: 80), end: CGPoint(x: 80, y: 80))))),
            Annotation(kind: .pen(PenData(path: PathGeometry(points: [CGPoint(x: 120, y: 120)])))),
            Annotation(kind: .shape(ShapeData(rect: CGRect(x: 1e300, y: 1e300, width: 5, height: 5), shape: .ellipse))),
        ]
        let dotted = try render(dots)
        #expect(dotted.width == 400 && dotted.height == 300)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ShapeRenderingTests`
Expected: snapshot tests FAIL (references missing / nothing drawn) and `highlighterMultipliesWithBackground` FAILS (pixel is still blue, `b` = 255). `degenerateAnnotationsDoNotCrash` passes trivially for now.

- [ ] **Step 3: Implement the shape renderer**

`PinxelKit/Sources/Rendering/ShapeRenderer.swift`:

```swift
import CoreGraphics
import DocumentModel

enum ShapeRenderer {
    static func drawLine(_ line: LineGeometry, style: Style, in ctx: CGContext) {
        guard style.stroke != nil, style.lineWidth > 0 else { return }
        StrokeStyle.apply(style, to: ctx)
        ctx.move(to: line.start)
        ctx.addLine(to: line.end)
        ctx.strokePath()
    }

    static func drawArrow(_ data: ArrowData, style: Style, in ctx: CGContext) {
        guard let color = style.stroke, style.lineWidth > 0 else { return }
        let start = data.line.start
        let end = data.line.end
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0.5 else {
            drawLine(data.line, style: style, in: ctx)
            return
        }
        let ux = dx / length
        let uy = dy / length
        let headLength = min(max(style.lineWidth * 3, 10), length * 0.5)

        var shaftStart = start
        var shaftEnd = end
        if data.heads.start == .triangle {
            shaftStart = CGPoint(x: start.x + ux * headLength * 0.8, y: start.y + uy * headLength * 0.8)
        }
        if data.heads.end == .triangle {
            shaftEnd = CGPoint(x: end.x - ux * headLength * 0.8, y: end.y - uy * headLength * 0.8)
        }
        StrokeStyle.apply(style, to: ctx)
        ctx.move(to: shaftStart)
        ctx.addLine(to: shaftEnd)
        ctx.strokePath()

        ctx.setLineDash(phase: 0, lengths: [])
        drawHead(data.heads.end, tip: end, ux: ux, uy: uy, headLength: headLength, color: color, in: ctx)
        drawHead(data.heads.start, tip: start, ux: -ux, uy: -uy, headLength: headLength, color: color, in: ctx)
    }

    private static func drawHead(_ head: HeadStyle, tip: CGPoint, ux: CGFloat, uy: CGFloat, headLength: CGFloat, color: RGBA, in ctx: CGContext) {
        let halfWidth = headLength * 0.6
        let base = CGPoint(x: tip.x - ux * headLength, y: tip.y - uy * headLength)
        let left = CGPoint(x: base.x - uy * halfWidth, y: base.y + ux * halfWidth)
        let right = CGPoint(x: base.x + uy * halfWidth, y: base.y - ux * halfWidth)
        switch head {
        case .none:
            return
        case .triangle:
            ctx.setFillColor(color.cgColor)
            ctx.move(to: tip)
            ctx.addLine(to: left)
            ctx.addLine(to: right)
            ctx.closePath()
            ctx.fillPath()
        case .open:
            ctx.move(to: left)
            ctx.addLine(to: tip)
            ctx.addLine(to: right)
            ctx.strokePath()
        case .circle:
            let radius = headLength * 0.4
            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: CGRect(x: tip.x - radius, y: tip.y - radius, width: radius * 2, height: radius * 2))
        }
    }

    static func shapePath(_ shape: ShapeType, in rect: CGRect) -> CGPath {
        switch shape {
        case .rectangle:
            return CGPath(rect: rect, transform: nil)
        case .roundedRectangle(let cornerRadius):
            let radius = max(0, min(cornerRadius, min(rect.width, rect.height) / 2))
            return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        case .ellipse:
            return CGPath(ellipseIn: rect, transform: nil)
        }
    }

    static func drawShape(_ data: ShapeData, style: Style, in ctx: CGContext) {
        let rect = data.rect.standardized
        guard rect.width > 0, rect.height > 0 else { return }
        let path = shapePath(data.shape, in: rect)
        if let fill = style.fill {
            ctx.setFillColor(fill.cgColor)
            ctx.addPath(path)
            ctx.fillPath()
        }
        if style.stroke != nil, style.lineWidth > 0 {
            StrokeStyle.apply(style, to: ctx)
            ctx.addPath(path)
            ctx.strokePath()
        }
    }

    /// Con `smoothing > 0` i punti sono uniti da curve quadratiche passanti per i punti medi.
    static func smoothedPath(_ points: [CGPoint], smoothing: Double) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        if points.count == 1 {
            path.addLine(to: first)
            return path
        }
        if smoothing <= 0 || points.count < 3 {
            for point in points.dropFirst() { path.addLine(to: point) }
            return path
        }
        for i in 1..<(points.count - 1) {
            let mid = CGPoint(x: (points[i].x + points[i + 1].x) / 2, y: (points[i].y + points[i + 1].y) / 2)
            path.addQuadCurve(to: mid, control: points[i])
        }
        path.addLine(to: points[points.count - 1])
        return path
    }

    static func drawPen(_ data: PenData, style: Style, in ctx: CGContext) {
        guard style.stroke != nil, style.lineWidth > 0, !data.path.points.isEmpty else { return }
        StrokeStyle.apply(style, to: ctx)
        ctx.addPath(smoothedPath(data.path.points, smoothing: data.smoothing))
        ctx.strokePath()
    }

    static func drawHighlight(_ data: HighlightData, style: Style, in ctx: CGContext) {
        guard style.stroke != nil, style.lineWidth > 0, !data.path.points.isEmpty else { return }
        StrokeStyle.apply(style, to: ctx)
        ctx.addPath(smoothedPath(data.path.points, smoothing: 1))
        ctx.strokePath()
    }
}
```

- [ ] **Step 4: Wire the shape kinds into the dispatcher**

In `PinxelKit/Sources/Rendering/AnnotationRenderer.swift`, replace the whole `drawContent` function with:

```swift
    private static func drawContent(_ annotation: Annotation, in ctx: CGContext, context: RenderContext) {
        let style = annotation.style
        switch annotation.kind {
        case .arrow(let data): ShapeRenderer.drawArrow(data, style: style, in: ctx)
        case .line(let data): ShapeRenderer.drawLine(data.line, style: style, in: ctx)
        case .shape(let data): ShapeRenderer.drawShape(data, style: style, in: ctx)
        case .pen(let data): ShapeRenderer.drawPen(data, style: style, in: ctx)
        case .highlight(let data): ShapeRenderer.drawHighlight(data, style: style, in: ctx)
        default: break
        }
    }
```

- [ ] **Step 5: Record and review snapshots**

Run: `swift test --filter ShapeRenderingTests`
Expected: `highlighterMultipliesWithBackground` and `degenerateAnnotationsDoNotCrash` PASS; `shapesSnapshot` and `stylesSnapshot` FAIL with "registrato".

Open `__Snapshots__/shapes.png`: three red/black arrows with triangle, open, circle and double heads; a black line; red outline rectangle; yellow rounded rectangle with black border; filled red ellipse; black zigzag pen stroke; a yellow highlighter band across the bottom.
Open `__Snapshots__/styles.png`: dashed red rectangle, dotted black rectangle, solid red rectangle rotated 30° clockwise, half-transparent yellow ellipse with a soft shadow down-right.
If anything is wrong, fix the code, delete the PNG and re-run.

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --filter ShapeRenderingTests`
Expected: PASS, 4 tests.

- [ ] **Step 7: Commit**

```bash
cd /Users/giovanni/work/reatool
git add PinxelKit
git commit -m "feat(rendering): draw arrows, lines, shapes, pen and highlighter"
```

---

### Task 8: Rendering text, callouts and steps

**Files:**
- Create: `PinxelKit/Sources/Rendering/TextRenderer.swift`
- Modify: `PinxelKit/Sources/Rendering/AnnotationRenderer.swift` (the `drawContent` switch)
- Test: `PinxelKit/Tests/RenderingTests/TextRenderingTests.swift`

**Interfaces:**
- Consumes: `RichText`, `TextRun`, `TextData`, `CalloutData`, `StepData`, `StrokeStyle`, `RenderContext.stepLabels`.
- Produces (internal): `TextRenderer.attributedString(_: RichText) -> NSAttributedString`, `TextRenderer.draw(_: RichText, in: CGRect, inset: CGFloat, ctx:)`, `drawText(_: TextData, style:in:)`, `calloutPath(_: CalloutData) -> CGPath`, `drawCallout(_: CalloutData, style:in:)`, `drawStep(_: StepData, label: String, style:in:)`.

- [ ] **Step 1: Write the failing tests**

`PinxelKit/Tests/RenderingTests/TextRenderingTests.swift`:

```swift
import CoreGraphics
import Foundation
import Testing
import DocumentModel
@testable import Rendering
import PinxelTestSupport

struct TextRenderingTests {
    let whiteBackground = TestImages.solid(width: 400, height: 300, red: 1, green: 1, blue: 1)

    func render(_ annotations: [Annotation]) throws -> CGImage {
        try DocumentRenderer().renderImage(TestDocuments.document(annotations: annotations), assets: assets(whiteBackground))
    }

    func nonWhitePixels(in image: CGImage, rect: CGRect) -> Int {
        let pixels = PixelBuffer(image)
        var count = 0
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) where pixels.pixel(x: x, y: y) != white {
                count += 1
            }
        }
        return count
    }

    @Test func textSnapshot() throws {
        let styled = RichText(runs: [
            TextRun(text: "Grassetto ", bold: true),
            TextRun(text: "corsivo ", italic: true),
            TextRun(text: "sottolineato ", underline: true),
            TextRun(text: "rosso", color: .accentRed),
        ], fontSize: 18)
        let noBox = Style(stroke: nil)
        let annotations: [Annotation] = [
            Annotation(kind: .text(TextData(rect: CGRect(x: 10, y: 10, width: 380, height: 30), text: styled)), style: noBox),
            Annotation(kind: .text(TextData(rect: CGRect(x: 10, y: 45, width: 380, height: 30), text: RichText("Centrato", fontSize: 18, alignment: .center))), style: noBox),
            Annotation(kind: .text(TextData(rect: CGRect(x: 10, y: 80, width: 380, height: 30), text: RichText("A destra", fontSize: 18, alignment: .right))), style: Style(stroke: .black, fill: .highlightYellow, lineWidth: 1)),
            Annotation(kind: .callout(CalloutData(rect: CGRect(x: 150, y: 130, width: 200, height: 60), text: RichText("Clicca qui per salvare", fontSize: 16), tail: CalloutTail(tip: CGPoint(x: 90, y: 230)))),
                       style: Style(stroke: .accentRed, fill: .white, lineWidth: 2)),
            Annotation(kind: .step(StepData(center: CGPoint(x: 40, y: 260), diameter: 36)), style: Style(stroke: nil, fill: .accentRed)),
            Annotation(kind: .step(StepData(center: CGPoint(x: 90, y: 260), diameter: 36)), style: Style(stroke: nil, fill: .accentRed)),
            Annotation(kind: .step(StepData(center: CGPoint(x: 140, y: 260), diameter: 36, label: StepLabel(sequence: .uppercaseLetters))), style: Style(stroke: .white, fill: .black, lineWidth: 2)),
        ]
        Snapshot.assertMatches(try render(annotations), named: "text", tolerance: 0.02)
    }

    @Test func unicodeTextRenders() throws {
        let rect = CGRect(x: 20, y: 20, width: 360, height: 60)
        let annotation = Annotation(kind: .text(TextData(rect: rect, text: RichText("👋🏽 مرحبا 日本語 Ciao", fontSize: 28))), style: Style(stroke: nil))
        #expect(nonWhitePixels(in: try render([annotation]), rect: rect) > 100)
    }

    @Test func emptyTextDrawsNothing() throws {
        let annotations = [
            Annotation(kind: .text(TextData(rect: CGRect(x: 20, y: 20, width: 100, height: 40), text: RichText(""))), style: Style(stroke: nil)),
            Annotation(kind: .text(TextData(rect: CGRect(x: 20, y: 80, width: 0, height: 0), text: RichText("x"))), style: Style(stroke: nil)),
        ]
        let image = try render(annotations)
        #expect(PixelBuffer(image).differingPixelFraction(from: PixelBuffer(whiteBackground), channelTolerance: 1) == 0)
    }

    @Test func stepUsesComputedLabel() throws {
        // Un solo step "1" e lo stesso con override "1": devono essere identici.
        let automatic = Annotation(kind: .step(StepData(center: CGPoint(x: 50, y: 50), diameter: 40)), style: Style(stroke: nil, fill: .accentRed))
        let manual = Annotation(kind: .step(StepData(center: CGPoint(x: 50, y: 50), diameter: 40, label: StepLabel(override: "1"))), style: Style(stroke: nil, fill: .accentRed))
        let a = PixelBuffer(try render([automatic]))
        let b = PixelBuffer(try render([manual]))
        #expect(a.differingPixelFraction(from: b, channelTolerance: 0) == 0)
        #expect(a.pixel(x: 50, y: 34) != white) // dentro il cerchio
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter TextRenderingTests`
Expected: `unicodeTextRenders` FAILS (0 non-white pixels), `textSnapshot` FAILS (recorded), `stepUsesComputedLabel` FAILS on the last expectation.

- [ ] **Step 3: Implement the text renderer**

`PinxelKit/Sources/Rendering/TextRenderer.swift`:

```swift
import CoreGraphics
import CoreText
import DocumentModel
import Foundation

enum TextRenderer {
    static func attributedString(_ text: RichText) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let paragraph = paragraphStyle(text.alignment)
        let base = CTFontCreateWithName(text.fontFamily as CFString, text.fontSize, nil)
        for run in text.runs where !run.text.isEmpty {
            var traits: CTFontSymbolicTraits = []
            if run.bold { traits.insert(.traitBold) }
            if run.italic { traits.insert(.traitItalic) }
            let font = traits.isEmpty ? base : (CTFontCreateCopyWithSymbolicTraits(base, text.fontSize, nil, traits, traits) ?? base)
            var attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): (run.color ?? text.color).cgColor,
                NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraph,
            ]
            if run.underline {
                attributes[NSAttributedString.Key(kCTUnderlineStyleAttributeName as String)] = NSNumber(value: CTUnderlineStyle.single.rawValue)
            }
            result.append(NSAttributedString(string: run.text, attributes: attributes))
        }
        return result
    }

    private static func paragraphStyle(_ alignment: RichTextAlignment) -> CTParagraphStyle {
        var value: CTTextAlignment = switch alignment {
        case .left: .left
        case .center: .center
        case .right: .right
        }
        return withUnsafeBytes(of: &value) { buffer in
            var setting = CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: buffer.baseAddress!)
            return CTParagraphStyleCreate(&setting, 1)
        }
    }

    /// Disegna il testo dall'alto verso il basso dentro `rect` (contesto capovolto del documento).
    static func draw(_ text: RichText, in rect: CGRect, inset: CGFloat, ctx: CGContext) {
        let frameRect = rect.standardized.insetBy(dx: inset, dy: inset)
        guard frameRect.width > 0, frameRect.height > 0 else { return }
        let string = attributedString(text)
        guard string.length > 0 else { return }
        let framesetter = CTFramesetterCreateWithAttributedString(string as CFAttributedString)
        let path = CGPath(rect: CGRect(origin: .zero, size: frameRect.size), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        ctx.saveGState()
        ctx.translateBy(x: frameRect.minX, y: frameRect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textMatrix = .identity
        CTFrameDraw(frame, ctx)
        ctx.restoreGState()
    }

    static func drawText(_ data: TextData, style: Style, in ctx: CGContext) {
        let rect = data.rect.standardized
        guard rect.width > 0, rect.height > 0 else { return }
        if let fill = style.fill {
            ctx.setFillColor(fill.cgColor)
            ctx.fill(rect)
        }
        if style.stroke != nil, style.lineWidth > 0 {
            StrokeStyle.apply(style, to: ctx)
            ctx.stroke(rect)
        }
        draw(data.text, in: rect, inset: 4, ctx: ctx)
    }

    static func calloutPath(_ data: CalloutData) -> CGPath {
        let rect = data.rect.standardized
        let radius = max(0, min(12, min(rect.width, rect.height) / 2))
        let bubble = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        let tip = data.tail.tip
        guard !rect.contains(tip) else { return bubble }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let dx = tip.x - center.x
        let dy = tip.y - center.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0, length.isFinite else { return bubble }
        let half = min(data.tail.baseWidth / 2, min(rect.width, rect.height) / 2)
        let px = -dy / length * half
        let py = dx / length * half
        let tail = CGMutablePath()
        tail.move(to: CGPoint(x: center.x + px, y: center.y + py))
        tail.addLine(to: tip)
        tail.addLine(to: CGPoint(x: center.x - px, y: center.y - py))
        tail.closeSubpath()
        return bubble.union(tail)
    }

    static func drawCallout(_ data: CalloutData, style: Style, in ctx: CGContext) {
        let rect = data.rect.standardized
        guard rect.width > 0, rect.height > 0 else { return }
        let path = calloutPath(data)
        ctx.setFillColor((style.fill ?? .white).cgColor)
        ctx.addPath(path)
        ctx.fillPath()
        if style.stroke != nil, style.lineWidth > 0 {
            StrokeStyle.apply(style, to: ctx)
            ctx.addPath(path)
            ctx.strokePath()
        }
        draw(data.text, in: rect, inset: 10, ctx: ctx)
    }

    static func drawStep(_ data: StepData, label: String, style: Style, in ctx: CGContext) {
        guard data.diameter > 0 else { return }
        let rect = CGRect(x: data.center.x - data.diameter / 2, y: data.center.y - data.diameter / 2, width: data.diameter, height: data.diameter)
        ctx.setFillColor((style.fill ?? .accentRed).cgColor)
        ctx.fillEllipse(in: rect)
        if style.stroke != nil, style.lineWidth > 0 {
            StrokeStyle.apply(style, to: ctx)
            ctx.strokeEllipse(in: rect.insetBy(dx: style.lineWidth / 2, dy: style.lineWidth / 2))
        }
        guard !label.isEmpty else { return }

        let fontSize = data.diameter * (label.count > 2 ? 0.38 : 0.5)
        let base = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let font = CTFontCreateCopyWithSymbolicTraits(base, fontSize, nil, .traitBold, .traitBold) ?? base
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): RGBA.white.cgColor,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: label, attributes: attributes) as CFAttributedString)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)

        ctx.saveGState()
        ctx.translateBy(x: data.center.x, y: data.center.y)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: -width / 2, y: -(ascent - descent) / 2)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}
```

- [ ] **Step 4: Wire text kinds into the dispatcher**

In `PinxelKit/Sources/Rendering/AnnotationRenderer.swift`, replace the whole `drawContent` function with:

```swift
    private static func drawContent(_ annotation: Annotation, in ctx: CGContext, context: RenderContext) {
        let style = annotation.style
        switch annotation.kind {
        case .arrow(let data): ShapeRenderer.drawArrow(data, style: style, in: ctx)
        case .line(let data): ShapeRenderer.drawLine(data.line, style: style, in: ctx)
        case .shape(let data): ShapeRenderer.drawShape(data, style: style, in: ctx)
        case .pen(let data): ShapeRenderer.drawPen(data, style: style, in: ctx)
        case .highlight(let data): ShapeRenderer.drawHighlight(data, style: style, in: ctx)
        case .text(let data): TextRenderer.drawText(data, style: style, in: ctx)
        case .callout(let data): TextRenderer.drawCallout(data, style: style, in: ctx)
        case .step(let data): TextRenderer.drawStep(data, label: context.stepLabels[annotation.id] ?? "?", style: style, in: ctx)
        default: break
        }
    }
```

- [ ] **Step 5: Record and review the snapshot**

Run: `swift test --filter TextRenderingTests`
Expected: 3 PASS, `textSnapshot` FAILS with "registrato".

Open `__Snapshots__/text.png`: first line with bold/italic/underlined/red words; "Centrato" centred; "A destra" right-aligned in a yellow box with thin black border; a white speech bubble with red border whose tail points down-left; two red circles "1" and "2" and a black circle "A" with white outline, labels centred. Fix and re-record if needed.

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --filter TextRenderingTests`
Expected: PASS, 4 tests.

- [ ] **Step 7: Commit**

```bash
cd /Users/giovanni/work/reatool
git add PinxelKit
git commit -m "feat(rendering): draw rich text, callouts and numbered steps"
```

---

### Task 9: Rendering blur, pixelate, magnifier, placed images and canvas style

**Files:**
- Create: `PinxelKit/Sources/Rendering/EffectRenderer.swift`
- Modify: `PinxelKit/Sources/Rendering/AnnotationRenderer.swift` (final exhaustive `drawContent` switch)
- Test: `PinxelKit/Tests/RenderingTests/EffectRenderingTests.swift`

**Interfaces:**
- Consumes: `RenderContext` (background, effects, assets), `ShapeRenderer.shapePath(_:in:)`, `StrokeStyle`, `ImageDrawing`.
- Produces (internal): `EffectRenderer.drawBlur(_: BlurData, context:in:)`, `drawPixelate(_: PixelateData, context:in:)`, `drawMagnifier(_: MagnifierData, style:context:in:)`, `drawPlacedImage(_: PlacedImageData, context:in:)`, `region(_: CGRect, in: CGImage) -> PixelRect?`. Blur/pixelate always sample the processed background without annotations; in exported rasters the effect is baked into pixels.

- [ ] **Step 1: Write the failing tests**

`PinxelKit/Tests/RenderingTests/EffectRenderingTests.swift`:

```swift
import CoreGraphics
import Foundation
import Testing
import DocumentModel
@testable import Rendering
import PinxelTestSupport

struct EffectRenderingTests {
    func render(_ annotations: [Annotation], background: CGImage = TestImages.quadrants(), canvasStyle: CanvasStyle = CanvasStyle()) throws -> CGImage {
        var document = TestDocuments.document(annotations: annotations, size: PixelSize(width: background.width, height: background.height))
        document.canvasStyle = canvasStyle
        return try DocumentRenderer().renderImage(document, assets: assets(background))
    }

    func redVariance(_ pixels: PixelBuffer, rect: CGRect) -> Double {
        var values: [Double] = []
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) { values.append(Double(pixels.pixel(x: x, y: y).r)) }
        }
        let mean = values.reduce(0, +) / Double(values.count)
        return values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
    }

    @Test func blurRemovesDetail() throws {
        let noise = TestImages.noise(width: 200, height: 200)
        let rect = CGRect(x: 50, y: 50, width: 100, height: 100)
        let inner = rect.insetBy(dx: 10, dy: 10)
        let before = redVariance(PixelBuffer(noise), rect: inner)
        let after = redVariance(PixelBuffer(try render([Annotation(kind: .blur(BlurData(rect: rect, radius: 8)))], background: noise)), rect: inner)
        #expect(after < before * 0.2, "variance \(before) → \(after)")
    }

    @Test func pixelateMakesUniformBlocks() throws {
        let noise = TestImages.noise(width: 200, height: 200)
        let pixels = PixelBuffer(try render([Annotation(kind: .pixelate(PixelateData(rect: CGRect(x: 100, y: 100, width: 40, height: 40), blockSize: 10)))], background: noise))
        #expect(pixels.pixel(x: 101, y: 101) == pixels.pixel(x: 108, y: 108))
        #expect(pixels.pixel(x: 121, y: 131) == pixels.pixel(x: 128, y: 138))
        #expect(pixels.pixel(x: 101, y: 101) != pixels.pixel(x: 131, y: 131))
    }

    @Test func magnifierCopiesSourceIntoTarget() throws {
        let magnifier = Annotation(kind: .magnifier(MagnifierData(
            source: CGRect(x: 50, y: 50, width: 10, height: 10),
            target: CGRect(x: 40, y: 200, width: 60, height: 60),
            shape: .rectangle, showsConnector: false)), style: Style(stroke: nil))
        let pixels = PixelBuffer(try render([magnifier]))
        #expect(pixels.pixel(x: 70, y: 230) == red)    // il bersaglio sta nel quadrante blu ma mostra il rosso
        #expect(pixels.pixel(x: 20, y: 230) == blue)
    }

    @Test func magnifierWithSourceOutsideImageDrawsNothing() throws {
        let magnifier = Annotation(kind: .magnifier(MagnifierData(
            source: CGRect(x: -100, y: -100, width: 20, height: 20),
            target: CGRect(x: 40, y: 200, width: 60, height: 60))))
        let image = try render([magnifier])
        #expect(PixelBuffer(image).differingPixelFraction(from: PixelBuffer(TestImages.quadrants()), channelTolerance: 1) == 0)
    }

    @Test func placedImageAndMissingPlaceholder() throws {
        let present = Annotation(kind: .image(PlacedImageData(rect: CGRect(x: 20, y: 20, width: 40, height: 40), asset: TestDocuments.placedImage)))
        let missing = Annotation(kind: .image(PlacedImageData(rect: CGRect(x: 100, y: 20, width: 40, height: 40), asset: ImageAssetRef(name: "assets/missing.png"))))
        let pixels = PixelBuffer(try render([present, missing]))
        #expect(pixels.pixel(x: 40, y: 40) == RGBA8(r: 0, g: 153, b: 255))
        let placeholder = pixels.pixel(x: 103, y: 40)
        #expect(placeholder.r == placeholder.g && placeholder.g == placeholder.b && placeholder.r > 200, "got \(placeholder)")
    }

    @Test func canvasStyleSnapshot() throws {
        let style = CanvasStyle(padding: 30, backgroundColor: RGBA(red: 0.93, green: 0.94, blue: 0.96), border: Border(color: .black, width: 4), shadow: Shadow(offset: CGSize(width: 0, height: 8), blur: 16, color: RGBA(red: 0, green: 0, blue: 0, alpha: 0.5)))
        Snapshot.assertMatches(try render([], canvasStyle: style), named: "canvas-style")
    }

    @Test func allKindsSnapshot() throws {
        Snapshot.assertMatches(try render(TestDocuments.allKindsAnnotations()), named: "all-kinds", tolerance: 0.02)
    }

    @Test func largeCanvasRenders() throws {
        let background = TestImages.solid(width: 6000, height: 4000, red: 0.2, green: 0.4, blue: 0.6)
        let annotations = [
            Annotation(kind: .blur(BlurData(rect: CGRect(x: 1000, y: 1000, width: 800, height: 600), radius: 20))),
            Annotation(kind: .arrow(ArrowData(line: LineGeometry(start: CGPoint(x: 100, y: 100), end: CGPoint(x: 5900, y: 3900))))),
        ]
        let image = try render(annotations, background: background)
        #expect(image.width == 6000 && image.height == 4000)
    }

    @Test func renderingIsDeterministicWithCache() throws {
        let renderer = DocumentRenderer()
        let document = TestDocuments.document()
        let provider = assets()
        let first = PixelBuffer(try renderer.renderImage(document, assets: provider))
        let second = PixelBuffer(try renderer.renderImage(document, assets: provider))
        #expect(first == second)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter EffectRenderingTests`
Expected: `blurRemovesDetail`, `pixelateMakesUniformBlocks`, `magnifierCopiesSourceIntoTarget`, `placedImageAndMissingPlaceholder` FAIL; snapshots FAIL (recorded).

- [ ] **Step 3: Implement the effect renderer**

`PinxelKit/Sources/Rendering/EffectRenderer.swift`:

```swift
import CoreGraphics
import CoreImage
import DocumentModel

enum EffectRenderer {
    nonisolated(unsafe) static let ciContext = CIContext(options: [
        .workingColorSpace: ImageDrawing.sRGB,
        .outputColorSpace: ImageDrawing.sRGB,
        .cacheIntermediates: false,
    ])

    /// Regione intera di `rect` dentro lo sfondo, o `nil` se vuota.
    static func region(_ rect: CGRect, in background: CGImage) -> PixelRect? {
        let r = rect.standardized.integral
        guard r.minX.isFinite, r.minY.isFinite, r.width.isFinite, r.height.isFinite else { return nil }
        let pixel = PixelRect(
            x: ImageDrawing.clampedInt(r.minX), y: ImageDrawing.clampedInt(r.minY),
            width: ImageDrawing.clampedInt(r.width), height: ImageDrawing.clampedInt(r.height)
        ).clamped(to: PixelSize(width: background.width, height: background.height))
        return pixel.width > 0 && pixel.height > 0 ? pixel : nil
    }

    static func drawBlur(_ data: BlurData, context: RenderContext, in ctx: CGContext) {
        guard data.radius > 0, let region = region(data.rect, in: context.background) else { return }
        let key = "blur|\(region)|\(data.radius)"
        guard let image = context.effects.image(for: key, make: { blurred(context.background, region: region, radius: data.radius) }) else { return }
        ImageDrawing.draw(image, in: region.cgRect, context: ctx)
    }

    static func drawPixelate(_ data: PixelateData, context: RenderContext, in ctx: CGContext) {
        guard let region = region(data.rect, in: context.background) else { return }
        let key = "pixelate|\(region)|\(data.blockSize)"
        guard let image = context.effects.image(for: key, make: { pixelated(context.background, region: region, blockSize: data.blockSize) }) else { return }
        ImageDrawing.draw(image, in: region.cgRect, context: ctx)
    }

    private static func blurred(_ background: CGImage, region: PixelRect, radius: Double) -> CGImage? {
        guard let crop = background.cropping(to: region.cgRect) else { return nil }
        let input = CIImage(cgImage: crop)
        let output = input.clampedToExtent().applyingGaussianBlur(sigma: radius).cropped(to: input.extent)
        return ciContext.createCGImage(output, from: input.extent)
    }

    private static func pixelated(_ background: CGImage, region: PixelRect, blockSize: Double) -> CGImage? {
        guard let crop = background.cropping(to: region.cgRect),
              let filter = CIFilter(name: "CIPixellate") else { return nil }
        let input = CIImage(cgImage: crop)
        filter.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(max(blockSize, 1), forKey: kCIInputScaleKey)
        filter.setValue(CIVector(x: 0, y: 0), forKey: kCIInputCenterKey)
        guard let output = filter.outputImage?.cropped(to: input.extent) else { return nil }
        return ciContext.createCGImage(output, from: input.extent)
    }

    static func drawMagnifier(_ data: MagnifierData, style: Style, context: RenderContext, in ctx: CGContext) {
        let target = data.target.standardized
        guard target.width > 0, target.height > 0,
              let region = region(data.source, in: context.background),
              let crop = context.background.cropping(to: region.cgRect) else { return }
        let source = data.source.standardized
        let stroked = style.stroke != nil && style.lineWidth > 0

        if data.showsConnector, stroked {
            StrokeStyle.apply(style, to: ctx)
            ctx.move(to: CGPoint(x: source.midX, y: source.midY))
            ctx.addLine(to: CGPoint(x: target.midX, y: target.midY))
            ctx.strokePath()
            ctx.addPath(ShapeRenderer.shapePath(data.shape, in: source))
            ctx.strokePath()
        }

        let path = ShapeRenderer.shapePath(data.shape, in: target)
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.setFillColor(RGBA.white.cgColor)
        ctx.fill(target)
        ctx.interpolationQuality = .none
        ImageDrawing.draw(crop, in: target, context: ctx)
        ctx.restoreGState()

        if stroked {
            StrokeStyle.apply(style, to: ctx)
            ctx.setLineDash(phase: 0, lengths: [])
            ctx.addPath(path)
            ctx.strokePath()
        }
    }

    static func drawPlacedImage(_ data: PlacedImageData, context: RenderContext, in ctx: CGContext) {
        let rect = data.rect.standardized
        guard rect.width > 0, rect.height > 0 else { return }
        if let image = context.assets.image(for: data.asset) {
            ImageDrawing.draw(image, in: rect, context: ctx)
            return
        }
        // Segnaposto per immagine mancante: grigio con una X.
        ctx.setFillColor(CGColor(gray: 0.85, alpha: 1))
        ctx.fill(rect)
        ctx.setStrokeColor(CGColor(gray: 0.5, alpha: 1))
        ctx.setLineWidth(2)
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.move(to: CGPoint(x: rect.minX, y: rect.minY))
        ctx.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        ctx.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        ctx.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        ctx.strokePath()
    }
}
```

- [ ] **Step 4: Make the dispatcher exhaustive**

In `PinxelKit/Sources/Rendering/AnnotationRenderer.swift`, replace the whole `drawContent` function with:

```swift
    private static func drawContent(_ annotation: Annotation, in ctx: CGContext, context: RenderContext) {
        let style = annotation.style
        switch annotation.kind {
        case .arrow(let data): ShapeRenderer.drawArrow(data, style: style, in: ctx)
        case .line(let data): ShapeRenderer.drawLine(data.line, style: style, in: ctx)
        case .shape(let data): ShapeRenderer.drawShape(data, style: style, in: ctx)
        case .pen(let data): ShapeRenderer.drawPen(data, style: style, in: ctx)
        case .highlight(let data): ShapeRenderer.drawHighlight(data, style: style, in: ctx)
        case .text(let data): TextRenderer.drawText(data, style: style, in: ctx)
        case .callout(let data): TextRenderer.drawCallout(data, style: style, in: ctx)
        case .step(let data): TextRenderer.drawStep(data, label: context.stepLabels[annotation.id] ?? "?", style: style, in: ctx)
        case .blur(let data): EffectRenderer.drawBlur(data, context: context, in: ctx)
        case .pixelate(let data): EffectRenderer.drawPixelate(data, context: context, in: ctx)
        case .magnifier(let data): EffectRenderer.drawMagnifier(data, style: style, context: context, in: ctx)
        case .image(let data): EffectRenderer.drawPlacedImage(data, context: context, in: ctx)
        case .unknown: break
        }
    }
```

- [ ] **Step 5: Record and review snapshots**

Run: `swift test --filter EffectRenderingTests`
Expected: all behavioural tests PASS; `canvasStyleSnapshot` and `allKindsSnapshot` FAIL with "registrato".

Open `__Snapshots__/canvas-style.png`: 460×360, light grey margin, the four quadrants framed by a 4 px black border, a soft shadow below the image.
Open `__Snapshots__/all-kinds.png`: every annotation of `TestDocuments.allKindsAnnotations()` over the quadrants — arrow, dashed line, rounded rect, yellow ellipse, "Ciao Pinxel", red-bordered callout pointing down-left, steps "1" and "2", translucent highlighter, smooth pen stroke, blurred patch and pixelated patch at the quadrant border, circular magnifier with connector, small blue placed image bottom-right.
Fix and re-record if anything is wrong.

- [ ] **Step 6: Run the whole suite**

Run: `swift test`
Expected: PASS, all tests in DocumentModelTests and RenderingTests.

- [ ] **Step 7: Commit**

```bash
cd /Users/giovanni/work/reatool
git add PinxelKit
git commit -m "feat(rendering): add blur, pixelate, magnifier, placed images and canvas style"
```

---

### Task 10: Minimal ZIP reader/writer with safety limits

**Files:**
- Modify: `PinxelKit/Package.swift`
- Create: `PinxelKit/Sources/Persistence/CRC32.swift`
- Create: `PinxelKit/Sources/Persistence/Deflate.swift`
- Create: `PinxelKit/Sources/Persistence/ByteReader.swift`
- Create: `PinxelKit/Sources/Persistence/Zip.swift`
- Test: `PinxelKit/Tests/PersistenceTests/ZipTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `enum ZipError: Error, Equatable { corrupt(String), unsafeEntryName(String), tooManyEntries(Int), entryTooLarge(String), archiveTooLarge, unsupportedMethod(UInt16), encrypted, checksumMismatch(String), missingEntry(String) }`
  - `struct ZipLimits { var maxEntries: Int = 1000; var maxTotalUncompressedSize: Int = 2 GiB; static let default }`
  - `struct ZipWriter { enum Method { store, deflate }; init(); mutating func add(name: String, data: Data, method: Method) throws; mutating func finish() throws -> Data }` (deflate falls back to store when it does not shrink the data)
  - `struct ZipEntry { let name: String; let uncompressedSize: Int }`
  - `struct ZipReader { let entries: [ZipEntry]; init(_ data: Data, limits: ZipLimits = .default) throws; func data(for name: String) throws -> Data; func data(for entry: ZipEntry) throws -> Data }`
  - Internal: `CRC32.checksum(_:)`, `Deflate.compress(_:)`, `Deflate.decompress(_:limit:)`, `ByteReader`.

- [ ] **Step 1: Add the Persistence targets**

Replace `PinxelKit/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PinxelKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "DocumentModel", targets: ["DocumentModel"]),
        .library(name: "Rendering", targets: ["Rendering"]),
        .library(name: "Persistence", targets: ["Persistence"]),
    ],
    targets: [
        .target(name: "DocumentModel"),
        .target(name: "Rendering", dependencies: ["DocumentModel"]),
        .target(name: "Persistence", dependencies: ["DocumentModel", "Rendering"]),
        .target(
            name: "PinxelTestSupport",
            dependencies: ["DocumentModel"],
            path: "Tests/PinxelTestSupport"
        ),
        .testTarget(
            name: "DocumentModelTests",
            dependencies: ["DocumentModel", "PinxelTestSupport"]
        ),
        .testTarget(
            name: "RenderingTests",
            dependencies: ["Rendering", "PinxelTestSupport"],
            exclude: ["__Snapshots__"]
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: ["Persistence", "PinxelTestSupport"]
        ),
    ]
)
```

- [ ] **Step 2: Write the failing tests**

`PinxelKit/Tests/PersistenceTests/ZipTests.swift`:

```swift
import Foundation
import Testing
@testable import Persistence

struct ZipTests {
    func archive(_ entries: [(String, Data, ZipWriter.Method)]) throws -> Data {
        var writer = ZipWriter()
        for (name, data, method) in entries { try writer.add(name: name, data: data, method: method) }
        return try writer.finish()
    }

    /// Offset della prima voce del central directory (firma PK\u{1}\u{2}).
    func centralDirectoryOffset(in data: Data) -> Int {
        let bytes = [UInt8](data)
        for i in 0..<(bytes.count - 4) where bytes[i] == 0x50 && bytes[i + 1] == 0x4B && bytes[i + 2] == 0x01 && bytes[i + 3] == 0x02 {
            return i
        }
        return -1
    }

    @Test func crc32KnownValue() {
        #expect(CRC32.checksum(Data("123456789".utf8)) == 0xCBF43926)
        #expect(CRC32.checksum(Data()) == 0)
    }

    @Test func roundTripStoreAndDeflate() throws {
        let text = Data(String(repeating: "pinxel ", count: 2000).utf8)
        let binary = Data((0..<1000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        let zip = try archive([("doc.json", text, .deflate), ("image.png", binary, .store), ("empty.txt", Data(), .deflate), ("àèì/ü.txt", Data("ok".utf8), .store)])
        #expect(zip.count < text.count) // il JSON ripetitivo è stato compresso
        let reader = try ZipReader(zip)
        #expect(reader.entries.map(\.name) == ["doc.json", "image.png", "empty.txt", "àèì/ü.txt"])
        #expect(try reader.data(for: "doc.json") == text)
        #expect(try reader.data(for: "image.png") == binary)
        #expect(try reader.data(for: "empty.txt") == Data())
        #expect(try reader.data(for: "àèì/ü.txt") == Data("ok".utf8))
    }

    @Test func zipIsReadableBySystemUnzip() throws {
        let zip = try archive([("hello.txt", Data(String(repeating: "ciao ", count: 100).utf8), .deflate)])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pinxel-\(UUID().uuidString).zip")
        try zip.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-tq", url.path]
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    @Test func missingEntry() throws {
        let reader = try ZipReader(archive([("a.txt", Data("a".utf8), .store)]))
        #expect(throws: ZipError.missingEntry("b.txt")) { try reader.data(for: "b.txt") }
    }

    @Test func rejectsPathTraversal() throws {
        for name in ["../evil.txt", "/etc/passwd", "a\\b.txt", "assets/../../x", "a//b", "./x"] {
            let zip = try archive([(name, Data("x".utf8), .store)])
            #expect(throws: ZipError.unsafeEntryName(name)) { try ZipReader(zip) }
        }
    }

    @Test func rejectsTooManyEntries() throws {
        let zip = try archive((0..<4).map { ("f\($0).txt", Data("x".utf8), ZipWriter.Method.store) })
        #expect(throws: ZipError.tooManyEntries(4)) { try ZipReader(zip, limits: ZipLimits(maxEntries: 3)) }
    }

    @Test func rejectsTotalSizeOverLimit() throws {
        let zip = try archive([("big.bin", Data(count: 5000), .deflate)])
        #expect(throws: ZipError.entryTooLarge("big.bin")) {
            try ZipReader(zip, limits: ZipLimits(maxTotalUncompressedSize: 1000))
        }
    }

    @Test func rejectsTruncatedAndGarbage() throws {
        let zip = try archive([("a.txt", Data("hello".utf8), .store)])
        #expect(throws: ZipError.self) { try ZipReader(zip.prefix(zip.count - 10)) }
        #expect(throws: ZipError.self) { try ZipReader(Data((0..<500).map { UInt8(truncatingIfNeeded: $0 * 7) })) }
        #expect(throws: ZipError.self) { try ZipReader(Data()) }
    }

    @Test func detectsChecksumMismatch() throws {
        var zip = try archive([("a.txt", Data("hello world".utf8), .store)])
        // Il contenuto memorizzato inizia dopo l'header locale (30 byte) e il nome (5 byte).
        zip[zip.startIndex + 35] ^= 0xFF
        let reader = try ZipReader(zip)
        #expect(throws: ZipError.checksumMismatch("a.txt")) { try reader.data(for: "a.txt") }
    }

    @Test func zipBombWithLyingSizeIsStopped() throws {
        var zip = try archive([("bomb.bin", Data(count: 1_000_000), .deflate)])
        // Il central directory dichiara 10 byte decompressi invece di 1 MB.
        let cd = centralDirectoryOffset(in: zip)
        #expect(cd > 0)
        for (i, byte) in [UInt8(10), 0, 0, 0].enumerated() { zip[zip.startIndex + cd + 24 + i] = byte }
        let reader = try ZipReader(zip)
        #expect(throws: ZipError.self) { try reader.data(for: "bomb.bin") }
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter ZipTests`
Expected: build FAILS with `cannot find 'ZipWriter' in scope`.

- [ ] **Step 4: Implement CRC32, Deflate and ByteReader**

`PinxelKit/Sources/Persistence/CRC32.swift`:

```swift
import Foundation

enum CRC32 {
    static let table: [UInt32] = (0..<256).map { index in
        var c = UInt32(index)
        for _ in 0..<8 {
            c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1
        }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        table.withUnsafeBufferPointer { table in
            data.withUnsafeBytes { buffer in
                for byte in buffer {
                    crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
                }
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}
```

`PinxelKit/Sources/Persistence/Deflate.swift`:

```swift
import Compression
import Foundation

/// DEFLATE grezzo (RFC 1951), il metodo 8 dello ZIP. In Compression si chiama `.zlib`.
enum Deflate {
    static func compress(_ data: Data) throws -> Data {
        var output = Data()
        let filter = try OutputFilter(.compress, using: .zlib) { chunk in
            if let chunk { output.append(chunk) }
        }
        try filter.write(data)
        try filter.finalize()
        return output
    }

    /// Si ferma appena l'output supera `limit` byte (protezione da zip bomb).
    static func decompress(_ data: Data, limit: Int) throws -> Data {
        var output = Data()
        output.reserveCapacity(min(limit, 64 * 1024 * 1024))
        var exceeded = false
        let filter = try OutputFilter(.decompress, using: .zlib) { chunk in
            guard let chunk, !exceeded else { return }
            if output.count + chunk.count > limit {
                exceeded = true
                return
            }
            output.append(chunk)
        }
        try filter.write(data)
        try filter.finalize()
        if exceeded { throw ZipError.entryTooLarge("decompressed data exceeds the declared size") }
        return output
    }
}
```

`PinxelKit/Sources/Persistence/ByteReader.swift`:

```swift
import Foundation

/// Letture little-endian con controllo dei limiti; offset relativi all'inizio dei dati.
struct ByteReader {
    let data: Data

    init(_ data: Data) {
        self.data = data
    }

    var count: Int { data.count }

    private func check(_ offset: Int, _ length: Int) throws {
        guard offset >= 0, length >= 0, offset <= data.count - length else {
            throw ZipError.corrupt("read out of bounds at \(offset)")
        }
    }

    func uint16(at offset: Int) throws -> UInt16 {
        try check(offset, 2)
        let i = data.startIndex + offset
        return UInt16(data[i]) | UInt16(data[i + 1]) << 8
    }

    func uint32(at offset: Int) throws -> UInt32 {
        try check(offset, 4)
        let i = data.startIndex + offset
        return UInt32(data[i]) | UInt32(data[i + 1]) << 8 | UInt32(data[i + 2]) << 16 | UInt32(data[i + 3]) << 24
    }

    func bytes(at offset: Int, count length: Int) throws -> Data {
        try check(offset, length)
        let start = data.startIndex + offset
        return data.subdata(in: start..<(start + length))
    }
}
```

- [ ] **Step 5: Implement the ZIP writer and reader**

`PinxelKit/Sources/Persistence/Zip.swift`:

```swift
import Foundation

public enum ZipError: Error, Equatable {
    case corrupt(String)
    case unsafeEntryName(String)
    case tooManyEntries(Int)
    case entryTooLarge(String)
    case archiveTooLarge
    case unsupportedMethod(UInt16)
    case encrypted
    case checksumMismatch(String)
    case missingEntry(String)
}

public struct ZipLimits: Sendable {
    public var maxEntries: Int
    public var maxTotalUncompressedSize: Int

    public init(maxEntries: Int = 1000, maxTotalUncompressedSize: Int = 2 * 1024 * 1024 * 1024) {
        self.maxEntries = maxEntries
        self.maxTotalUncompressedSize = maxTotalUncompressedSize
    }

    public static let `default` = ZipLimits()
}

private enum Signature {
    static let localHeader: UInt32 = 0x0403_4B50
    static let centralHeader: UInt32 = 0x0201_4B50
    static let endOfCentralDirectory: UInt32 = 0x0605_4B50
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8(value >> 8))
    }

    mutating func appendUInt32(_ value: UInt32) {
        for shift in stride(from: 0, to: 32, by: 8) { append(UInt8((value >> UInt32(shift)) & 0xFF)) }
    }
}

/// Scrittore ZIP minimale (niente ZIP64, niente cifratura). Nomi in UTF-8.
public struct ZipWriter {
    public enum Method: UInt16 {
        case store = 0
        case deflate = 8
    }

    private var output = Data()
    private var central = Data()
    private var count = 0

    public init() {}

    public mutating func add(name: String, data: Data, method: Method) throws {
        let nameBytes = Data(name.utf8)
        let crc = CRC32.checksum(data)
        var payload = data
        var actualMethod = Method.store
        if method == .deflate, let compressed = try? Deflate.compress(data), compressed.count < data.count {
            payload = compressed
            actualMethod = .deflate
        }
        guard data.count < Int(UInt32.max), payload.count < Int(UInt32.max), output.count < Int(UInt32.max),
              nameBytes.count < Int(UInt16.max) else { throw ZipError.archiveTooLarge }
        let offset = UInt32(output.count)
        let dosDate: UInt16 = 0x21 // 1 gennaio 1980

        output.appendUInt32(Signature.localHeader)
        output.appendUInt16(20)            // versione necessaria
        output.appendUInt16(0x0800)        // flag: nomi UTF-8
        output.appendUInt16(actualMethod.rawValue)
        output.appendUInt16(0)             // ora
        output.appendUInt16(dosDate)
        output.appendUInt32(crc)
        output.appendUInt32(UInt32(payload.count))
        output.appendUInt32(UInt32(data.count))
        output.appendUInt16(UInt16(nameBytes.count))
        output.appendUInt16(0)             // extra
        output.append(nameBytes)
        output.append(payload)

        central.appendUInt32(Signature.centralHeader)
        central.appendUInt16(20)           // versione creatrice
        central.appendUInt16(20)           // versione necessaria
        central.appendUInt16(0x0800)
        central.appendUInt16(actualMethod.rawValue)
        central.appendUInt16(0)
        central.appendUInt16(dosDate)
        central.appendUInt32(crc)
        central.appendUInt32(UInt32(payload.count))
        central.appendUInt32(UInt32(data.count))
        central.appendUInt16(UInt16(nameBytes.count))
        central.appendUInt16(0)            // extra
        central.appendUInt16(0)            // commento
        central.appendUInt16(0)            // disco
        central.appendUInt16(0)            // attributi interni
        central.appendUInt32(0)            // attributi esterni
        central.appendUInt32(offset)
        central.append(nameBytes)
        count += 1
    }

    public mutating func finish() throws -> Data {
        guard count < Int(UInt16.max) else { throw ZipError.tooManyEntries(count) }
        guard output.count + central.count < Int(UInt32.max) else { throw ZipError.archiveTooLarge }
        var result = output
        let centralOffset = UInt32(result.count)
        result.append(central)
        result.appendUInt32(Signature.endOfCentralDirectory)
        result.appendUInt16(0)
        result.appendUInt16(0)
        result.appendUInt16(UInt16(count))
        result.appendUInt16(UInt16(count))
        result.appendUInt32(UInt32(central.count))
        result.appendUInt32(centralOffset)
        result.appendUInt16(0)
        return result
    }
}

public struct ZipEntry: Equatable, Sendable {
    public let name: String
    public let uncompressedSize: Int
    let method: UInt16
    let crc: UInt32
    let compressedSize: Int
    let localHeaderOffset: Int
}

/// Lettore ZIP difensivo: valida nomi, numero di voci, dimensioni dichiarate e checksum.
public struct ZipReader {
    public let entries: [ZipEntry]
    private let reader: ByteReader

    public init(_ data: Data, limits: ZipLimits = .default) throws {
        let reader = ByteReader(data)
        self.reader = reader
        let end = try Self.findEndOfCentralDirectory(reader)
        let total = Int(try reader.uint16(at: end + 10))
        let centralSize = Int(try reader.uint32(at: end + 12))
        let centralOffset = Int(try reader.uint32(at: end + 16))
        guard total <= limits.maxEntries else { throw ZipError.tooManyEntries(total) }
        guard centralOffset + centralSize <= end else { throw ZipError.corrupt("central directory out of bounds") }

        var entries: [ZipEntry] = []
        var names = Set<String>()
        var totalSize = 0
        var offset = centralOffset
        for _ in 0..<total {
            guard try reader.uint32(at: offset) == Signature.centralHeader else {
                throw ZipError.corrupt("bad central directory entry at \(offset)")
            }
            let flags = try reader.uint16(at: offset + 8)
            let method = try reader.uint16(at: offset + 10)
            let crc = try reader.uint32(at: offset + 16)
            let compressedSize = Int(try reader.uint32(at: offset + 20))
            let uncompressedSize = Int(try reader.uint32(at: offset + 24))
            let nameLength = Int(try reader.uint16(at: offset + 28))
            let extraLength = Int(try reader.uint16(at: offset + 30))
            let commentLength = Int(try reader.uint16(at: offset + 32))
            let localHeaderOffset = Int(try reader.uint32(at: offset + 42))
            guard let name = String(data: try reader.bytes(at: offset + 46, count: nameLength), encoding: .utf8) else {
                throw ZipError.unsafeEntryName("<non-UTF-8>")
            }
            if flags & 0x1 != 0 { throw ZipError.encrypted }
            guard method == 0 || method == 8 else { throw ZipError.unsupportedMethod(method) }
            try Self.validate(name: name)
            guard names.insert(name).inserted else { throw ZipError.corrupt("duplicate entry \(name)") }
            totalSize += uncompressedSize
            guard totalSize <= limits.maxTotalUncompressedSize else { throw ZipError.entryTooLarge(name) }
            entries.append(ZipEntry(
                name: name, uncompressedSize: uncompressedSize, method: method, crc: crc,
                compressedSize: compressedSize, localHeaderOffset: localHeaderOffset
            ))
            offset += 46 + nameLength + extraLength + commentLength
        }
        self.entries = entries
    }

    public func data(for name: String) throws -> Data {
        guard let entry = entries.first(where: { $0.name == name }) else { throw ZipError.missingEntry(name) }
        return try data(for: entry)
    }

    public func data(for entry: ZipEntry) throws -> Data {
        let offset = entry.localHeaderOffset
        guard try reader.uint32(at: offset) == Signature.localHeader else {
            throw ZipError.corrupt("bad local header for \(entry.name)")
        }
        let nameLength = Int(try reader.uint16(at: offset + 26))
        let extraLength = Int(try reader.uint16(at: offset + 28))
        let payload = try reader.bytes(at: offset + 30 + nameLength + extraLength, count: entry.compressedSize)
        let result: Data
        if entry.method == 0 {
            result = payload
        } else {
            do {
                result = try Deflate.decompress(payload, limit: entry.uncompressedSize)
            } catch let error as ZipError {
                throw error
            } catch {
                throw ZipError.corrupt("invalid deflate data in \(entry.name)")
            }
        }
        guard result.count == entry.uncompressedSize else { throw ZipError.corrupt("size mismatch for \(entry.name)") }
        guard CRC32.checksum(result) == entry.crc else { throw ZipError.checksumMismatch(entry.name) }
        return result
    }

    static func validate(name: String) throws {
        let components = name.split(separator: "/", omittingEmptySubsequences: false)
        if name.isEmpty || name.hasPrefix("/") || name.contains("\\") || name.contains("\0")
            || components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) {
            throw ZipError.unsafeEntryName(name)
        }
    }

    private static func findEndOfCentralDirectory(_ reader: ByteReader) throws -> Int {
        let minimumSize = 22
        guard reader.count >= minimumSize else { throw ZipError.corrupt("file too small") }
        let lowest = max(0, reader.count - minimumSize - 65_535)
        var offset = reader.count - minimumSize
        while offset >= lowest {
            if try reader.uint32(at: offset) == Signature.endOfCentralDirectory { return offset }
            offset -= 1
        }
        throw ZipError.corrupt("end of central directory not found")
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --filter ZipTests`
Expected: PASS, 10 tests.

- [ ] **Step 7: Commit**

```bash
cd /Users/giovanni/work/reatool
git add PinxelKit
git commit -m "feat(persistence): add defensive ZIP reader and writer"
```

---

### Task 11: The `.pinxel` archive, image codecs and thumbnails

**Files:**
- Create: `PinxelKit/Sources/Persistence/ImageCodec.swift`
- Create: `PinxelKit/Sources/Persistence/PinxelArchive.swift`
- Create: `PinxelKit/Sources/Persistence/Thumbnailer.swift`
- Test: `PinxelKit/Tests/PersistenceTests/PinxelArchiveTests.swift`

**Interfaces:**
- Consumes: `ZipWriter`, `ZipReader`, `ZipLimits`, `ZipError`, `PinxelDocument`, `ImageAssetRef`, `DocumentRenderer`, `RenderOptions`, `AssetProvider`, `DictionaryAssetProvider`.
- Produces:
  - `enum ImageCodecError: Error, Equatable { encodingFailed(String), decodingFailed }`
  - `enum ImageCodec { static let heicThreshold: Int; static func encode(_: CGImage, type: UTType, quality: Double? = nil) throws -> Data; static func decode(_: Data) throws -> CGImage; static func encodeBackground(_: CGImage) throws -> (ref: ImageAssetRef, data: Data) }`
  - `struct PinxelManifest: Codable { format: String; version: Int; appVersion: String }`
  - `struct PinxelFileContents { var document: PinxelDocument; var images: [ImageAssetRef: Data]; var thumbnail: Data?; var isReadOnly: Bool; func assetProvider() throws -> DictionaryAssetProvider }`
  - `enum PinxelArchiveError: Error, Equatable { notAPinxelFile, invalidDocument(String), missingAsset(String) }`
  - `enum PinxelArchive { static let currentVersion = 1; static func write(document:images:thumbnail:appVersion:) throws -> Data; static func read(_: Data, limits: ZipLimits = .default) throws -> PinxelFileContents; static func requiredAssets(of:) -> [ImageAssetRef]; static func recoverBackground(_: Data) -> Data? }`
  - `enum Thumbnailer { static let maxSide: Double = 512; static func make(_: PinxelDocument, assets: any AssetProvider, renderer: DocumentRenderer = DocumentRenderer()) throws -> Data }`

- [ ] **Step 1: Write the failing tests**

`PinxelKit/Tests/PersistenceTests/PinxelArchiveTests.swift`:

```swift
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

    @Test func archiveLayout() throws {
        let reader = try ZipReader(write())
        #expect(Set(reader.entries.map(\.name)) == ["manifest.json", "document.json", "background.png", TestDocuments.placedImage.name, "thumbnail.png"])
        let manifest = try JSONDecoder().decode(PinxelManifest.self, from: reader.data(for: "manifest.json"))
        #expect(manifest == PinxelManifest(format: "pinxel", version: 1, appVersion: "0.1.0"))
    }

    @Test func newerVersionOpensReadOnly() throws {
        let document = TestDocuments.document(annotations: [])
        var zip = ZipWriter()
        try zip.add(name: "manifest.json", data: Data(#"{"format":"pinxel","version":2,"appVersion":"9.0"}"#.utf8), method: .deflate)
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
        #expect(twice.document.annotations.first?.kind == .unknown(type: "sticker", raw: raw))
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
        try zip.add(name: "manifest.json", data: Data(#"{"format":"pinxel","version":1,"appVersion":"0.1.0"}"#.utf8), method: .store)
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PinxelArchiveTests`
Expected: build FAILS with `cannot find 'ImageCodec' in scope`.

- [ ] **Step 3: Implement the image codec**

`PinxelKit/Sources/Persistence/ImageCodec.swift`:

```swift
import CoreGraphics
import DocumentModel
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageCodecError: Error, Equatable {
    case encodingFailed(String)
    case decodingFailed
}

public enum ImageCodec {
    /// Oltre questa dimensione il PNG dello sfondo viene sostituito da HEIC.
    public static let heicThreshold = 20 * 1024 * 1024

    public static func encode(_ image: CGImage, type: UTType, quality: Double? = nil) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, type.identifier as CFString, 1, nil) else {
            throw ImageCodecError.encodingFailed(type.identifier)
        }
        var properties: [CFString: Any] = [:]
        if let quality { properties[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImageCodecError.encodingFailed(type.identifier) }
        return data as Data
    }

    public static func decode(_ data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ImageCodecError.decodingFailed
        }
        return image
    }

    /// PNG; HEIC se il PNG supera `heicThreshold` e il sistema sa codificare HEIC.
    public static func encodeBackground(_ image: CGImage) throws -> (ref: ImageAssetRef, data: Data) {
        let png = try encode(image, type: .png)
        if png.count > heicThreshold, let heic = try? encode(image, type: .heic, quality: 0.9) {
            return (ImageAssetRef(name: "background.heic"), heic)
        }
        return (ImageAssetRef(name: "background.png"), png)
    }
}
```

- [ ] **Step 4: Implement the archive and the thumbnailer**

`PinxelKit/Sources/Persistence/PinxelArchive.swift`:

```swift
import DocumentModel
import Foundation
import Rendering

public struct PinxelManifest: Codable, Equatable, Sendable {
    public var format: String
    public var version: Int
    public var appVersion: String

    public init(format: String, version: Int, appVersion: String) {
        self.format = format
        self.version = version
        self.appVersion = appVersion
    }
}

public struct PinxelFileContents: Sendable {
    public var document: PinxelDocument
    /// Byte codificati (PNG/HEIC) di ogni immagine referenziata, sfondo incluso.
    public var images: [ImageAssetRef: Data]
    public var thumbnail: Data?
    /// Il file è di una versione più recente: va aperto in sola lettura.
    public var isReadOnly: Bool

    public func assetProvider() throws -> DictionaryAssetProvider {
        var decoded: [ImageAssetRef: CGImage] = [:]
        for (ref, data) in images { decoded[ref] = try ImageCodec.decode(data) }
        return DictionaryAssetProvider(decoded)
    }
}

public enum PinxelArchiveError: Error, Equatable {
    case notAPinxelFile
    case invalidDocument(String)
    case missingAsset(String)
}

public enum PinxelArchive {
    public static let currentVersion = 1

    public static func requiredAssets(of document: PinxelDocument) -> [ImageAssetRef] {
        var refs = [document.background]
        var seen: Set<ImageAssetRef> = [document.background]
        for annotation in document.annotations {
            if case .image(let data) = annotation.kind, seen.insert(data.asset).inserted {
                refs.append(data.asset)
            }
        }
        return refs
    }

    public static func write(document: PinxelDocument, images: [ImageAssetRef: Data], thumbnail: Data, appVersion: String) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var zip = ZipWriter()
        let manifest = PinxelManifest(format: "pinxel", version: currentVersion, appVersion: appVersion)
        try zip.add(name: "manifest.json", data: encoder.encode(manifest), method: .deflate)
        try zip.add(name: "document.json", data: encoder.encode(document), method: .deflate)
        for ref in requiredAssets(of: document) {
            guard let data = images[ref] else { throw PinxelArchiveError.missingAsset(ref.name) }
            try zip.add(name: ref.name, data: data, method: .store)
        }
        try zip.add(name: "thumbnail.png", data: thumbnail, method: .store)
        return try zip.finish()
    }

    public static func read(_ data: Data, limits: ZipLimits = .default) throws -> PinxelFileContents {
        let zip = try ZipReader(data, limits: limits)
        let decoder = JSONDecoder()

        let manifest: PinxelManifest
        do {
            manifest = try decoder.decode(PinxelManifest.self, from: zip.data(for: "manifest.json"))
        } catch ZipError.missingEntry(_) {
            throw PinxelArchiveError.notAPinxelFile
        } catch is DecodingError {
            throw PinxelArchiveError.notAPinxelFile
        }
        guard manifest.format == "pinxel" else { throw PinxelArchiveError.notAPinxelFile }

        let document: PinxelDocument
        do {
            document = try decoder.decode(PinxelDocument.self, from: zip.data(for: "document.json"))
        } catch let error as ZipError {
            if case .missingEntry = error { throw PinxelArchiveError.invalidDocument("document.json missing") }
            throw error
        } catch {
            throw PinxelArchiveError.invalidDocument(String(describing: error))
        }

        var images: [ImageAssetRef: Data] = [:]
        for ref in requiredAssets(of: document) {
            do {
                images[ref] = try zip.data(for: ref.name)
            } catch ZipError.missingEntry(_) {
                throw PinxelArchiveError.missingAsset(ref.name)
            }
        }
        let thumbnail = try? zip.data(for: "thumbnail.png")
        return PinxelFileContents(document: document, images: images, thumbnail: thumbnail, isReadOnly: manifest.version > currentVersion)
    }

    /// Prova a estrarre solo lo sfondo da un file danneggiato.
    public static func recoverBackground(_ data: Data) -> Data? {
        guard let zip = try? ZipReader(data) else { return nil }
        for name in ["background.png", "background.heic"] {
            if let background = try? zip.data(for: name) { return background }
        }
        return nil
    }
}
```

`PinxelKit/Sources/Persistence/Thumbnailer.swift`:

```swift
import DocumentModel
import Foundation
import Rendering

public enum Thumbnailer {
    public static let maxSide: Double = 512

    /// PNG con il lato lungo al massimo di 512 px; le immagini più piccole non vengono ingrandite.
    public static func make(_ document: PinxelDocument, assets: any AssetProvider, renderer: DocumentRenderer = DocumentRenderer()) throws -> Data {
        let canvas = renderer.canvasSize(for: document)
        let scale = min(1, maxSide / max(canvas.width, canvas.height, 1))
        let image = try renderer.renderImage(document, assets: assets, options: RenderOptions(outputScale: scale))
        return try ImageCodec.encode(image, type: .png)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter PinxelArchiveTests`
Expected: PASS, 13 tests. `largeBackgroundIsStoredAsHEIC` may take a few seconds. If it fails only because HEIC encoding is unavailable on the machine (`ref` is `background.png`), report it — do not weaken the test.

- [ ] **Step 6: Commit**

```bash
cd /Users/giovanni/work/reatool
git add PinxelKit
git commit -m "feat(persistence): add .pinxel archive, image codecs and thumbnails"
```

---

### Task 12: Exporter (PNG, JPEG, HEIC, PDF at 1x/2x)

**Files:**
- Create: `PinxelKit/Sources/Persistence/Exporter.swift`
- Test: `PinxelKit/Tests/PersistenceTests/ExporterTests.swift`

**Interfaces:**
- Consumes: `DocumentRenderer`, `RenderOptions`, `RenderError`, `AssetProvider`, `ImageCodec`, `PinxelDocument.scale`.
- Produces:
  - `enum ExportFormat: Equatable { png, jpeg(quality: Double), heic(quality: Double), pdf }`
  - `enum ExportScale { oneX, twoX; func outputScale(documentScale: Double) -> Double }` — `oneX` = logical points, `twoX` = Retina pixels.
  - `enum Exporter { static func export(_: PinxelDocument, assets: any AssetProvider, format: ExportFormat, scale: ExportScale, renderer: DocumentRenderer = DocumentRenderer()) throws -> Data }`. JPEG is rendered on a white matte. PDF keeps annotations as vectors.

- [ ] **Step 1: Write the failing tests**

`PinxelKit/Tests/PersistenceTests/ExporterTests.swift`:

```swift
import CoreGraphics
import Foundation
import Testing
import DocumentModel
import Rendering
@testable import Persistence
import PinxelTestSupport

struct ExporterTests {
    let provider = DictionaryAssetProvider([
        TestDocuments.background: TestImages.quadrants(),
        TestDocuments.placedImage: TestImages.solid(width: 10, height: 10, red: 0, green: 0.6, blue: 1),
    ])

    @Test func pngAtNativeScaleMatchesCanvasRenderExactly() throws {
        // Documento a scala 2: 2x = pixel nativi, cioè quello che il canvas mostra al 100%.
        let document = TestDocuments.document()
        let exported = try ImageCodec.decode(Exporter.export(document, assets: provider, format: .png, scale: .twoX))
        let canvas = try DocumentRenderer().renderImage(document, assets: provider, options: RenderOptions(outputScale: 1))
        #expect(PixelBuffer(exported).differingPixelFraction(from: PixelBuffer(canvas), channelTolerance: 0) == 0)
    }

    @Test func oneXHalvesARetinaCapture() throws {
        let image = try ImageCodec.decode(Exporter.export(TestDocuments.document(), assets: provider, format: .png, scale: .oneX))
        #expect(image.width == 200 && image.height == 150)
    }

    @Test func twoXDoublesANonRetinaCapture() throws {
        let document = TestDocuments.document(scale: 1)
        let image = try ImageCodec.decode(Exporter.export(document, assets: provider, format: .png, scale: .twoX))
        #expect(image.width == 800 && image.height == 600)
    }

    @Test func jpegUsesWhiteMatte() throws {
        var document = TestDocuments.document(annotations: [])
        document.canvasStyle = CanvasStyle(padding: 20)
        let data = try Exporter.export(document, assets: provider, format: .jpeg(quality: 0.9), scale: .twoX)
        #expect(data.starts(with: [0xFF, 0xD8]))
        let pixels = PixelBuffer(try ImageCodec.decode(data))
        let corner = pixels.pixel(x: 3, y: 3)
        #expect(corner.r > 245 && corner.g > 245 && corner.b > 245, "got \(corner)")
    }

    @Test func heicExportDecodes() throws {
        let data = try Exporter.export(TestDocuments.document(), assets: provider, format: .heic(quality: 0.8), scale: .twoX)
        let image = try ImageCodec.decode(data)
        #expect(image.width == 400 && image.height == 300)
    }

    @Test func pdfHasOnePageOfTheRightSize() throws {
        let data = try Exporter.export(TestDocuments.document(), assets: provider, format: .pdf, scale: .oneX)
        #expect(data.starts(with: Array("%PDF".utf8)))
        let pdf = try #require(CGPDFDocument(CGDataProvider(data: data as CFData)!))
        #expect(pdf.numberOfPages == 1)
        let box = try #require(pdf.page(at: 1)).getBoxRect(.mediaBox)
        #expect(box.size == CGSize(width: 200, height: 150))
    }

    @Test func missingBackgroundPropagates() {
        #expect(throws: RenderError.missingBackground) {
            try Exporter.export(TestDocuments.document(), assets: DictionaryAssetProvider([:]), format: .png, scale: .oneX)
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ExporterTests`
Expected: build FAILS with `cannot find 'Exporter' in scope`.

- [ ] **Step 3: Implement the exporter**

`PinxelKit/Sources/Persistence/Exporter.swift`:

```swift
import CoreGraphics
import DocumentModel
import Foundation
import Rendering
import UniformTypeIdentifiers

public enum ExportFormat: Equatable, Sendable {
    case png
    case jpeg(quality: Double)
    case heic(quality: Double)
    case pdf
}

public enum ExportScale: Sendable {
    /// Punti logici (metà dei pixel di una cattura Retina).
    case oneX
    /// Pixel Retina.
    case twoX

    public func outputScale(documentScale: Double) -> Double {
        let target: Double = self == .oneX ? 1 : 2
        return target / max(documentScale, 0.0001)
    }
}

public enum Exporter {
    public static func export(
        _ document: PinxelDocument,
        assets: any AssetProvider,
        format: ExportFormat,
        scale: ExportScale,
        renderer: DocumentRenderer = DocumentRenderer()
    ) throws -> Data {
        let outputScale = scale.outputScale(documentScale: document.scale)
        switch format {
        case .png:
            let image = try renderer.renderImage(document, assets: assets, options: RenderOptions(outputScale: outputScale))
            return try ImageCodec.encode(image, type: .png)
        case .jpeg(let quality):
            let image = try renderer.renderImage(document, assets: assets, options: RenderOptions(outputScale: outputScale, matte: .white))
            return try ImageCodec.encode(image, type: .jpeg, quality: quality)
        case .heic(let quality):
            let image = try renderer.renderImage(document, assets: assets, options: RenderOptions(outputScale: outputScale))
            return try ImageCodec.encode(image, type: .heic, quality: quality)
        case .pdf:
            return try pdf(document, assets: assets, outputScale: outputScale, renderer: renderer)
        }
    }

    private static func pdf(_ document: PinxelDocument, assets: any AssetProvider, outputScale: Double, renderer: DocumentRenderer) throws -> Data {
        // Verifica prima lo sfondo, così l'errore è lo stesso degli altri formati.
        _ = try renderer.processedBackground(for: document, assets: assets)
        let canvas = renderer.canvasSize(for: document)
        var mediaBox = CGRect(x: 0, y: 0, width: canvas.width * outputScale, height: canvas.height * outputScale)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw RenderError.contextCreationFailed
        }
        ctx.beginPDFPage(nil)
        try renderer.render(document, assets: assets, in: ctx, options: RenderOptions(outputScale: outputScale))
        ctx.endPDFPage()
        ctx.closePDF()
        return data as Data
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ExporterTests`
Expected: PASS, 7 tests.

- [ ] **Step 5: Run the full suite**

Run: `swift test`
Expected: PASS, every test in DocumentModelTests, RenderingTests and PersistenceTests. Also run `swift build -c release` — it must build without errors.

- [ ] **Step 6: Commit**

```bash
cd /Users/giovanni/work/reatool
git add PinxelKit
git commit -m "feat(persistence): export to PNG, JPEG, HEIC and PDF at 1x/2x"
```

---

## Spec coverage (self-review)

| Spec section | Covered by |
|---|---|
| §2 decisions (Swift 6, macOS 15, CG/CI rendering) | Task 1, 6 |
| §3 format choices (separate immutable background, image-space coords, explicit scale, stable IDs, metadata; no base64, no flat record) | Tasks 2, 3, 11 |
| §4 modules and dependencies | Tasks 1, 6, 10 (`Package.swift`) |
| §5.1 document | Task 3 |
| §5.2 annotations, Style, RGBA, RichText, steps | Tasks 1, 2, 4 |
| §5.3 image operations + annotation mapping | Tasks 3, 5 |
| §5.4 commands, single command per gesture (merge), invariant | Task 5 (UndoManager wiring is plan 3) |
| §6.2 rendering of every tool | Tasks 7, 8, 9 |
| §6.4 blur/pixel/magnifier semantics, cache | Tasks 6, 9 |
| §8 `.pinxel` format, versioning, unknown kinds, defensive reading | Tasks 10, 11 |
| §9 export formats and scales, single render path | Task 12 |
| §10 errors: corrupt file, unsupported version, missing assets | Tasks 10, 11 |
| §11 tests: model, persistence, rendering snapshots | all tasks |
| §7 capture, §6.1/6.3 editor UI, §9 clipboard/drag/share, §10 permission/hotkey errors | **plan 2 and plan 3** |
