# Scrolling Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capture content taller than the screen in one image: the user drags an area, Pinxel scrolls it (or the user does) and stitches the frames by matching them.

**Architecture:** Pure logic in `CaptureKit`: `ScrollStitcher` (row signatures, fixed bands, offset search, accumulation), two protocols (`RegionFrameSource`, `ScrollDriver`) with a deterministic `FakeScrollingPage`, and `ScrollCaptureSession` (the capture → stitch → scroll → settle loop). Real implementations use ScreenCaptureKit and `CGEvent` scroll events. The app reuses the area overlay, shows a border window and a non-activating panel, and hands the image to the existing post-capture path.

**Tech Stack:** Swift 6, macOS 15+, ScreenCaptureKit, CoreGraphics, AppKit + SwiftUI, Swift Testing (package), XCTest (UI tests), XcodeGen.

**Spec:** `docs/superpowers/specs/2026-10-17-pinxel-scrolling-capture-design.md`

## Global Constraints

- macOS 15+, Swift 6 strict concurrency; no third-party dependencies.
- Vertical scrolling only, downwards.
- Maximum output height: `PinxelDocument.maxImageSide` = 32768 px (CaptureKit cannot import DocumentModel: pass `32768` from the app).
- Minimum area height: 100 pt. Memory budget for the worst case: 1 GB (width px × 32768 × 4).
- Automatic step: 2/3 of the scrolling region height. Settle: until two identical frames, at most 500 ms. Manual mode: ~10 frames/s. Auto-scroll resumes 1 s after the last manual scroll.
- End: two automatic steps with no movement, Fine/Return, or the height limit. Esc/Annulla discard.
- 3 consecutive `noMatch` in automatic mode stop the capture and keep what is stitched.
- Default shortcut for the new action: ⌃⇧5 (keyCode 0x17). Menu title "Cattura a scorrimento".
- The result follows the "Dopo la cattura" setting, through `CaptureDocumentBuilder` and `PostCaptureActions`.
- User-facing strings in Italian; code, comments style as the surrounding files (comments in Italian), commits in English with the Co-Authored-By trailer.
- Never mention other screenshot products in the repo (public).

## Ruling against the spec

- The spec puts `ScrollCaptureSession` and `AccessibilityPermission` in AppCore. AppCore does not depend on CaptureKit, and both only need CaptureKit types; they go in **CaptureKit**, next to `ScreenRecordingPermission`. Cost if wrong: moving two files.
- `StitchStep` gains `.first`, `.ambiguous` and `.sizeMismatch` besides the spec's cases; `.ambiguous` is what "discard the frame and wait" returns in manual mode.
- In manual mode `noMatch` does not stop the capture (a fast flick can outrun 10 frames/s); the frame is discarded and the next one is matched against the last good one. The spec's 3-strikes rule applies to automatic mode.

## Review Focus

1. Periodic content (a list of identical rows): several offsets match equally; with a hint the nearest one must win, never a multiple of the row height. → test in Task 2.
2. A page whose first rows are blank: the blank rows look like a fixed header at the first move; the result must still equal the page. → test in Task 2.
3. Scrolling back up during an automatic capture, then down again: nothing is appended twice. → test in Task 2 and Task 3.
4. Pinxel's own panel/border overlapping the area when the screen has no room around it: excluded from the capture by window identity, so the image is clean. → manual check S9.
5. Settings saved by a previous version (no `scrolling` key) keep the user's other shortcuts and get ⌃⇧5. → test in Task 5.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `PinxelKit/Sources/CaptureKit/ScrollCapturing.swift` (new) | `RegionFrameSource`, `ScrollDriver` protocols |
| `PinxelKit/Sources/CaptureKit/FakeScrollingPage.swift` (new) | deterministic long page: source + driver for tests and UI tests |
| `PinxelKit/Sources/CaptureKit/ScrollStitcher.swift` (new) | frame matching and accumulation |
| `PinxelKit/Sources/CaptureKit/ScrollCaptureSession.swift` (new) | capture loop, end conditions, progress |
| `PinxelKit/Sources/CaptureKit/ScrollCaptureGeometry.swift` (new) | area preparation (screen, minimum, memory), panel placement |
| `PinxelKit/Sources/CaptureKit/ScrollCaptureSystem.swift` (new) | ScreenCaptureKit source, CGEvent driver, Accessibility permission |
| `PinxelKit/Sources/AppCore/KeyCombo.swift` | `HotKeyAction.scrolling` |
| `App/Pinxel/Capture/ScrollCaptureController.swift` (new) | border window, panel, key/scroll monitors |
| `App/Pinxel/Capture/ScrollCapturePanel.swift` (new) | SwiftUI panel content |
| `App/Pinxel/Capture/CaptureCoordinator.swift` | `captureScrolling()` |
| `App/Pinxel/AppEnvironment.swift`, `MenuContent.swift`, `AppDelegate.swift` | wiring, menu, UI-test launch args |
| `PinxelKit/Tests/CaptureKitTests/*` | unit tests |
| `App/PinxelUITests/ScrollCaptureUITests.swift` (new) | end-to-end with the fake page |
| `docs/manual-tests/scrolling.md` (new) | manual checklist |

Run package tests with `cd PinxelKit && swift test --filter <Suite>`; after adding files under `App/`, run `xcodegen generate` from the repo root.

---

### Task 1: Protocols and fake scrolling page

**Files:**
- Create: `PinxelKit/Sources/CaptureKit/ScrollCapturing.swift`
- Create: `PinxelKit/Sources/CaptureKit/FakeScrollingPage.swift`
- Test: `PinxelKit/Tests/CaptureKitTests/FakeScrollingPageTests.swift`

**Interfaces:**
- Produces: `protocol RegionFrameSource` with `func prepare(display: DisplayInfo) async throws` (default no-op) and `func frame(of rect: CGRect, on display: DisplayInfo) async throws -> CGImage`; `protocol ScrollDriver` with `func scroll(by points: Double, at point: CGPoint)` (positive = further down the document); `final class FakeScrollingPage: RegionFrameSource, ScrollDriver` with `init(content: CGImage, viewportHeight: Int, header: CGImage? = nil, footer: CGImage? = nil, scale: Double = 2, scrollFactor: Double = 1)`, `position`, `maxPosition`, `scrollCalls`, `frameCount`, `isAnimating`, `onFrame: ((Int) -> Void)?`, `func scrollTo(_:)`, `func currentFrame() -> CGImage`, `var expectedImage: CGImage`.

- [ ] **Step 1: Write the failing test**

```swift
import CoreGraphics
import Testing
@testable import CaptureKit
import PinxelTestSupport

@MainActor
struct FakeScrollingPageTests {
    let display = DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 800, height: 600), scale: 2)

    @Test func framesShowTheViewportBetweenHeaderAndFooter() async throws {
        let content = TestImages.noise(width: 40, height: 200)
        let page = FakeScrollingPage(content: content, viewportHeight: 50,
                                     header: TestImages.solid(width: 40, height: 10, red: 1, green: 0, blue: 0),
                                     footer: TestImages.solid(width: 40, height: 6, red: 0, green: 0, blue: 1))
        page.scroll(by: 15, at: .zero) // 15 pt × 2 = 30 px
        #expect(page.position == 30)
        let frame = PixelBuffer(try await page.frame(of: .zero, on: display))
        #expect(frame.height == 66)
        #expect(frame.pixel(x: 3, y: 2) == RGBA8(r: 255, g: 0, b: 0))
        #expect(frame.pixel(x: 3, y: 63) == RGBA8(r: 0, g: 0, b: 255))
        #expect(frame.pixel(x: 7, y: 10) == PixelBuffer(content).pixel(x: 7, y: 30))
        #expect(page.frameCount == 1)
    }

    @Test func scrollingStopsAtTheEndsAndHonoursTheFactor() {
        let page = FakeScrollingPage(content: TestImages.noise(width: 20, height: 100), viewportHeight: 40, scale: 1, scrollFactor: 1.5)
        page.scroll(by: 10, at: .zero)
        #expect(page.position == 15)
        page.scroll(by: 1000, at: .zero)
        #expect(page.position == 60)
        page.scroll(by: -1000, at: .zero)
        #expect(page.position == 0)
        #expect(page.scrollCalls == [10, 1000, -1000])
    }

    @Test func expectedImageStacksHeaderContentAndFooter() {
        let page = FakeScrollingPage(content: TestImages.noise(width: 20, height: 100), viewportHeight: 40,
                                     header: TestImages.solid(width: 20, height: 5, red: 1, green: 0, blue: 0))
        #expect(page.expectedImage.height == 105)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd PinxelKit && swift test --filter FakeScrollingPageTests`
Expected: FAIL — `cannot find 'FakeScrollingPage' in scope`.

- [ ] **Step 3: Write the protocols**

`ScrollCapturing.swift`:

```swift
import CoreGraphics

/// Immagini di un rettangolo dello schermo, una alla volta, per la cattura a scorrimento.
@MainActor
public protocol RegionFrameSource {
    /// Prepara la cattura dopo che le finestre di Pinxel (cornice, pannello) sono comparse, per escluderle.
    func prepare(display: DisplayInfo) async throws
    /// `rect` in punti globali con origine in alto a sinistra; l'immagine è alla risoluzione dello schermo.
    func frame(of rect: CGRect, on display: DisplayInfo) async throws -> CGImage
}

public extension RegionFrameSource {
    func prepare(display: DisplayInfo) async throws {}
}

/// Fa scorrere il contenuto sotto `point` (punti globali, origine in alto a sinistra).
@MainActor
public protocol ScrollDriver {
    /// Positivo: più giù nel documento (il contenuto sale).
    func scroll(by points: Double, at point: CGPoint)
}
```

- [ ] **Step 4: Write the fake page**

`FakeScrollingPage.swift`:

```swift
import CoreGraphics

/// Pagina lunga virtuale per test e UI test: fa da sorgente dei fotogrammi e da scorrimento.
/// I fotogrammi sono intestazione + `viewportHeight` righe del contenuto + piè di pagina.
@MainActor
public final class FakeScrollingPage: RegionFrameSource, ScrollDriver {
    public let content: CGImage
    public let viewportHeight: Int
    public let header: CGImage?
    public let footer: CGImage?
    public let scale: Double
    /// Quanto scorre davvero rispetto al richiesto (app con accelerazione o scorrimento ridotto).
    public var scrollFactor: Double
    /// Contenuto che cambia da solo: ogni fotogramma è diverso dal precedente.
    public var isAnimating = false
    /// Chiamato a ogni fotogramma con il numero del fotogramma (da 1).
    public var onFrame: ((Int) -> Void)?
    public private(set) var position = 0
    public private(set) var scrollCalls: [Double] = []
    public private(set) var frameCount = 0

    public init(content: CGImage, viewportHeight: Int, header: CGImage? = nil, footer: CGImage? = nil,
                scale: Double = 2, scrollFactor: Double = 1) {
        self.content = content
        self.viewportHeight = min(viewportHeight, content.height)
        self.header = header
        self.footer = footer
        self.scale = scale
        self.scrollFactor = scrollFactor
    }

    public var maxPosition: Int { content.height - viewportHeight }

    public func scroll(by points: Double, at point: CGPoint) {
        scrollCalls.append(points)
        scrollTo(position + Int((points * scale * scrollFactor).rounded()))
    }

    /// Scorrimento a mano, in pixel.
    public func scrollTo(_ newPosition: Int) {
        position = min(max(newPosition, 0), maxPosition)
    }

    public func frame(of rect: CGRect, on display: DisplayInfo) async throws -> CGImage {
        frameCount += 1
        onFrame?(frameCount)
        return currentFrame()
    }

    public func currentFrame() -> CGImage {
        let headerHeight = header?.height ?? 0, footerHeight = footer?.height ?? 0
        let width = content.width, height = headerHeight + viewportHeight + footerHeight
        let ctx = Self.context(width: width, height: height)
        // Il contesto ha origine in basso a sinistra; `cropping` ha origine in alto a sinistra.
        if isAnimating {
            ctx.setFillColor(CGColor(srgbRed: Double(frameCount % 7) / 7, green: 0.5, blue: Double(frameCount % 3) / 3, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            ctx.fill(CGRect(x: frameCount * 7 % max(width, 1), y: 0, width: 3, height: height))
            return ctx.makeImage()!
        }
        if let visible = content.cropping(to: CGRect(x: 0, y: position, width: width, height: viewportHeight)) {
            ctx.draw(visible, in: CGRect(x: 0, y: footerHeight, width: width, height: viewportHeight))
        }
        if let header { ctx.draw(header, in: CGRect(x: 0, y: height - headerHeight, width: width, height: headerHeight)) }
        if let footer { ctx.draw(footer, in: CGRect(x: 0, y: 0, width: width, height: footerHeight)) }
        return ctx.makeImage()!
    }

    /// Ciò che una cattura perfetta deve produrre: intestazione, tutto il contenuto, piè di pagina.
    public var expectedImage: CGImage {
        let headerHeight = header?.height ?? 0, footerHeight = footer?.height ?? 0
        let width = content.width, height = headerHeight + content.height + footerHeight
        let ctx = Self.context(width: width, height: height)
        ctx.draw(content, in: CGRect(x: 0, y: footerHeight, width: width, height: content.height))
        if let header { ctx.draw(header, in: CGRect(x: 0, y: height - headerHeight, width: width, height: headerHeight)) }
        if let footer { ctx.draw(footer, in: CGRect(x: 0, y: 0, width: width, height: footerHeight)) }
        return ctx.makeImage()!
    }

    static func context(width: Int, height: Int) -> CGContext {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd PinxelKit && swift test --filter FakeScrollingPageTests`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add PinxelKit/Sources/CaptureKit/ScrollCapturing.swift PinxelKit/Sources/CaptureKit/FakeScrollingPage.swift PinxelKit/Tests/CaptureKitTests/FakeScrollingPageTests.swift
git commit -m "feat(capture): frame source and scroll driver protocols with a fake scrolling page"
```

---

### Task 2: ScrollStitcher

**Files:**
- Create: `PinxelKit/Sources/CaptureKit/ScrollStitcher.swift`
- Test: `PinxelKit/Tests/CaptureKitTests/ScrollStitcherTests.swift`

**Interfaces:**
- Consumes: `FakeScrollingPage` (tests only).
- Produces: `enum StitchStep { case first, appended(Int), unchanged, movedBack, ambiguous, noMatch, reachedLimit, sizeMismatch }`; `struct ScrollStitcher` with `init(maxHeight: Int)`, `mutating func add(_ image: CGImage, hint: Int?) -> StitchStep`, `height: Int`, `regionHeight: Int`, `topBand: Int`, `bottomBand: Int`, `func image() -> CGImage?`, `func thumbnail(width: Int) -> CGImage?`.

- [ ] **Step 1: Write the failing tests**

```swift
import CoreGraphics
import Testing
@testable import CaptureKit
import PinxelTestSupport

@MainActor
struct ScrollStitcherTests {
    /// Scorre la pagina a passi di `step` pixel richiesti (il fattore della pagina decide quelli veri) fino in fondo.
    func stitch(_ page: FakeScrollingPage, step: Int, hint: Bool = true, maxHeight: Int = 32768) -> (ScrollStitcher, [StitchStep]) {
        var stitcher = ScrollStitcher(maxHeight: maxHeight)
        var steps = [stitcher.add(page.currentFrame(), hint: nil)]
        var unchanged = 0
        while unchanged < 2, steps.count < 200 {
            page.scroll(by: Double(step) / page.scale, at: .zero)
            let result = stitcher.add(page.currentFrame(), hint: hint ? step : nil)
            steps.append(result)
            if result == .reachedLimit { break }
            unchanged = result == .unchanged ? unchanged + 1 : 0
        }
        return (stitcher, steps)
    }

    func expectEqual(_ image: CGImage?, _ expected: CGImage, sourceLocation: SourceLocation = #_sourceLocation) {
        guard let image else { Issue.record("no image", sourceLocation: sourceLocation); return }
        #expect(image.width == expected.width && image.height == expected.height, "\(image.width)x\(image.height)", sourceLocation: sourceLocation)
        #expect(PixelBuffer(image) == PixelBuffer(expected), sourceLocation: sourceLocation)
    }

    @Test func exactStepsRebuildThePage() {
        let page = FakeScrollingPage(content: TestImages.noise(width: 64, height: 900), viewportHeight: 120, scale: 1)
        let (stitcher, steps) = stitch(page, step: 80)
        #expect(steps.first == .first)
        expectEqual(stitcher.image(), page.expectedImage)
    }

    @Test(arguments: [0.7, 1.3])
    func appsThatScrollMoreOrLessStillRebuildThePage(factor: Double) {
        let page = FakeScrollingPage(content: TestImages.noise(width: 64, height: 900), viewportHeight: 120, scale: 1, scrollFactor: factor)
        let (stitcher, _) = stitch(page, step: 70)
        expectEqual(stitcher.image(), page.expectedImage)
    }

    @Test func fixedHeaderAndFooterAppearOnce() {
        let page = FakeScrollingPage(content: TestImages.noise(width: 64, height: 700), viewportHeight: 120,
                                     header: TestImages.solid(width: 64, height: 20, red: 1, green: 0, blue: 0),
                                     footer: TestImages.solid(width: 64, height: 12, red: 0, green: 0, blue: 1), scale: 1)
        let (stitcher, _) = stitch(page, step: 80)
        #expect(stitcher.topBand == 20)
        #expect(stitcher.bottomBand == 12)
        expectEqual(stitcher.image(), page.expectedImage)
    }

    @Test func blankTopRowsDoNotBreakThePage() {
        let ctx = FakeScrollingPage.context(width: 64, height: 700)
        ctx.draw(TestImages.noise(width: 64, height: 700), in: CGRect(x: 0, y: 0, width: 64, height: 700))
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 700 - 30, width: 64, height: 30)) // 30 righe bianche in cima
        let page = FakeScrollingPage(content: ctx.makeImage()!, viewportHeight: 120, scale: 1)
        let (stitcher, _) = stitch(page, step: 80)
        expectEqual(stitcher.image(), page.expectedImage)
    }

    @Test func periodicRowsFollowTheHint() {
        // Righe identiche ogni 20 px: senza indizio ogni multiplo di 20 andrebbe bene.
        let ctx = FakeScrollingPage.context(width: 64, height: 600)
        for row in 0..<30 {
            ctx.setFillColor(CGColor(srgbRed: row % 2 == 0 ? 0.9 : 0.2, green: 0.4, blue: 0.6, alpha: 1))
            ctx.fill(CGRect(x: 0, y: row * 20, width: 64, height: 20))
        }
        let page = FakeScrollingPage(content: ctx.makeImage()!, viewportHeight: 120, scale: 1)
        let (stitcher, _) = stitch(page, step: 80)
        #expect(stitcher.height == 600)
    }

    @Test func uniformContentUsesTheHintOrWaits() {
        let blank = TestImages.solid(width: 64, height: 600, red: 1, green: 1, blue: 1)
        let page = FakeScrollingPage(content: blank, viewportHeight: 120, scale: 1)
        var stitcher = ScrollStitcher(maxHeight: 32768)
        _ = stitcher.add(page.currentFrame(), hint: nil)
        page.scroll(by: 50, at: .zero)
        // Fotogrammi identici: nessun movimento visibile.
        #expect(stitcher.add(page.currentFrame(), hint: nil) == .unchanged)
    }

    @Test func scrollingBackUpAppendsNothingTwice() {
        let page = FakeScrollingPage(content: TestImages.noise(width: 64, height: 600), viewportHeight: 120, scale: 1)
        var stitcher = ScrollStitcher(maxHeight: 32768)
        _ = stitcher.add(page.currentFrame(), hint: nil)
        page.scrollTo(80); _ = stitcher.add(page.currentFrame(), hint: nil)
        page.scrollTo(160); _ = stitcher.add(page.currentFrame(), hint: nil)
        page.scrollTo(100)
        #expect(stitcher.add(page.currentFrame(), hint: nil) == .movedBack)
        page.scrollTo(140)
        #expect(stitcher.add(page.currentFrame(), hint: nil) == .appended(0))
        for position in stride(from: 220, through: page.maxPosition, by: 60) {
            page.scrollTo(position); _ = stitcher.add(page.currentFrame(), hint: nil)
        }
        page.scrollTo(page.maxPosition); _ = stitcher.add(page.currentFrame(), hint: nil)
        expectEqual(stitcher.image(), page.expectedImage)
    }

    @Test func aJumpLargerThanTheFrameIsNoMatch() {
        let page = FakeScrollingPage(content: TestImages.noise(width: 64, height: 900), viewportHeight: 120, scale: 1)
        var stitcher = ScrollStitcher(maxHeight: 32768)
        _ = stitcher.add(page.currentFrame(), hint: nil)
        page.scrollTo(400)
        #expect(stitcher.add(page.currentFrame(), hint: 400) == .noMatch)
        // Il riferimento resta il fotogramma buono: tornando vicino si riprende.
        page.scrollTo(60)
        #expect(stitcher.add(page.currentFrame(), hint: nil) == .appended(60))
    }

    @Test func stopsAtTheHeightLimit() {
        let page = FakeScrollingPage(content: TestImages.noise(width: 64, height: 900), viewportHeight: 120, scale: 1)
        let (stitcher, steps) = stitch(page, step: 80, maxHeight: 300)
        #expect(steps.last == .reachedLimit)
        #expect(stitcher.height == 300)
        #expect(PixelBuffer(stitcher.image()!).pixel(x: 5, y: 299) == PixelBuffer(page.expectedImage).pixel(x: 5, y: 299))
    }

    @Test func framesOfAnotherSizeAreRejected() {
        var stitcher = ScrollStitcher(maxHeight: 32768)
        _ = stitcher.add(TestImages.noise(width: 64, height: 120), hint: nil)
        #expect(stitcher.add(TestImages.noise(width: 64, height: 100), hint: nil) == .sizeMismatch)
    }

    @Test func thumbnailKeepsTheAspectRatio() {
        let page = FakeScrollingPage(content: TestImages.noise(width: 64, height: 600), viewportHeight: 120, scale: 1)
        let (stitcher, _) = stitch(page, step: 80)
        let thumbnail = stitcher.thumbnail(width: 16)
        #expect(thumbnail?.width == 16)
        #expect(thumbnail?.height == 150)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd PinxelKit && swift test --filter ScrollStitcherTests`
Expected: FAIL — `cannot find 'ScrollStitcher' in scope`.

- [ ] **Step 3: Implement**

`ScrollStitcher.swift`:

```swift
import CoreGraphics
import Foundation

/// Esito dell'aggiunta di un fotogramma a `ScrollStitcher`.
public enum StitchStep: Equatable, Sendable {
    /// Primo fotogramma: diventa l'inizio dell'immagine.
    case first
    /// Il contenuto è sceso; aggiunte queste righe (0 se erano già state catturate).
    case appended(Int)
    /// Nessuno spostamento (fine pagina o contenuto fermo).
    case unchanged
    /// Il contenuto è salito: si aggiorna solo la posizione.
    case movedBack
    /// Contenuto uniforme senza indizio: fotogramma scartato.
    case ambiguous
    /// Nessuna sovrapposizione riconoscibile: fotogramma scartato, il riferimento resta il precedente.
    case noMatch
    /// Raggiunta l'altezza massima: l'immagine finisce qui.
    case reachedLimit
    /// Fotogramma di dimensioni diverse dal primo.
    case sizeMismatch
}

/// Cuce i fotogrammi di un'area che scorre in verticale (spec §4). Logica pura: niente schermi né eventi.
public struct ScrollStitcher {
    static let blocks = 32
    /// Errore medio (0–255) sotto cui due righe combaciano.
    static let matchThreshold: Float = 3
    /// Spostamenti con errore entro questa distanza dal migliore sono equivalenti.
    static let tieTolerance: Float = 0.75
    /// Righe confrontate al massimo per ogni spostamento provato.
    static let maxSampledRows = 400

    struct Frame {
        let bytes: [UInt8]
        let signatures: [Float]
    }

    enum Match {
        case shift(Int)
        case ambiguous
        case noMatch
    }

    public let maxHeight: Int
    public private(set) var width = 0
    public private(set) var frameHeight = 0
    public private(set) var topBand = 0
    public private(set) var bottomBand = 0
    private var bandsKnown = false
    /// Fascia superiore + contenuto che scorre, RGBA premoltiplicato sRGB, righe dall'alto.
    private var canvas: [UInt8] = []
    /// Fascia inferiore dell'ultimo fotogramma: va in fondo all'immagine.
    private var bottomRows: [UInt8] = []
    private var previous: Frame?
    /// Riga del contenuto in cima alla zona che scorre del fotogramma di riferimento.
    private var position = 0
    /// Righe di contenuto che scorre già nell'immagine.
    private var captured = 0

    public init(maxHeight: Int) {
        self.maxHeight = maxHeight
    }

    private var rowBytes: Int { width * 4 }
    /// Altezza in pixel della parte che scorre, senza fasce fisse.
    public var regionHeight: Int { frameHeight - topBand - bottomBand }
    public var height: Int { rowBytes == 0 ? 0 : (canvas.count + bottomRows.count) / rowBytes }

    public mutating func add(_ image: CGImage, hint: Int?) -> StitchStep {
        guard let previous else {
            width = image.width
            frameHeight = image.height
            let frame = Self.makeFrame(image)
            let rows = min(frameHeight, maxHeight)
            canvas = Array(frame.bytes[0..<rows * rowBytes])
            captured = rows
            self.previous = frame
            return rows < frameHeight ? .reachedLimit : .first
        }
        guard image.width == width, image.height == frameHeight else { return .sizeMismatch }
        let frame = Self.makeFrame(image)
        if frame.bytes == previous.bytes { return .unchanged }
        if !bandsKnown { detectBands(previous, frame) }

        switch match(previous, frame, hint: hint) {
        case .ambiguous:
            return .ambiguous
        case .noMatch:
            return .noMatch
        case .shift(let shift):
            self.previous = frame
            bottomRows = Array(frame.bytes[(frameHeight - bottomBand) * rowBytes ..< frameHeight * rowBytes])
            if shift == 0 { return .unchanged }
            position += shift
            if shift < 0 { return .movedBack }
            let newBottom = position + regionHeight
            guard newBottom > captured else { return .appended(0) }
            let wanted = newBottom - captured
            let room = max(0, maxHeight - (topBand + captured + bottomBand))
            let rows = min(wanted, room)
            let start = topBand + regionHeight - wanted
            canvas += frame.bytes[start * rowBytes ..< (start + rows) * rowBytes]
            captured += rows
            return rows < wanted ? .reachedLimit : .appended(rows)
        }
    }

    /// Righe in cima e in fondo identiche alla stessa posizione mentre il centro cambia: intestazioni e barre fisse.
    /// Al massimo un quarto del fotogramma ciascuna. Si decide una volta, al primo movimento.
    private mutating func detectBands(_ old: Frame, _ new: Frame) {
        bandsKnown = true
        let limit = frameHeight / 4
        func same(_ row: Int) -> Bool {
            old.bytes[row * rowBytes ..< (row + 1) * rowBytes] == new.bytes[row * rowBytes ..< (row + 1) * rowBytes]
        }
        var top = 0
        while top < limit, same(top) { top += 1 }
        var bottom = 0
        while bottom < limit, same(frameHeight - 1 - bottom) { bottom += 1 }
        topBand = top
        bottomBand = bottom
        // Finora l'immagine è il primo fotogramma intero: la fascia inferiore va tolta e rimessa in fondo alla fine.
        let keep = min(canvas.count / rowBytes, frameHeight - bottom)
        canvas.removeSubrange(keep * rowBytes ..< canvas.count)
        captured = keep - top
        position = 0
    }

    private func match(_ old: Frame, _ new: Frame, hint: Int?) -> Match {
        let region = regionHeight
        let minimumOverlap = max(8, region / 4)
        guard region > minimumOverlap else { return .noMatch }
        let range = -(region - minimumOverlap)...(region - minimumOverlap)
        var errors: [(shift: Int, error: Float)] = []
        errors.reserveCapacity(range.count)
        for shift in range {
            errors.append((shift, error(old, new, shift: shift)))
        }
        let best = errors.min { $0.error < $1.error }!
        guard best.error <= Self.matchThreshold else { return .noMatch }
        let candidates = errors.filter { $0.error <= best.error + Self.tieTolerance }.map(\.shift)
        let spread = candidates.max()! - candidates.min()!
        guard spread > 2 else { return .shift(best.shift) }
        // Più spostamenti equivalenti (contenuto uniforme o ripetuto): decide l'indizio, se c'è.
        guard let hint else { return .ambiguous }
        return .shift(candidates.min { abs($0 - hint) < abs($1 - hint) }!)
    }

    /// Errore medio tra le righe vecchie da `shift` in giù e le nuove dall'inizio (o viceversa se `shift` < 0).
    private func error(_ old: Frame, _ new: Frame, shift: Int) -> Float {
        let overlap = regionHeight - abs(shift)
        let stride = max(1, overlap / Self.maxSampledRows)
        var total: Float = 0
        var count = 0
        var i = 0
        while i < overlap {
            let oldRow = topBand + (shift >= 0 ? i + shift : i)
            let newRow = topBand + (shift >= 0 ? i : i - shift)
            let a = oldRow * Self.blocks, b = newRow * Self.blocks
            for k in 0..<Self.blocks { total += abs(old.signatures[a + k] - new.signatures[b + k]) }
            count += Self.blocks
            i += stride
        }
        return count == 0 ? .infinity : total / Float(count)
    }

    static func makeFrame(_ image: CGImage) -> Frame {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let ctx = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var signatures = [Float](repeating: 0, count: height * blocks)
        for y in 0..<height {
            let row = y * width * 4
            for block in 0..<blocks {
                let x0 = min(width - 1, block * width / blocks)
                let x1 = max(x0 + 1, (block + 1) * width / blocks)
                var sum = 0
                for x in x0..<x1 {
                    let p = row + x * 4
                    sum += (Int(bytes[p]) * 299 + Int(bytes[p + 1]) * 587 + Int(bytes[p + 2]) * 114) / 1000
                }
                signatures[y * blocks + block] = Float(sum) / Float(x1 - x0)
            }
        }
        return Frame(bytes: bytes, signatures: signatures)
    }

    /// L'immagine cucita finora.
    public func image() -> CGImage? {
        guard rowBytes > 0 else { return nil }
        return Self.makeImage(bytes: canvas + bottomRows, width: width)
    }

    /// Miniatura larga `width` pixel per il pannello, campionando le righe senza copiare l'immagine intera.
    public func thumbnail(width thumbnailWidth: Int) -> CGImage? {
        let total = height
        guard rowBytes > 0, total > 0, thumbnailWidth > 0 else { return nil }
        let thumbnailHeight = max(1, total * thumbnailWidth / width)
        var bytes = [UInt8](repeating: 0, count: thumbnailWidth * thumbnailHeight * 4)
        let canvasRows = canvas.count / rowBytes
        for y in 0..<thumbnailHeight {
            let sourceRow = min(total - 1, y * total / thumbnailHeight)
            for x in 0..<thumbnailWidth {
                let sourceX = min(width - 1, x * width / thumbnailWidth)
                let offset = sourceX * 4
                let target = (y * thumbnailWidth + x) * 4
                if sourceRow < canvasRows {
                    let p = sourceRow * rowBytes + offset
                    bytes[target ..< target + 4] = canvas[p ..< p + 4]
                } else {
                    let p = (sourceRow - canvasRows) * rowBytes + offset
                    bytes[target ..< target + 4] = bottomRows[p ..< p + 4]
                }
            }
        }
        return Self.makeImage(bytes: bytes, width: thumbnailWidth)
    }

    static func makeImage(bytes: [UInt8], width: Int) -> CGImage? {
        let height = bytes.count / (width * 4)
        guard height > 0, let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd PinxelKit && swift test --filter ScrollStitcherTests`
Expected: PASS (12 tests including both arguments). If `blankTopRowsDoNotBreakThePage` fails because the white rows are taken as a header, that is the Review Focus #2 failure: fix the stitcher (not the test) — e.g. bands only count rows that also differ from their neighbours in the new frame — and record the ruling.

- [ ] **Step 5: Commit**

```bash
git add PinxelKit/Sources/CaptureKit/ScrollStitcher.swift PinxelKit/Tests/CaptureKitTests/ScrollStitcherTests.swift
git commit -m "feat(capture): stitch scrolling frames by matching row signatures"
```

---

### Task 3: ScrollCaptureSession and geometry

**Files:**
- Create: `PinxelKit/Sources/CaptureKit/ScrollCaptureSession.swift`
- Create: `PinxelKit/Sources/CaptureKit/ScrollCaptureGeometry.swift`
- Test: `PinxelKit/Tests/CaptureKitTests/ScrollCaptureSessionTests.swift`
- Test: `PinxelKit/Tests/CaptureKitTests/ScrollCaptureGeometryTests.swift`

**Interfaces:**
- Consumes: `RegionFrameSource`, `ScrollDriver`, `FakeScrollingPage`, `ScrollStitcher`, `StitchStep`.
- Produces: `final class ScrollCaptureSession` (`@MainActor @Observable`) with `enum Outcome { case reachedEnd, finishedByUser, reachedLimit, contentChanging, cancelled }`, `init(source:driver:rect:display:maxHeight:sleep:now:)`, `height`, `preview`, `outcome`, `scrollsAutomatically`, `func run() async -> CGImage?`, `finish()`, `cancel()`, `userDidScroll()`; `enum ScrollCaptureGeometry` with `minimumHeight`, `byteBudget`, `static func prepare(_ rect: CGRect, on display: DisplayInfo, maxHeight: Int) -> (rect: CGRect, narrowed: Bool)?`, `static func panelFrame(size: CGSize, around rect: CGRect, in screen: CGRect, gap: CGFloat = 12) -> CGRect`.

- [ ] **Step 1: Write the failing tests**

`ScrollCaptureSessionTests.swift`:

```swift
import CoreGraphics
import Testing
@testable import CaptureKit
import PinxelTestSupport

/// Tempo finto: `sleep` avanza l'orologio senza aspettare.
@MainActor
final class FakeTime {
    var now: Double = 0
    func sleep(_ duration: Duration) async {
        now += Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        await Task.yield()
    }
}

@MainActor
struct ScrollCaptureSessionTests {
    let display = DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 800, height: 600), scale: 1)
    let rect = CGRect(x: 0, y: 0, width: 64, height: 120)

    func makeSession(_ page: FakeScrollingPage, automatic: Bool = true, time: FakeTime = FakeTime(), maxHeight: Int = 32768) -> ScrollCaptureSession {
        ScrollCaptureSession(source: page, driver: automatic ? page : nil, rect: rect, display: display, maxHeight: maxHeight,
                             sleep: { await time.sleep($0) }, now: { time.now })
    }

    @Test func automaticCaptureScrollsToTheEnd() async {
        let page = FakeScrollingPage(content: TestImages.noise(width: 64, height: 900), viewportHeight: 120, scale: 1)
        let session = makeSession(page)
        let image = await session.run()
        #expect(session.outcome == .reachedEnd)
        #expect(image.map(PixelBuffer.init) == PixelBuffer(page.expectedImage))
        #expect(page.scrollCalls.first == 80) // 2/3 di 120 pt
        #expect(session.height == 900)
        #expect(session.preview != nil)
    }

    @Test func fineKeepsWhatIsStitched() async {
        let page = FakeScrollingPage(content: TestImages.noise(width: 64, height: 900), viewportHeight: 120, scale: 1)
        let session = makeSession(page)
        page.onFrame = { count in if count == 3 { session.finish() } }
        let image = await session.run()
        #expect(session.outcome == .finishedByUser)
        #expect(image != nil)
        #expect((image?.height ?? 0) < 900)
    }

    @Test func cancelDiscardsEverything() async {
        let page = FakeScrollingPage(content: TestImages.noise(width: 64, height: 900), viewportHeight: 120, scale: 1)
        let session = makeSession(page)
        page.onFrame = { count in if count == 3 { session.cancel() } }
        #expect(await session.run() == nil)
        #expect(session.outcome == .cancelled)
    }

    @Test func withoutADriverTheUserScrolls() async {
        let page = FakeScrollingPage(content: TestImages.noise(width: 64, height: 400), viewportHeight: 120, scale: 1)
        let session = makeSession(page, automatic: false)
        #expect(!session.scrollsAutomatically)
        page.onFrame = { count in
            page.scrollTo(count * 50) // l'utente scorre di 50 px fra un fotogramma e l'altro
            if count == 12 { session.finish() }
        }
        let image = await session.run()
        #expect(page.scrollCalls.isEmpty)
        #expect(image.map(PixelBuffer.init) == PixelBuffer(page.expectedImage))
    }

    @Test func manualScrollingPausesTheAutomaticSteps() async {
        let time = FakeTime()
        let page = FakeScrollingPage(content: TestImages.noise(width: 64, height: 900), viewportHeight: 120, scale: 1)
        let session = makeSession(page, time: time)
        var callsWhilePaused = -1
        page.onFrame = { count in
            if count == 2 { session.userDidScroll() }
            if count == 4 { callsWhilePaused = page.scrollCalls.count }
        }
        _ = await session.run()
        #expect(callsWhilePaused == 1) // dopo lo scorrimento a mano, per 1 s nessun passo automatico
        #expect(session.outcome == .reachedEnd)
    }

    @Test func contentThatChangesStopsTheCapture() async {
        let page = FakeScrollingPage(content: TestImages.noise(width: 64, height: 900), viewportHeight: 120, scale: 1)
        let session = makeSession(page)
        page.onFrame = { count in if count == 2 { page.isAnimating = true } }
        let image = await session.run()
        #expect(session.outcome == .contentChanging)
        #expect(image?.height == 120) // resta il primo fotogramma
    }

    @Test func stopsAtTheHeightLimit() async {
        let page = FakeScrollingPage(content: TestImages.noise(width: 64, height: 900), viewportHeight: 120, scale: 1)
        let session = makeSession(page, maxHeight: 400)
        let image = await session.run()
        #expect(session.outcome == .reachedLimit)
        #expect(image?.height == 400)
    }

    @Test func scrollingBackDuringAnAutomaticCaptureAddsNothingTwice() async {
        let page = FakeScrollingPage(content: TestImages.noise(width: 64, height: 900), viewportHeight: 120, scale: 1)
        let session = makeSession(page)
        page.onFrame = { count in if count == 4 { page.scrollTo(page.position - 100); session.userDidScroll() } }
        let image = await session.run()
        #expect(image.map(PixelBuffer.init) == PixelBuffer(page.expectedImage))
    }
}
```

`ScrollCaptureGeometryTests.swift`:

```swift
import CoreGraphics
import Testing
@testable import CaptureKit

struct ScrollCaptureGeometryTests {
    let display = DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 2)

    @Test func areaIsClippedToItsScreenAndMustBeTallEnough() {
        #expect(ScrollCaptureGeometry.prepare(CGRect(x: 100, y: 100, width: 300, height: 99), on: display, maxHeight: 32768) == nil)
        // Dentro lo schermo restano 140×100 punti: esattamente il minimo, quindi accettata.
        let boundary = ScrollCaptureGeometry.prepare(CGRect(x: 1300, y: 800, width: 300, height: 300), on: display, maxHeight: 32768)
        #expect(boundary?.rect == CGRect(x: 1300, y: 800, width: 140, height: 100))
        let ok = ScrollCaptureGeometry.prepare(CGRect(x: 1300, y: 700, width: 300, height: 300), on: display, maxHeight: 32768)
        #expect(ok?.rect == CGRect(x: 1300, y: 700, width: 140, height: 200))
        #expect(ok?.narrowed == false)
    }

    @Test func widthIsLimitedByTheMemoryBudget() {
        let wide = DisplayInfo(id: 2, frame: CGRect(x: 0, y: 0, width: 6000, height: 2000), scale: 2)
        let prepared = ScrollCaptureGeometry.prepare(CGRect(x: 0, y: 0, width: 6000, height: 500), on: wide, maxHeight: 32768)
        // 1 GB / (32768 × 4) = 8192 px = 4096 pt a 2x.
        #expect(prepared?.rect.width == 4096)
        #expect(prepared?.narrowed == true)
    }

    @Test func panelGoesBelowThenAboveThenBeside() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let size = CGSize(width: 340, height: 64)
        let below = ScrollCaptureGeometry.panelFrame(size: size, around: CGRect(x: 500, y: 100, width: 400, height: 400), in: screen)
        #expect(below == CGRect(x: 530, y: 512, width: 340, height: 64))
        let above = ScrollCaptureGeometry.panelFrame(size: size, around: CGRect(x: 500, y: 300, width: 400, height: 580), in: screen)
        #expect(above == CGRect(x: 530, y: 224, width: 340, height: 64))
        let beside = ScrollCaptureGeometry.panelFrame(size: size, around: CGRect(x: 100, y: 20, width: 400, height: 860), in: screen)
        #expect(beside == CGRect(x: 512, y: 20, width: 340, height: 64))
        let inside = ScrollCaptureGeometry.panelFrame(size: size, around: screen, in: screen)
        #expect(screen.contains(inside))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd PinxelKit && swift test --filter "ScrollCaptureSessionTests|ScrollCaptureGeometryTests"`
Expected: FAIL — `cannot find 'ScrollCaptureSession' in scope`.

- [ ] **Step 3: Implement the geometry**

`ScrollCaptureGeometry.swift`:

```swift
import CoreGraphics

/// Calcoli dell'area e del pannello della cattura a scorrimento. Coordinate globali in punti, origine in alto a sinistra.
public enum ScrollCaptureGeometry {
    public static let minimumHeight: CGFloat = 100
    /// Memoria massima per l'immagine più lunga possibile.
    public static let byteBudget = 1 << 30

    /// L'area limitata al suo schermo e, se serve, ristretta in larghezza per il budget di memoria.
    /// `nil` se resta più bassa di `minimumHeight`.
    public static func prepare(_ rect: CGRect, on display: DisplayInfo, maxHeight: Int) -> (rect: CGRect, narrowed: Bool)? {
        let clipped = rect.standardized.intersection(display.frame)
        guard !clipped.isNull, clipped.height >= minimumHeight else { return nil }
        let maxWidth = (Double(byteBudget / (max(maxHeight, 1) * 4)) / display.scale).rounded(.down)
        guard clipped.width > maxWidth else { return (clipped, false) }
        return (CGRect(x: clipped.minX, y: clipped.minY, width: maxWidth, height: clipped.height), true)
    }

    /// Pannello fuori dall'area: sotto, sopra, a destra, a sinistra; se non c'è posto, in basso a destra dentro lo schermo
    /// (la cattura esclude comunque le finestre di Pinxel).
    public static func panelFrame(size: CGSize, around rect: CGRect, in screen: CGRect, gap: CGFloat = 12) -> CGRect {
        func clampX(_ x: CGFloat) -> CGFloat { min(max(x, screen.minX), screen.maxX - size.width) }
        func clampY(_ y: CGFloat) -> CGFloat { min(max(y, screen.minY), screen.maxY - size.height) }
        let centeredX = clampX(rect.midX - size.width / 2)
        if rect.maxY + gap + size.height <= screen.maxY {
            return CGRect(origin: CGPoint(x: centeredX, y: rect.maxY + gap), size: size)
        }
        if rect.minY - gap - size.height >= screen.minY {
            return CGRect(origin: CGPoint(x: centeredX, y: rect.minY - gap - size.height), size: size)
        }
        if rect.maxX + gap + size.width <= screen.maxX {
            return CGRect(origin: CGPoint(x: rect.maxX + gap, y: clampY(rect.minY)), size: size)
        }
        if rect.minX - gap - size.width >= screen.minX {
            return CGRect(origin: CGPoint(x: rect.minX - gap - size.width, y: clampY(rect.minY)), size: size)
        }
        return CGRect(origin: CGPoint(x: screen.maxX - size.width - gap, y: screen.maxY - size.height - gap), size: size)
    }
}
```

- [ ] **Step 4: Implement the session**

`ScrollCaptureSession.swift`:

```swift
import CoreGraphics
import Observation

/// Il ciclo della cattura a scorrimento (spec §2, §4): cattura → cuci → scorri → attendi che il contenuto si fermi.
@MainActor
@Observable
public final class ScrollCaptureSession {
    public enum Outcome: Equatable, Sendable {
        case reachedEnd, finishedByUser, reachedLimit, contentChanging, cancelled
    }

    public static let settleTimeout = 0.5
    public static let settleInterval: Duration = .milliseconds(50)
    public static let manualInterval: Duration = .milliseconds(100)
    public static let manualResumeDelay = 1.0
    public static let minimumStep = 20.0

    /// Altezza in pixel dell'immagine cucita finora.
    public private(set) var height = 0
    public private(set) var preview: CGImage?
    public private(set) var outcome: Outcome?
    /// Falso senza permesso Accessibilità: scorre solo l'utente.
    public let scrollsAutomatically: Bool

    @ObservationIgnored private let source: any RegionFrameSource
    @ObservationIgnored private let driver: (any ScrollDriver)?
    @ObservationIgnored private let rect: CGRect
    @ObservationIgnored private let display: DisplayInfo
    @ObservationIgnored private var stitcher: ScrollStitcher
    @ObservationIgnored private let sleep: @MainActor (Duration) async -> Void
    @ObservationIgnored private let now: @MainActor () -> Double
    @ObservationIgnored private var lastManualScroll = -Double.infinity
    @ObservationIgnored private var stopRequest: Outcome?

    public init(source: any RegionFrameSource, driver: (any ScrollDriver)?, rect: CGRect, display: DisplayInfo,
                maxHeight: Int = 32768,
                sleep: @escaping @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) },
                now: @escaping @MainActor () -> Double = ScrollCaptureSession.secondsSinceLaunch) {
        self.source = source
        self.driver = driver
        self.rect = rect
        self.display = display
        self.sleep = sleep
        self.now = now
        stitcher = ScrollStitcher(maxHeight: maxHeight)
        scrollsAutomatically = driver != nil
    }

    public func finish() {
        if stopRequest == nil { stopRequest = .finishedByUser }
    }

    public func cancel() {
        stopRequest = .cancelled
    }

    /// L'utente ha scorso a mano: i passi automatici si fermano per `manualResumeDelay`.
    public func userDidScroll() {
        lastManualScroll = now()
    }

    /// Cattura fino alla fine; `nil` se annullata.
    public func run() async -> CGImage? {
        do {
            try await source.prepare(display: display)
            let first = stitcher.add(try await source.frame(of: rect, on: display), hint: nil)
            publish()
            if first == .reachedLimit { outcome = .reachedLimit }
            var step = Double(stitcher.regionHeight) / display.scale * 2 / 3
            var unchanged = 0
            var noMatch = 0
            while outcome == nil {
                if let stop = stopRequest {
                    outcome = stop
                    break
                }
                guard let driver, now() - lastManualScroll >= Self.manualResumeDelay else {
                    await sleep(Self.manualInterval)
                    if stopRequest != nil { continue }
                    let result = stitcher.add(try await source.frame(of: rect, on: display), hint: nil)
                    publish()
                    if result == .reachedLimit { outcome = .reachedLimit }
                    continue
                }
                driver.scroll(by: step, at: CGPoint(x: rect.midX, y: rect.midY))
                let frame = try await settledFrame()
                if stopRequest != nil { continue }
                let result = stitcher.add(frame, hint: Int((step * display.scale).rounded()))
                publish()
                switch result {
                case .unchanged:
                    unchanged += 1
                    if unchanged >= 2 { outcome = .reachedEnd }
                case .appended, .movedBack, .first:
                    unchanged = 0
                    noMatch = 0
                case .noMatch, .ambiguous:
                    noMatch += 1
                    if noMatch >= 3 {
                        outcome = .contentChanging
                    } else {
                        // Troppo lontano: si torna su di mezzo passo e si prosegue con passi più corti.
                        driver.scroll(by: -step / 2, at: CGPoint(x: rect.midX, y: rect.midY))
                        step = max(Self.minimumStep, step / 2)
                    }
                case .reachedLimit:
                    outcome = .reachedLimit
                case .sizeMismatch:
                    outcome = .contentChanging
                }
            }
        } catch {
            outcome = stopRequest ?? .contentChanging
        }
        if outcome == nil { outcome = stopRequest ?? .contentChanging }
        return outcome == .cancelled ? nil : stitcher.image()
    }

    /// Cattura finché due fotogrammi di fila sono uguali, al massimo `settleTimeout`.
    private func settledFrame() async throws -> CGImage {
        var last = try await source.frame(of: rect, on: display)
        let start = now()
        while now() - start < Self.settleTimeout {
            await sleep(Self.settleInterval)
            let next = try await source.frame(of: rect, on: display)
            if Self.sameImage(last, next) { return next }
            last = next
        }
        return last
    }

    static func sameImage(_ a: CGImage, _ b: CGImage) -> Bool {
        guard a.width == b.width, a.height == b.height else { return false }
        return a.dataProvider?.data as Data? == b.dataProvider?.data as Data?
    }

    private func publish() {
        height = stitcher.height
        preview = stitcher.thumbnail(width: 80)
    }
}

extension ScrollCaptureSession {
    private static let clockStart = ContinuousClock.now

    /// Orologio monotono in secondi: la sessione usa solo differenze.
    public static func secondsSinceLaunch() -> Double {
        let components = clockStart.duration(to: .now).components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
```

Add `import Foundation` at the top of the file (`Data` in `sameImage`).

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd PinxelKit && swift test --filter "ScrollCaptureSessionTests|ScrollCaptureGeometryTests"`
Expected: PASS (8 + 3 tests).

- [ ] **Step 6: Commit**

```bash
git add PinxelKit/Sources/CaptureKit/ScrollCaptureSession.swift PinxelKit/Sources/CaptureKit/ScrollCaptureGeometry.swift PinxelKit/Tests/CaptureKitTests/ScrollCaptureSessionTests.swift PinxelKit/Tests/CaptureKitTests/ScrollCaptureGeometryTests.swift
git commit -m "feat(capture): scrolling capture session loop and area/panel geometry"
```

---

### Task 4: System implementations (ScreenCaptureKit, CGEvent, Accessibility)

**Files:**
- Create: `PinxelKit/Sources/CaptureKit/ScrollCaptureSystem.swift`
- Test: `PinxelKit/Tests/CaptureKitTests/ScrollCaptureSystemTests.swift`

**Interfaces:**
- Produces: `final class ScreenCaptureKitFrameSource: RegionFrameSource` (`init(excludingBundleIdentifier: String)`, `static func sourceRect(for rect: CGRect, on display: DisplayInfo) -> CGRect`, `static func pixelSize(for rect: CGRect, on display: DisplayInfo) -> (width: Int, height: Int)`); `struct CGEventScrollDriver: ScrollDriver` (`static let syntheticMarker: Int64`, `static func chunks(for points: Double) -> [Double]`); `protocol AccessibilityPermission { var isGranted: Bool { get }; func request(); func openSystemSettings() }`, `struct SystemAccessibilityPermission`, `struct FixedAccessibilityPermission(isGranted: Bool)`.

- [ ] **Step 1: Write the failing tests** (only the pure parts; the system calls are checked by the manual checklist)

```swift
import CoreGraphics
import Testing
@testable import CaptureKit

@MainActor
struct ScrollCaptureSystemTests {
    @Test func sourceRectIsRelativeToTheDisplay() {
        let display = DisplayInfo(id: 2, frame: CGRect(x: 1440, y: -200, width: 1920, height: 1080), scale: 2)
        let rect = CGRect(x: 1500, y: 100, width: 300, height: 400)
        #expect(ScreenCaptureKitFrameSource.sourceRect(for: rect, on: display) == CGRect(x: 60, y: 300, width: 300, height: 400))
        #expect(ScreenCaptureKitFrameSource.pixelSize(for: rect, on: display) == (600, 800))
    }

    @Test func scrollsAreSplitIntoSmallEvents() {
        #expect(CGEventScrollDriver.chunks(for: 150) == [50, 50, 50])
        #expect(CGEventScrollDriver.chunks(for: -40) == [-40])
        #expect(CGEventScrollDriver.chunks(for: 0) == [])
    }

    @Test func fixedPermissionReportsItsValue() {
        #expect(FixedAccessibilityPermission(isGranted: true).isGranted)
        #expect(!FixedAccessibilityPermission(isGranted: false).isGranted)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd PinxelKit && swift test --filter ScrollCaptureSystemTests`
Expected: FAIL — `cannot find 'ScreenCaptureKitFrameSource' in scope`.

- [ ] **Step 3: Implement**

`ScrollCaptureSystem.swift`:

```swift
import AppKit
import ApplicationServices
import CoreGraphics
@preconcurrency import ScreenCaptureKit

/// Fotogrammi reali con ScreenCaptureKit, escludendo le finestre di Pinxel. Verificata dalla checklist manuale
/// (docs/manual-tests/scrolling.md).
@MainActor
public final class ScreenCaptureKitFrameSource: RegionFrameSource {
    private let bundleIdentifier: String
    private var filter: SCContentFilter?

    public init(excludingBundleIdentifier bundleIdentifier: String) {
        self.bundleIdentifier = bundleIdentifier
    }

    public func prepare(display: DisplayInfo) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let screen = content.displays.first(where: { $0.displayID == display.id }) else { throw CaptureError.displayNotFound }
        let own = content.windows.filter { $0.owningApplication?.bundleIdentifier == bundleIdentifier }
        filter = SCContentFilter(display: screen, excludingWindows: own)
    }

    public func frame(of rect: CGRect, on display: DisplayInfo) async throws -> CGImage {
        if filter == nil { try await prepare(display: display) }
        guard let filter else { throw CaptureError.displayNotFound }
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = Self.sourceRect(for: rect, on: display)
        let size = Self.pixelSize(for: rect, on: display)
        configuration.width = size.width
        configuration.height = size.height
        configuration.showsCursor = false
        configuration.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    static func sourceRect(for rect: CGRect, on display: DisplayInfo) -> CGRect {
        rect.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
    }

    static func pixelSize(for rect: CGRect, on display: DisplayInfo) -> (width: Int, height: Int) {
        (Int((rect.width * display.scale).rounded()), Int((rect.height * display.scale).rounded()))
    }
}

/// Scorrimento con eventi di sistema in pixel; richiede il permesso Accessibilità.
@MainActor
public struct CGEventScrollDriver: ScrollDriver {
    /// Segna gli eventi di Pinxel, per distinguerli dallo scorrimento dell'utente nei monitor globali.
    public static let syntheticMarker: Int64 = 0x5069_6E78
    static let maximumChunk = 50.0

    public init() {}

    public func scroll(by points: Double, at point: CGPoint) {
        for chunk in Self.chunks(for: points) {
            // Rotella negativa: il contenuto sale, cioè si va più giù nel documento.
            guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                      wheel1: Int32((-chunk).rounded()), wheel2: 0, wheel3: 0) else { continue }
            event.location = point
            event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
            event.post(tap: .cghidEventTap)
        }
    }

    static func chunks(for points: Double) -> [Double] {
        guard points != 0 else { return [] }
        let count = Int((abs(points) / maximumChunk).rounded(.up))
        return Array(repeating: points / Double(count), count: count)
    }
}

@MainActor
public protocol AccessibilityPermission {
    var isGranted: Bool { get }
    /// Mostra la richiesta di sistema.
    func request()
    func openSystemSettings()
}

@MainActor
public struct SystemAccessibilityPermission: AccessibilityPermission {
    public init() {}

    public var isGranted: Bool { AXIsProcessTrusted() }

    public func request() {
        // Chiave di kAXTrustedCheckOptionPrompt, scritta per esteso: la globale C non è concurrency-safe.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    public func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Per test e UI test.
@MainActor
public struct FixedAccessibilityPermission: AccessibilityPermission {
    public let isGranted: Bool
    public init(isGranted: Bool) { self.isGranted = isGranted }
    public func request() {}
    public func openSystemSettings() {}
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd PinxelKit && swift test --filter ScrollCaptureSystemTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add PinxelKit/Sources/CaptureKit/ScrollCaptureSystem.swift PinxelKit/Tests/CaptureKitTests/ScrollCaptureSystemTests.swift
git commit -m "feat(capture): ScreenCaptureKit frames, CGEvent scrolling and accessibility permission"
```

---

### Task 5: Shortcut action

**Files:**
- Modify: `PinxelKit/Sources/AppCore/KeyCombo.swift:69-89`
- Test: `PinxelKit/Tests/AppCoreTests/KeyComboTests.swift`, `PinxelKit/Tests/AppCoreTests/SettingsTests.swift`

**Interfaces:**
- Produces: `HotKeyAction.scrolling` (`title` "Cattura a scorrimento", `defaultCombo` ⌃⇧5 = keyCode 0x17), order `area, window, screen, scrolling, repeatLastArea`.

- [ ] **Step 1: Write the failing tests**

In `KeyComboTests.defaultsAreControlShiftDigits` add:

```swift
        #expect(HotKeyAction.scrolling.defaultCombo.displayString == "⌃⇧5")
        #expect(HotKeyAction.scrolling.title == "Cattura a scorrimento")
        #expect(Set(HotKeyAction.allCases.map(\.defaultCombo)).count == HotKeyAction.allCases.count)
```

In `SettingsTests` add:

```swift
    @Test func settingsFromBeforeScrollingKeepTheirShortcuts() throws {
        var old = CaptureSettings()
        old.hotKeys = [.area: KeyCombo(keyCode: 0x15, modifiers: KeyCombo.command | KeyCombo.shift)]
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
        // Una versione precedente non conosceva `scrolling`: la si toglie dal JSON, in qualunque forma sia codificata.
        if var keys = json["hotKeys"] as? [String: Any] { keys["scrolling"] = nil; json["hotKeys"] = keys }
        if var pairs = json["hotKeys"] as? [Any], let index = pairs.firstIndex(where: { ($0 as? String) == "scrolling" }) {
            pairs.removeSubrange(index...index + 1); json["hotKeys"] = pairs
        }
        let decoded = try JSONDecoder().decode(CaptureSettings.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.combo(for: .area) == KeyCombo(keyCode: 0x15, modifiers: KeyCombo.command | KeyCombo.shift))
        #expect(decoded.combo(for: .scrolling) == HotKeyAction.scrolling.defaultCombo)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd PinxelKit && swift test --filter "KeyComboTests|SettingsTests"`
Expected: FAIL — `type 'HotKeyAction' has no member 'scrolling'`.

- [ ] **Step 3: Implement**

In `KeyCombo.swift`:

```swift
public enum HotKeyAction: String, Codable, CaseIterable, Sendable {
    case area, window, screen, scrolling, repeatLastArea

    public var title: String {
        switch self {
        case .area: "Cattura area"
        case .window: "Cattura finestra"
        case .screen: "Cattura schermo"
        case .scrolling: "Cattura a scorrimento"
        case .repeatLastArea: "Ripeti ultima area"
        }
    }

    public var defaultCombo: KeyCombo {
        let modifiers = KeyCombo.control | KeyCombo.shift
        switch self {
        case .area: return KeyCombo(keyCode: 0x12, modifiers: modifiers)
        case .window: return KeyCombo(keyCode: 0x13, modifiers: modifiers)
        case .screen: return KeyCombo(keyCode: 0x14, modifiers: modifiers)
        case .scrolling: return KeyCombo(keyCode: 0x17, modifiers: modifiers)
        case .repeatLastArea: return KeyCombo(keyCode: 0x15, modifiers: modifiers)
        }
    }
```

The app's `switch action` statements in `AppEnvironment.perform` and `MenuContent.perform` stop compiling; add `case .scrolling: captureScrolling()` / `case .scrolling: environment.captureScrolling(fromMenu: true)` with a temporary `func captureScrolling(fromMenu: Bool = false) {}` in `AppEnvironment`, filled in Task 6.

- [ ] **Step 4: Run tests to verify they pass, build the app**

Run: `cd PinxelKit && swift test --filter "KeyComboTests|SettingsTests"` → PASS.
Run: `xcodebuild -project Pinxel.xcodeproj -scheme Pinxel -configuration Debug build 2>&1 | grep -E "BUILD (SUCC|FAIL)"` → `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add PinxelKit/Sources/AppCore/KeyCombo.swift PinxelKit/Tests/AppCoreTests App/Pinxel/AppEnvironment.swift App/Pinxel/MenuContent.swift
git commit -m "feat(app): scrolling capture shortcut action (Control-Shift-5)"
```

---

### Task 6: App flow — controller, panel, coordinator, UI test, checklist

**Files:**
- Create: `App/Pinxel/Capture/ScrollCaptureController.swift`
- Create: `App/Pinxel/Capture/ScrollCapturePanel.swift`
- Modify: `App/Pinxel/Capture/CaptureCoordinator.swift`
- Modify: `App/Pinxel/AppEnvironment.swift`, `App/Pinxel/AppDelegate.swift`
- Create: `App/PinxelUITests/ScrollCaptureUITests.swift`
- Create: `docs/manual-tests/scrolling.md`

**Interfaces:**
- Consumes: everything from Tasks 1–5; existing `SelectionProvider`, `PostCaptureActions.perform`, `CaptureDocumentBuilder.make`, `ScreenGeometry.appKit(fromTopLeft:primaryHeight:)`, `ScreenGeometry.display(at:in:)`, `Notifier.info(_:)`.
- Produces: `protocol ScrollCapturePresenting { func run(_ session: ScrollCaptureSession, rect: CGRect, display: DisplayInfo, narrowed: Bool) async -> CGImage? }`, `struct ScrollCaptureDependencies`, `CaptureCoordinator.captureScrolling()`, `AppEnvironment.captureScrolling(fromMenu:)`, launch args `-PinxelUITestFakeScrolling`, `-PinxelUITestScrollOnLaunch`.

- [ ] **Step 1: Write the failing UI test**

`App/PinxelUITests/ScrollCaptureUITests.swift`:

```swift
import XCTest

final class ScrollCaptureUITests: XCTestCase {
    private var pasteboardGuard: PasteboardGuard?

    override func setUp() {
        continueAfterFailure = false
        pasteboardGuard = PasteboardGuard()
    }

    override func tearDown() {
        pasteboardGuard?.restore()
    }

    /// La pagina finta è larga 400 px e lunga 1200: la cattura a scorrimento la deve ricostruire intera.
    func testScrollingCaptureOpensTheWholePageInTheEditor() {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-PinxelUITestFakeCapture", "-PinxelUITestFakeScrolling",
                               "-PinxelUITestPostCapture", "openEditor", "-PinxelUITestScrollOnLaunch"]
        app.launch()
        let canvas = app.images["pinxel.editor.canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 20))
        let whole = NSPredicate(format: "value ENDSWITH %@", "immagine: 400\u{00D7}1200")
        wait(for: [expectation(for: whole, evaluatedWith: canvas)], timeout: 5)
        app.activate()
        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.lifetime = .keepAlways
        add(shot)
        app.terminate()
    }
}
```

Run: `xcodegen generate && pkill -x Pinxel; caffeinate -dimsu xcodebuild -project Pinxel.xcodeproj -scheme Pinxel -destination 'platform=macOS' test -only-testing:PinxelUITests/ScrollCaptureUITests`
Expected: FAIL — the canvas never appears (nothing handles `-PinxelUITestScrollOnLaunch`).

- [ ] **Step 2: Panel view**

`App/Pinxel/Capture/ScrollCapturePanel.swift`:

```swift
import CaptureKit
import SwiftUI

/// Pannello flottante della cattura a scorrimento: miniatura che cresce, altezza, Fine e Annulla.
struct ScrollCapturePanel: View {
    let session: ScrollCaptureSession
    let narrowed: Bool

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(session.scrollsAutomatically ? "Cattura a scorrimento" : "Scorri tu")
                    .font(.headline)
                Text("\(session.height) px")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Button("Annulla") { session.cancel() }
            Button("Fine") { session.finish() }
                .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .frame(width: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(.smooth(duration: 0.25), value: session.height)
    }

    private var message: String? {
        if !session.scrollsAutomatically { return "Per lo scorrimento automatico consenti Pinxel in Accessibilità." }
        if narrowed { return "Area ristretta in larghezza per non esaurire la memoria." }
        return nil
    }

    @ViewBuilder private var thumbnail: some View {
        Group {
            if let preview = session.preview {
                Image(decorative: preview, scale: 1)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.secondary.opacity(0.15)
            }
        }
        .frame(width: 36, height: 48, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
    }
}
```

- [ ] **Step 3: Controller**

`App/Pinxel/Capture/ScrollCaptureController.swift`:

```swift
import AppKit
import CaptureKit
import SwiftUI

@MainActor
protocol ScrollCapturePresenting {
    func run(_ session: ScrollCaptureSession, rect: CGRect, display: DisplayInfo, narrowed: Bool) async -> CGImage?
}

/// Cornice attorno all'area e pannello accanto, mentre la sessione scorre e cuce. Tasti: Esc annulla, Invio finisce.
@MainActor
final class ScrollCaptureController: ScrollCapturePresenting {
    private var windows: [NSWindow] = []
    private var monitors: [Any] = []

    func run(_ session: ScrollCaptureSession, rect: CGRect, display: DisplayInfo, narrowed: Bool) async -> CGImage? {
        show(session, rect: rect, display: display, narrowed: narrowed)
        defer { close() }
        return await session.run()
    }

    private func show(_ session: ScrollCaptureSession, rect: CGRect, display: DisplayInfo, narrowed: Bool) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0

        let border = NSWindow(contentRect: ScreenGeometry.appKit(fromTopLeft: rect.insetBy(dx: -3, dy: -3), primaryHeight: primaryHeight),
                              styleMask: .borderless, backing: .buffered, defer: false)
        border.isOpaque = false
        border.backgroundColor = .clear
        border.hasShadow = false
        border.ignoresMouseEvents = true
        border.level = .statusBar
        border.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        border.contentView = ScrollFrameView()
        border.orderFrontRegardless()

        let hosting = NSHostingView(rootView: ScrollCapturePanel(session: session, narrowed: narrowed))
        let size = hosting.fittingSize
        let frame = ScrollCaptureGeometry.panelFrame(size: size, around: rect, in: display.frame)
        let panel = NSPanel(contentRect: ScreenGeometry.appKit(fromTopLeft: frame, primaryHeight: primaryHeight),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting
        panel.orderFrontRegardless()
        windows = [border, panel]

        // Lo scorrimento va alla finestra sotto il puntatore: se è fuori dall'area lo si porta al centro.
        let mouse = NSEvent.mouseLocation
        if !rect.contains(CGPoint(x: mouse.x, y: primaryHeight - mouse.y)) {
            CGWarpMouseCursorPosition(CGPoint(x: rect.midX, y: rect.midY))
        }

        let keys: (NSEvent) -> Void = { event in
            switch event.keyCode {
            case 53: session.cancel()
            case 36, 76: session.finish()
            default: break
            }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { event in
            MainActor.assumeIsolated { keys(event) }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            keys(event)
            return event
        }) { monitors.append(local) }
        if let scroll = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel, handler: { event in
            MainActor.assumeIsolated {
                if event.cgEvent?.getIntegerValueField(.eventSourceUserData) != CGEventScrollDriver.syntheticMarker {
                    session.userDidScroll()
                }
            }
        }) { monitors.append(scroll) }
    }

    private func close() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        windows.forEach { $0.orderOut(nil) }
        windows = []
    }
}

/// Filo attorno all'area, appena fuori dal rettangolo catturato.
private final class ScrollFrameView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: 3, yRadius: 3)
        path.lineWidth = 2
        NSColor.controlAccentColor.setStroke()
        path.stroke()
    }
}
```

- [ ] **Step 4: Coordinator**

In `CaptureCoordinator.swift` add a dependency bundle, a stored property, an init parameter, and the flow:

```swift
/// Ciò che serve alla cattura a scorrimento; nei UI test la pagina finta fa da sorgente e da scorrimento.
@MainActor
struct ScrollCaptureDependencies {
    let accessibility: any AccessibilityPermission
    let makeSource: () -> any RegionFrameSource
    let makeDriver: () -> any ScrollDriver
    let presenter: any ScrollCapturePresenting
    let defaults: UserDefaults
}
```

Init signature becomes `init(engine:permission:selection:actions:scrolling:settings:)` storing `private let scrolling: ScrollCaptureDependencies`. Add:

```swift
    static let maxScrollingHeight = 32768 // PinxelDocument.maxImageSide
    private static let accessibilityAskedKey = "PinxelAccessibilityRequested"

    func captureScrolling() async {
        guard !isCapturing else { return }
        isCapturing = true
        defer { isCapturing = false }
        guard permission.isGranted else {
            showPermissionWindow()
            return
        }
        let frontmost = NSWorkspace.shared.frontmostApplication
        let current = settings()
        do {
            let snapshot = try await engine.snapshot(excludingBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.degiorgi.pinxel")
            guard case .area(let selected) = await selection.select(mode: .area, snapshot: snapshot) else {
                frontmost?.activate()
                return
            }
            let center = CGPoint(x: selected.midX, y: selected.midY)
            guard let display = ScreenGeometry.display(at: center, in: snapshot.displays.map(\.info)) else { throw CaptureError.displayNotFound }
            guard let prepared = ScrollCaptureGeometry.prepare(selected, on: display, maxHeight: Self.maxScrollingHeight) else {
                AppEnvironment.shared.notifier.info("Area troppo bassa per la cattura a scorrimento: almeno \(Int(ScrollCaptureGeometry.minimumHeight)) punti")
                frontmost?.activate()
                return
            }
            if !scrolling.accessibility.isGranted, !scrolling.defaults.bool(forKey: Self.accessibilityAskedKey) {
                scrolling.defaults.set(true, forKey: Self.accessibilityAskedKey)
                scrolling.accessibility.request()
            }
            // L'app sotto l'area deve ricevere lo scorrimento: torna davanti prima di iniziare.
            frontmost?.activate()
            let session = ScrollCaptureSession(source: scrolling.makeSource(),
                                               driver: scrolling.accessibility.isGranted ? scrolling.makeDriver() : nil,
                                               rect: prepared.rect, display: display, maxHeight: Self.maxScrollingHeight)
            guard let image = await scrolling.presenter.run(session, rect: prepared.rect, display: display, narrowed: prepared.narrowed) else { return }
            var metadata = CaptureMetadata(captureDate: Date(), appName: frontmost?.localizedName, bundleIdentifier: frontmost?.bundleIdentifier)
            metadata.windowTitle = nil
            let contents = try CaptureDocumentBuilder.make(image: image, scale: display.scale, metadata: metadata)
            let plan = PostCaptureRouter.plan(for: current)
            actions.perform(plan, contents: contents, image: image, settings: current)
            if session.outcome == .reachedLimit {
                AppEnvironment.shared.notifier.info("Raggiunta l'altezza massima di \(Self.maxScrollingHeight) pixel")
            } else if session.outcome == .contentChanging {
                AppEnvironment.shared.notifier.info("Il contenuto cambia da solo: cattura fermata")
            }
        } catch {
            logger.error("scrolling capture failed: \(String(describing: error), privacy: .public)")
            AppEnvironment.shared.notifier.failure(error)
            frontmost?.activate()
        }
    }
```

- [ ] **Step 5: Environment and launch arguments**

In `AppEnvironment.init`, after `let actions = ...`:

```swift
        let scrolling: ScrollCaptureDependencies
        if arguments.contains("-PinxelUITestFakeScrolling") {
            // 200×150 pt a 2x come l'area finta: pagina di rumore 400×1200 px.
            let page = FakeScrollingPage(content: Self.fakeScrollingContent(), viewportHeight: 300, scale: 2)
            scrolling = ScrollCaptureDependencies(accessibility: FixedAccessibilityPermission(isGranted: true),
                                                  makeSource: { page }, makeDriver: { page },
                                                  presenter: ScrollCaptureController(), defaults: store.defaults)
        } else {
            let bundle = Bundle.main.bundleIdentifier ?? "com.degiorgi.pinxel"
            scrolling = ScrollCaptureDependencies(accessibility: SystemAccessibilityPermission(),
                                                  makeSource: { ScreenCaptureKitFrameSource(excludingBundleIdentifier: bundle) },
                                                  makeDriver: { CGEventScrollDriver() },
                                                  presenter: ScrollCaptureController(), defaults: .standard)
        }
```

pass `scrolling: scrolling` to `CaptureCoordinator(...)`, and add:

```swift
    func captureScrolling(fromMenu: Bool = false) {
        Task {
            if fromMenu { try? await Task.sleep(for: .milliseconds(250)) }
            await coordinator.captureScrolling()
        }
    }

    /// Rumore deterministico: ogni riga è diversa, così la cucitura è verificabile.
    private static func fakeScrollingContent() -> CGImage {
        let width = 400, height = 1200
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        var state: UInt64 = 42
        for index in stride(from: 0, to: bytes.count, by: 4) {
            for channel in 0..<3 {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                bytes[index + channel] = UInt8(truncatingIfNeeded: state >> 33)
            }
        }
        let ctx = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }
```

If `SettingsStore` does not expose its `UserDefaults`, add `public let defaults: UserDefaults` to it (it is already initialised with one) rather than creating a second suite. Replace the temporary `captureScrolling` stub from Task 5.

In `AppDelegate.applicationDidFinishLaunching`, next to `-PinxelUITestCaptureOnLaunch`:

```swift
        if ProcessInfo.processInfo.arguments.contains("-PinxelUITestScrollOnLaunch") {
            AppEnvironment.shared.captureScrolling()
        }
```

- [ ] **Step 6: Run the UI test**

Run: `xcodegen generate && pkill -x Pinxel; caffeinate -dimsu xcodebuild -project Pinxel.xcodeproj -scheme Pinxel -destination 'platform=macOS' test -only-testing:PinxelUITests/ScrollCaptureUITests`
Expected: `** TEST SUCCEEDED **`; the screenshot shows the noise page 400×1200 in the editor.

- [ ] **Step 7: Manual checklist**

`docs/manual-tests/scrolling.md`:

```markdown
# Checklist manuale — cattura a scorrimento

Prerequisiti: Pinxel firmato (Signing.local.xcconfig), Registrazione schermo concessa. Per S1–S7 anche Accessibilità.

| # | Prova | Risultato atteso |
|---|-------|------------------|
| S1 | Safari, pagina lunga con intestazione fissa: ⌃⇧5, trascina un'area sul contenuto | Pinxel scorre da solo fino in fondo; l'immagine non ha righe doppie né buchi; l'intestazione compare una volta sola |
| S2 | Una chat lunga (Messaggi o WhatsApp) | Come S1; i fumetti non sono tagliati né ripetuti |
| S3 | Mail, un messaggio lungo | Come S1 |
| S4 | Finder in vista elenco con molti file | Righe tutte presenti, nessuna ripetuta (contenuto ripetitivo) |
| S5 | Un PDF in Anteprima | Come S1 |
| S6 | Una pagina quasi tutta bianca | Nessun errore; l'immagine ha la lunghezza giusta |
| S7 | Durante S1 scorri a mano con il trackpad, anche verso l'alto | Pinxel aggiunge ciò che vedi, non duplica nulla, riprende da solo dopo 1 s |
| S8 | Revoca Accessibilità, ripeti S1 | Il pannello dice "Scorri tu"; scorrendo a mano l'immagine cresce; Fine la consegna |
| S9 | Area che occupa tutto lo schermo | Il pannello sta in basso a destra; non compare nell'immagine |
| S10 | Esc durante la cattura | Nessuna immagine, nessuna notifica |
| S11 | Invio o Fine a metà | L'immagine contiene la parte cucita fin lì |
| S12 | Area più bassa di 100 punti | Avviso "Area troppo bassa…", nessuna cattura |
| S13 | Un video in riproduzione nell'area | La cattura si ferma con "Il contenuto cambia da solo"; resta la parte già cucita |
| S14 | "Dopo la cattura" su Solo appunti / Editor / Anteprima rapida | L'immagine lunga segue l'impostazione |
| S15 | Preferenze → Scorciatoie | C'è "Cattura a scorrimento" con ⌃⇧5, modificabile |
```

- [ ] **Step 8: Full verification and commit**

Run: `cd PinxelKit && swift test` → all green (record the count).
Run: `pkill -x Pinxel; caffeinate -dimsu xcodebuild -project Pinxel.xcodeproj -scheme Pinxel -destination 'platform=macOS' test -only-testing:PinxelUITests/ScrollCaptureUITests -only-testing:PinxelUITests/EditorUITests` → `** TEST SUCCEEDED **` (status-item tests may fail when the menu bar item is hidden behind the notch; that is the screen layout, note it).

```bash
git add App/Pinxel/Capture/ScrollCaptureController.swift App/Pinxel/Capture/ScrollCapturePanel.swift App/Pinxel/Capture/CaptureCoordinator.swift App/Pinxel/AppEnvironment.swift App/Pinxel/AppDelegate.swift App/PinxelUITests/ScrollCaptureUITests.swift docs/manual-tests/scrolling.md PinxelKit/Sources/AppCore
git commit -m "feat(app): scrolling capture flow with border, panel and manual checklist"
```
