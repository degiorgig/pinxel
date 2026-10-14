# Pinxel 2 — App and Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn PinxelKit into a working menu-bar app: global hotkeys, screen-recording permission flow, frozen-screen selection overlay (area / window / screen, multi-monitor), window capture, and the post-capture flow (open document, quick preview, clipboard, auto-save).

**Architecture:** Two new PinxelKit targets hold all testable logic: `CaptureKit` (screen geometry, multi-display composition, the selection state machine, the capture-engine protocol with a ScreenCaptureKit implementation and a fake) and `AppCore` (hotkey model, settings, file naming, capture-to-document building, auto-save, post-capture routing). A thin AppKit/SwiftUI app target `Pinxel` (generated with XcodeGen) wires them to the system: Carbon hotkeys, overlay windows, `NSDocument`, quick-preview panel, notifications. Until plan 3 the document window is a read-only viewer.

**Tech Stack:** Swift 6, macOS 15+, Xcode 27, XcodeGen 2.46, SwiftUI (`MenuBarExtra`, `Settings`), AppKit, ScreenCaptureKit, Carbon HIToolbox (`RegisterEventHotKey`), UserNotifications, Swift Testing (package), XCTest/XCUITest (app).

**Spec:** `docs/superpowers/specs/2026-10-14-pinxel-capture-editor-design.md` (sections 2, 4, 7, 10, 11, 12). Builds on plan 1 (`docs/superpowers/plans/2026-10-14-pinxel-1-core.md`), already merged.

## Global Constraints

- Platform floor `macOS 15`; Swift 6 language mode in package and app (`SWIFT_VERSION = 6.0`).
- No third-party runtime dependencies. XcodeGen is a dev-only tool; `Pinxel.xcodeproj` is generated and git-ignored.
- Bundle ID `com.degiorgi.pinxel`; UTI `com.degiorgi.pinxel.document`; extension `.pinxel`; logging subsystem `com.degiorgi.pinxel`.
- `LSUIElement = YES`: agent app, Dock icon only while a document window is open.
- Default hotkeys: `⌃⇧1` area, `⌃⇧2` window, `⌃⇧3` screen, `⌃⇧4` repeat last area, registered with `RegisterEventHotKey` (no Accessibility permission).
- Coordinates: CaptureKit uses CoreGraphics global space (origin top-left of the primary display, points). AppKit (bottom-left) coordinates are converted at the app boundary only.
- Never produce a black capture: no capture starts without `CGPreflightScreenCaptureAccess()`.
- Pinxel's own windows are excluded from snapshots.
- Post-capture: `openEditor` (default) / `quickPreview` (5 s) / `clipboardOnly` (PNG + TIFF); auto-save independent: folder default `~/Pictures/Pinxel`, format `.pinxel` or PNG, name template default `'Pinxel' yyyy-MM-dd 'at' HH.mm.ss`.
- Image size cap from plan 1: `PinxelDocument.maxImageSide` (32768).
- Signing: committed `App/Config/Base.xcconfig` signs ad hoc; a git-ignored `App/Config/Signing.local.xcconfig` supplies `DEVELOPMENT_TEAM` for a stable Apple Development signature (keeps the screen-recording grant across builds). No team IDs in git.
- User-visible strings are Italian.
- Decision (spec §7.2.4 interpretation): releasing the mouse after a drag captures immediately; arrows (`⇧` = 10 px) adjust the dragged corner while the button is held; `Enter` confirms the current drag or captures the window/screen under the pointer; `Esc` cancels; holding `Space` while dragging moves the selection.

## Review Focus

1. **Multi-monitor with different scales and a display above/left of the primary** (negative global coordinates): selection, hit-testing and composition must line up → tests in Task 1 (`appKitConversionHandlesDisplaysAbovePrimary`) and Task 2 (`composesAcrossDisplaysAtMaxScale`, `negativeOriginDisplayComposes`).
2. **A click or tiny drag** (below threshold, zero width, outside every window): no zero-size capture, no crash → tests in Task 3 (`zeroWidthDragProducesNothing`, `windowModeClickOutsideWindowsDoesNothing`).
3. **Auto-save into a missing, read-only or crowded folder**: create missing folders, typed error for unwritable ones, never overwrite an existing file → tests in Task 7 (`createsMissingFolder`, `unwritableFolderThrows`, `neverOverwrites`).
4. **Corrupt or old saved settings / hotkey changes** (garbage JSON in defaults, a combo without modifiers): fall back to defaults, never register a bare key → tests in Task 5 (`bareKeyHasNoModifier`) and Task 6 (`corruptSettingsFallBackToDefaults`).
5. **Capture of a window that closed between snapshot and capture, or permission revoked mid-session**: a notification, no document, no crash → test in Task 8 (`missingWindowThrowsWindowNotFound`) plus manual checklist items M5–M6 in Task 14.

---

## File Structure

```
reatool/
├── project.yml                          XcodeGen project (app + UI tests)
├── App/
│   ├── Config/
│   │   ├── Base.xcconfig                committed: ad-hoc signing, includes local file
│   │   └── Signing.local.xcconfig       git-ignored: DEVELOPMENT_TEAM
│   ├── Pinxel/
│   │   ├── PinxelApp.swift              @main, MenuBarExtra, Settings scene
│   │   ├── AppDelegate.swift            activation policy, launch-time UI-test hooks
│   │   ├── AppEnvironment.swift         wiring: settings, hotkeys, coordinator
│   │   ├── MenuContent.swift
│   │   ├── HotKeyCenter.swift           Carbon hotkeys
│   │   ├── Settings/SettingsView.swift  preferences + ShortcutRecorder
│   │   ├── Capture/CaptureCoordinator.swift
│   │   ├── Capture/SelectionProviders.swift
│   │   ├── Capture/OverlayController.swift
│   │   ├── Capture/SelectionView.swift
│   │   ├── Capture/PermissionWindow.swift
│   │   ├── PostCapture/PostCaptureActions.swift
│   │   ├── PostCapture/QuickPreview.swift
│   │   ├── PostCapture/Clipboard.swift
│   │   ├── PostCapture/Notifier.swift
│   │   └── Document/PinxelFileDocument.swift + ViewerWindowController.swift
│   └── PinxelUITests/CaptureFlowUITests.swift
├── docs/manual-tests/capture.md         manual checklist (real ScreenCaptureKit)
└── PinxelKit/
    ├── Sources/CaptureKit/
    │   ├── ScreenGeometry.swift         DisplayInfo, WindowInfo, conversions, hit tests
    │   ├── CaptureComposer.swift        FrozenDisplay, multi-display composition
    │   ├── SelectionModel.swift         overlay state machine
    │   ├── CaptureEngine.swift          CaptureSnapshot, CaptureEngine, CaptureError, FakeCaptureEngine
    │   ├── ScreenCaptureKitEngine.swift
    │   └── ScreenRecordingPermission.swift
    ├── Sources/AppCore/
    │   ├── KeyCombo.swift
    │   ├── CaptureSettings.swift        settings + SettingsStore
    │   ├── FileNamer.swift
    │   ├── CaptureDocumentBuilder.swift
    │   ├── AutoSaver.swift
    │   └── PostCaptureRouter.swift
    └── Tests/{CaptureKitTests,AppCoreTests}/
```

Package commands run from `/Users/giovanni/work/reatool/PinxelKit`; app commands from `/Users/giovanni/work/reatool`.

---

### Task 1: CaptureKit — screen geometry and hit testing

**Files:**
- Modify: `PinxelKit/Package.swift`
- Create: `PinxelKit/Sources/CaptureKit/ScreenGeometry.swift`
- Test: `PinxelKit/Tests/CaptureKitTests/ScreenGeometryTests.swift`

**Interfaces:**
- Consumes: nothing from earlier plans.
- Produces:
  - `struct DisplayInfo: Equatable, Sendable { let id: UInt32; let frame: CGRect; let scale: Double }` (frame in global top-left points)
  - `struct WindowInfo: Equatable, Sendable, Identifiable { let id: UInt32; let frame: CGRect; let title: String?; let appName: String?; let bundleIdentifier: String? }`
  - `enum ScreenGeometry { static func topLeft(fromAppKit: CGRect, primaryHeight: CGFloat) -> CGRect; static func appKit(fromTopLeft: CGRect, primaryHeight: CGFloat) -> CGRect; static func display(at: CGPoint, in: [DisplayInfo]) -> DisplayInfo?; static func window(at: CGPoint, in: [WindowInfo]) -> WindowInfo? }` — `windows` are ordered front to back.

- [ ] **Step 1: Add the targets**

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
        .library(name: "CaptureKit", targets: ["CaptureKit"]),
        .library(name: "AppCore", targets: ["AppCore"]),
    ],
    targets: [
        .target(name: "DocumentModel"),
        .target(name: "Rendering", dependencies: ["DocumentModel"]),
        .target(name: "Persistence", dependencies: ["DocumentModel", "Rendering"]),
        .target(name: "CaptureKit"),
        .target(name: "AppCore", dependencies: ["DocumentModel", "Rendering", "Persistence"]),
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
        .testTarget(
            name: "CaptureKitTests",
            dependencies: ["CaptureKit", "PinxelTestSupport"]
        ),
        .testTarget(
            name: "AppCoreTests",
            dependencies: ["AppCore", "PinxelTestSupport"]
        ),
    ]
)
```

Create `PinxelKit/Sources/AppCore/AppCore.swift` so the target is not empty until Task 5:

```swift
// Logica dell'app indipendente dall'interfaccia (impostazioni, salvataggio, instradamento).
enum AppCore {}
```

Create `PinxelKit/Tests/AppCoreTests/Placeholder.swift` (removed in Task 5):

```swift
import Testing

struct AppCorePlaceholderTests {
    @Test func targetBuilds() {}
}
```

- [ ] **Step 2: Write the failing tests**

`PinxelKit/Tests/CaptureKitTests/ScreenGeometryTests.swift`:

```swift
import CoreGraphics
import Testing
@testable import CaptureKit

struct ScreenGeometryTests {
    let displays = [
        DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100), scale: 1),
        DisplayInfo(id: 2, frame: CGRect(x: 100, y: 0, width: 100, height: 100), scale: 2),
    ]

    @Test func appKitConversionOfPrimary() {
        let topLeft = ScreenGeometry.topLeft(fromAppKit: CGRect(x: 0, y: 900, width: 100, height: 100), primaryHeight: 1000)
        #expect(topLeft == CGRect(x: 0, y: 0, width: 100, height: 100))
    }

    @Test func appKitConversionHandlesDisplaysAbovePrimary() {
        // Schermo sopra il principale: in AppKit y ≥ altezza del principale, in CG y negativa.
        let rect = CGRect(x: -200, y: 1000, width: 500, height: 300)
        let topLeft = ScreenGeometry.topLeft(fromAppKit: rect, primaryHeight: 1000)
        #expect(topLeft == CGRect(x: -200, y: -300, width: 500, height: 300))
        #expect(ScreenGeometry.appKit(fromTopLeft: topLeft, primaryHeight: 1000) == rect)
    }

    @Test func displayAtPoint() {
        #expect(ScreenGeometry.display(at: CGPoint(x: 150, y: 50), in: displays)?.id == 2)
        #expect(ScreenGeometry.display(at: CGPoint(x: 0, y: 0), in: displays)?.id == 1)
        // Il bordo destro/inferiore dell'ultimo schermo appartiene ancora a quello schermo.
        #expect(ScreenGeometry.display(at: CGPoint(x: 200, y: 100), in: displays)?.id == 2)
        #expect(ScreenGeometry.display(at: CGPoint(x: 500, y: 500), in: displays) == nil)
    }

    @Test func topmostWindowWins() {
        let windows = [
            WindowInfo(id: 10, frame: CGRect(x: 0, y: 0, width: 50, height: 50), title: "Davanti", appName: nil, bundleIdentifier: nil),
            WindowInfo(id: 11, frame: CGRect(x: 0, y: 0, width: 100, height: 100), title: "Dietro", appName: nil, bundleIdentifier: nil),
        ]
        #expect(ScreenGeometry.window(at: CGPoint(x: 10, y: 10), in: windows)?.id == 10)
        #expect(ScreenGeometry.window(at: CGPoint(x: 70, y: 70), in: windows)?.id == 11)
        #expect(ScreenGeometry.window(at: CGPoint(x: 150, y: 150), in: windows) == nil)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter ScreenGeometryTests`
Expected: build FAILS — `Source files for target CaptureKit should be located under 'Sources/CaptureKit'` (no sources yet).

- [ ] **Step 4: Implement**

`PinxelKit/Sources/CaptureKit/ScreenGeometry.swift`:

```swift
import CoreGraphics

/// Uno schermo nello spazio globale di CoreGraphics (origine in alto a sinistra del principale, punti).
public struct DisplayInfo: Equatable, Sendable {
    public let id: UInt32
    public let frame: CGRect
    /// Pixel per punto.
    public let scale: Double

    public init(id: UInt32, frame: CGRect, scale: Double) {
        self.id = id
        self.frame = frame
        self.scale = scale
    }
}

/// Una finestra visibile, con frame nello spazio globale di CoreGraphics.
public struct WindowInfo: Equatable, Sendable, Identifiable {
    public let id: UInt32
    public let frame: CGRect
    public let title: String?
    public let appName: String?
    public let bundleIdentifier: String?

    public init(id: UInt32, frame: CGRect, title: String?, appName: String?, bundleIdentifier: String?) {
        self.id = id
        self.frame = frame
        self.title = title
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
    }
}

public enum ScreenGeometry {
    /// AppKit (origine in basso a sinistra del principale) → CoreGraphics (in alto a sinistra).
    public static func topLeft(fromAppKit rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// La conversione è simmetrica.
    public static func appKit(fromTopLeft rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        topLeft(fromAppKit: rect, primaryHeight: primaryHeight)
    }

    public static func display(at point: CGPoint, in displays: [DisplayInfo]) -> DisplayInfo? {
        if let exact = displays.first(where: { $0.frame.contains(point) }) { return exact }
        // `contains` esclude i bordi destro e inferiore: li assegna allo schermo adiacente.
        return displays.first { $0.frame.insetBy(dx: -1, dy: -1).contains(point) }
    }

    /// `windows` in ordine dalla più in primo piano alla più in fondo.
    public static func window(at point: CGPoint, in windows: [WindowInfo]) -> WindowInfo? {
        windows.first { $0.frame.contains(point) }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter ScreenGeometryTests`
Expected: PASS, 4 tests. Then `swift test`: all plan-1 tests still pass.

- [ ] **Step 6: Commit**

```bash
cd /Users/giovanni/work/reatool
git add PinxelKit
git commit -m "feat(capture): add screen geometry and hit testing"
```

---

### Task 2: CaptureKit — multi-display composition

**Files:**
- Create: `PinxelKit/Sources/CaptureKit/CaptureComposer.swift`
- Test: `PinxelKit/Tests/CaptureKitTests/CaptureComposerTests.swift`

**Interfaces:**
- Consumes: `DisplayInfo`.
- Produces:
  - `struct FrozenDisplay: Sendable { let info: DisplayInfo; let image: CGImage }` (image in native pixels of that display)
  - `enum CaptureComposer { static func compose(_ rect: CGRect, from: [FrozenDisplay]) -> (image: CGImage, scale: Double)? }` — `rect` in global top-left points; result at the max scale of the displays it touches; areas outside every display are transparent; `nil` if `rect` touches no display or is smaller than 1×1 pt.

- [ ] **Step 1: Write the failing tests**

`PinxelKit/Tests/CaptureKitTests/CaptureComposerTests.swift`:

```swift
import CoreGraphics
import Testing
@testable import CaptureKit
import PinxelTestSupport

struct CaptureComposerTests {
    let red = RGBA8(r: 255, g: 0, b: 0)
    let blue = RGBA8(r: 0, g: 0, b: 255)

    var twoDisplays: [FrozenDisplay] {
        [
            FrozenDisplay(info: DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100), scale: 1),
                          image: TestImages.solid(width: 100, height: 100, red: 1, green: 0, blue: 0)),
            FrozenDisplay(info: DisplayInfo(id: 2, frame: CGRect(x: 100, y: 0, width: 100, height: 100), scale: 2),
                          image: TestImages.solid(width: 200, height: 200, red: 0, green: 0, blue: 1)),
        ]
    }

    @Test func singleDisplayIsPixelExact() throws {
        let quadrants = FrozenDisplay(info: DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 400, height: 300), scale: 1), image: TestImages.quadrants())
        let result = try #require(CaptureComposer.compose(CGRect(x: 190, y: 140, width: 20, height: 20), from: [quadrants]))
        #expect(result.scale == 1)
        let pixels = PixelBuffer(result.image)
        #expect(pixels.width == 20 && pixels.height == 20)
        #expect(pixels.pixel(x: 2, y: 2) == red)
        #expect(pixels.pixel(x: 17, y: 2) == RGBA8(r: 0, g: 255, b: 0))
        #expect(pixels.pixel(x: 2, y: 17) == blue)
    }

    @Test func composesAcrossDisplaysAtMaxScale() throws {
        let result = try #require(CaptureComposer.compose(CGRect(x: 50, y: 10, width: 100, height: 50), from: twoDisplays))
        #expect(result.scale == 2)
        let pixels = PixelBuffer(result.image)
        #expect(pixels.width == 200 && pixels.height == 100)
        #expect(pixels.pixel(x: 10, y: 50) == red)
        #expect(pixels.pixel(x: 190, y: 50) == blue)
    }

    @Test func negativeOriginDisplayComposes() throws {
        let above = FrozenDisplay(info: DisplayInfo(id: 3, frame: CGRect(x: -50, y: -100, width: 100, height: 100), scale: 1),
                                  image: TestImages.solid(width: 100, height: 100, red: 0, green: 0, blue: 1))
        let primary = twoDisplays[0]
        let result = try #require(CaptureComposer.compose(CGRect(x: 0, y: -20, width: 40, height: 40), from: [above, primary]))
        let pixels = PixelBuffer(result.image)
        #expect(pixels.pixel(x: 20, y: 5) == blue)
        #expect(pixels.pixel(x: 20, y: 35) == red)
    }

    @Test func gapsBetweenDisplaysAreTransparent() throws {
        let left = twoDisplays[0]
        let farRight = FrozenDisplay(info: DisplayInfo(id: 2, frame: CGRect(x: 200, y: 0, width: 100, height: 100), scale: 1),
                                     image: TestImages.solid(width: 100, height: 100, red: 0, green: 0, blue: 1))
        let result = try #require(CaptureComposer.compose(CGRect(x: 50, y: 0, width: 200, height: 50), from: [left, farRight]))
        #expect(PixelBuffer(result.image).pixel(x: 100, y: 10).a == 0)
    }

    @Test func outsideOrTinyReturnsNil() {
        #expect(CaptureComposer.compose(CGRect(x: 500, y: 500, width: 10, height: 10), from: twoDisplays) == nil)
        #expect(CaptureComposer.compose(CGRect(x: 10, y: 10, width: 0.4, height: 10), from: twoDisplays) == nil)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CaptureComposerTests`
Expected: build FAILS — `cannot find 'FrozenDisplay' in scope`.

- [ ] **Step 3: Implement**

`PinxelKit/Sources/CaptureKit/CaptureComposer.swift`:

```swift
import CoreGraphics

/// Immagine di uno schermo scattata all'avvio della cattura, ai suoi pixel nativi.
public struct FrozenDisplay: Sendable {
    public let info: DisplayInfo
    public let image: CGImage

    public init(info: DisplayInfo, image: CGImage) {
        self.info = info
        self.image = image
    }
}

public enum CaptureComposer {
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// Ritaglia `rect` (punti globali, origine in alto a sinistra) dalle immagini congelate.
    /// Il risultato usa la scala massima tra gli schermi toccati; le zone fuori dagli schermi restano trasparenti.
    public static func compose(_ rect: CGRect, from displays: [FrozenDisplay]) -> (image: CGImage, scale: Double)? {
        let selection = rect.standardized
        guard selection.width >= 1, selection.height >= 1 else { return nil }
        let touched = displays.filter { $0.info.frame.intersects(selection) }
        guard let scale = touched.map(\.info.scale).max() else { return nil }

        let width = Int((selection.width * scale).rounded())
        let height = Int((selection.height * scale).rounded())
        guard width > 0, height > 0,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        // Spazio in punti globali con origine in alto a sinistra della selezione.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: scale, y: -scale)
        ctx.translateBy(x: -selection.minX, y: -selection.minY)
        for display in touched {
            let frame = display.info.frame
            ctx.saveGState()
            ctx.translateBy(x: frame.minX, y: frame.maxY)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(display.image, in: CGRect(origin: .zero, size: frame.size))
            ctx.restoreGState()
        }
        guard let image = ctx.makeImage() else { return nil }
        return (image, scale)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CaptureComposerTests`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
cd /Users/giovanni/work/reatool
git add PinxelKit
git commit -m "feat(capture): compose selections across displays at native scale"
```

---

### Task 3: CaptureKit — selection state machine

**Files:**
- Create: `PinxelKit/Sources/CaptureKit/SelectionModel.swift`
- Test: `PinxelKit/Tests/CaptureKitTests/SelectionModelTests.swift`

**Interfaces:**
- Consumes: `DisplayInfo`, `WindowInfo`, `ScreenGeometry`.
- Produces:
  - `enum CaptureMode: String, Codable, CaseIterable, Sendable { area, window, screen }`
  - `enum SelectionResult: Equatable, Sendable { area(CGRect), window(WindowInfo), screen(DisplayInfo), cancelled }`
  - `enum SelectionKey: Sendable { left, right, up, down, escape, enter }`
  - `struct SelectionModel { init(mode:windows:displays:); enum Phase { hovering, pressed(CGPoint), dragging(anchor: CGPoint, current: CGPoint) }; var phase; var pointer: CGPoint; var selectionRect: CGRect?; var highlightedWindow: WindowInfo?; var highlightedDisplay: DisplayInfo?; mutating func mouseMoved(to:); mouseDown(at:); mouseDragged(to:square:); moveSelection(by: CGSize); mouseUp(at:) -> SelectionResult?; key(_:shift:) -> SelectionResult? }` — all points in global top-left points; `dragThreshold = 3`.

- [ ] **Step 1: Write the failing tests**

`PinxelKit/Tests/CaptureKitTests/SelectionModelTests.swift`:

```swift
import CoreGraphics
import Testing
@testable import CaptureKit

struct SelectionModelTests {
    let displays = [
        DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 400, height: 300), scale: 2),
        DisplayInfo(id: 2, frame: CGRect(x: 400, y: 0, width: 400, height: 300), scale: 1),
    ]
    let window = WindowInfo(id: 7, frame: CGRect(x: 200, y: 100, width: 100, height: 100), title: "Note", appName: "Note", bundleIdentifier: "com.apple.Notes")

    func model(_ mode: CaptureMode) -> SelectionModel {
        SelectionModel(mode: mode, windows: [window], displays: displays)
    }

    @Test func dragCreatesArea() {
        var m = model(.area)
        m.mouseDown(at: CGPoint(x: 10, y: 10))
        m.mouseDragged(to: CGPoint(x: 110, y: 60), square: false)
        #expect(m.selectionRect == CGRect(x: 10, y: 10, width: 100, height: 50))
        #expect(m.mouseUp(at: CGPoint(x: 110, y: 60)) == .area(CGRect(x: 10, y: 10, width: 100, height: 50)))
        #expect(m.phase == .hovering)
    }

    @Test func reverseDragIsNormalized() {
        var m = model(.area)
        m.mouseDown(at: CGPoint(x: 110, y: 60))
        m.mouseDragged(to: CGPoint(x: 10, y: 10), square: false)
        #expect(m.mouseUp(at: CGPoint(x: 10, y: 10)) == .area(CGRect(x: 10, y: 10, width: 100, height: 50)))
    }

    @Test func clickCapturesWindowOrScreen() {
        var m = model(.area)
        m.mouseMoved(to: CGPoint(x: 250, y: 150))
        #expect(m.highlightedWindow == window)
        m.mouseDown(at: CGPoint(x: 250, y: 150))
        m.mouseDragged(to: CGPoint(x: 251, y: 151), square: false) // sotto la soglia
        #expect(m.mouseUp(at: CGPoint(x: 251, y: 151)) == .window(window))

        m.mouseDown(at: CGPoint(x: 500, y: 50))
        #expect(m.mouseUp(at: CGPoint(x: 500, y: 50)) == .screen(displays[1]))
    }

    @Test func zeroWidthDragProducesNothing() {
        var m = model(.area)
        m.mouseDown(at: CGPoint(x: 10, y: 10))
        m.mouseDragged(to: CGPoint(x: 10, y: 40), square: false)
        #expect(m.mouseUp(at: CGPoint(x: 10, y: 40)) == nil)
    }

    @Test func squareLock() {
        var m = model(.area)
        m.mouseDown(at: CGPoint(x: 10, y: 10))
        m.mouseDragged(to: CGPoint(x: 110, y: 40), square: true)
        #expect(m.selectionRect == CGRect(x: 10, y: 10, width: 100, height: 100))
        m.mouseDragged(to: CGPoint(x: -40, y: 0), square: true)
        #expect(m.selectionRect == CGRect(x: -40, y: -40, width: 50, height: 50))
    }

    @Test func spaceMovesSelection() {
        var m = model(.area)
        m.mouseDown(at: CGPoint(x: 10, y: 10))
        m.mouseDragged(to: CGPoint(x: 60, y: 60), square: false)
        m.moveSelection(by: CGSize(width: 5, height: -3))
        #expect(m.selectionRect == CGRect(x: 15, y: 7, width: 50, height: 50))
    }

    @Test func keys() {
        var m = model(.area)
        m.mouseDown(at: CGPoint(x: 10, y: 10))
        m.mouseDragged(to: CGPoint(x: 60, y: 60), square: false)
        #expect(m.key(.right, shift: false) == nil)
        #expect(m.key(.down, shift: true) == nil)
        #expect(m.selectionRect == CGRect(x: 10, y: 10, width: 51, height: 60))
        #expect(m.key(.enter, shift: false) == .area(CGRect(x: 10, y: 10, width: 51, height: 60)))

        var escaped = model(.area)
        #expect(escaped.key(.escape, shift: false) == .cancelled)

        var hovering = model(.area)
        hovering.mouseMoved(to: CGPoint(x: 250, y: 150))
        hovering.key(.left, shift: true).map { _ in Issue.record("arrows must not finish") }
        #expect(hovering.pointer == CGPoint(x: 240, y: 150))
        #expect(hovering.key(.enter, shift: false) == .window(window))
    }

    @Test func windowModeIgnoresDragsAndEmptyClicks() {
        var m = model(.window)
        m.mouseDown(at: CGPoint(x: 10, y: 10))
        m.mouseDragged(to: CGPoint(x: 110, y: 60), square: false)
        #expect(m.selectionRect == nil)
        #expect(m.mouseUp(at: CGPoint(x: 110, y: 60)) == nil)
    }

    @Test func windowModeClickOutsideWindowsDoesNothing() {
        var m = model(.window)
        m.mouseDown(at: CGPoint(x: 10, y: 10))
        #expect(m.mouseUp(at: CGPoint(x: 10, y: 10)) == nil)
        m.mouseDown(at: CGPoint(x: 250, y: 150))
        #expect(m.mouseUp(at: CGPoint(x: 250, y: 150)) == .window(window))
    }

    @Test func screenModeHighlightsAndPicksDisplay() {
        var m = model(.screen)
        m.mouseMoved(to: CGPoint(x: 600, y: 100))
        #expect(m.highlightedDisplay == displays[1])
        #expect(m.highlightedWindow == nil)
        m.mouseDown(at: CGPoint(x: 600, y: 100))
        m.mouseDragged(to: CGPoint(x: 700, y: 200), square: false)
        #expect(m.mouseUp(at: CGPoint(x: 700, y: 200)) == .screen(displays[1]))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SelectionModelTests`
Expected: build FAILS — `cannot find 'SelectionModel' in scope`.

- [ ] **Step 3: Implement**

`PinxelKit/Sources/CaptureKit/SelectionModel.swift`:

```swift
import CoreGraphics

public enum CaptureMode: String, Codable, CaseIterable, Sendable {
    case area, window, screen
}

public enum SelectionResult: Equatable, Sendable {
    case area(CGRect)
    case window(WindowInfo)
    case screen(DisplayInfo)
    case cancelled
}

public enum SelectionKey: Sendable {
    case left, right, up, down, escape, enter
}

/// Stato dell'overlay di selezione, indipendente dalle finestre. Punti globali con origine in alto a sinistra.
public struct SelectionModel: Sendable {
    public enum Phase: Equatable, Sendable {
        case hovering
        case pressed(CGPoint)
        case dragging(anchor: CGPoint, current: CGPoint)
    }

    public static let dragThreshold: CGFloat = 3

    public let mode: CaptureMode
    public private(set) var phase: Phase = .hovering
    public private(set) var pointer: CGPoint = .zero
    private var squareLock = false
    private let windows: [WindowInfo]
    private let displays: [DisplayInfo]

    public init(mode: CaptureMode, windows: [WindowInfo], displays: [DisplayInfo]) {
        self.mode = mode
        self.windows = windows
        self.displays = displays
    }

    public var selectionRect: CGRect? {
        guard case .dragging(let anchor, let current) = phase else { return nil }
        return rect(from: anchor, to: current)
    }

    public var highlightedWindow: WindowInfo? {
        guard mode != .screen, selectionRect == nil else { return nil }
        return ScreenGeometry.window(at: pointer, in: windows)
    }

    public var highlightedDisplay: DisplayInfo? {
        guard mode == .screen else { return nil }
        return ScreenGeometry.display(at: pointer, in: displays)
    }

    public mutating func mouseMoved(to point: CGPoint) {
        pointer = point
    }

    public mutating func mouseDown(at point: CGPoint) {
        pointer = point
        phase = .pressed(point)
    }

    public mutating func mouseDragged(to point: CGPoint, square: Bool) {
        pointer = point
        squareLock = square
        switch phase {
        case .pressed(let anchor):
            let distance = hypot(point.x - anchor.x, point.y - anchor.y)
            if mode == .area, distance >= Self.dragThreshold {
                phase = .dragging(anchor: anchor, current: point)
            }
        case .dragging(let anchor, _):
            phase = .dragging(anchor: anchor, current: point)
        case .hovering:
            break
        }
    }

    /// Sposta l'intera selezione (Spazio tenuto premuto durante il trascinamento).
    public mutating func moveSelection(by delta: CGSize) {
        guard case .dragging(let anchor, let current) = phase else { return }
        phase = .dragging(anchor: anchor.offset(by: delta), current: current.offset(by: delta))
        pointer = pointer.offset(by: delta)
    }

    public mutating func mouseUp(at point: CGPoint) -> SelectionResult? {
        pointer = point
        switch phase {
        case .dragging:
            let rect = selectionRect
            phase = .hovering
            guard let rect, rect.width >= 1, rect.height >= 1 else { return nil }
            return .area(rect)
        case .pressed:
            phase = .hovering
            return clickResult()
        case .hovering:
            return nil
        }
    }

    public mutating func key(_ key: SelectionKey, shift: Bool) -> SelectionResult? {
        let step: CGFloat = shift ? 10 : 1
        let delta: CGSize
        switch key {
        case .escape:
            phase = .hovering
            return .cancelled
        case .enter:
            if let rect = selectionRect {
                phase = .hovering
                return rect.width >= 1 && rect.height >= 1 ? .area(rect) : nil
            }
            return clickResult()
        case .left: delta = CGSize(width: -step, height: 0)
        case .right: delta = CGSize(width: step, height: 0)
        case .up: delta = CGSize(width: 0, height: -step)
        case .down: delta = CGSize(width: 0, height: step)
        }
        if case .dragging(let anchor, let current) = phase {
            phase = .dragging(anchor: anchor, current: current.offset(by: delta))
        }
        pointer = pointer.offset(by: delta)
        return nil
    }

    private func clickResult() -> SelectionResult? {
        switch mode {
        case .area:
            if let window = ScreenGeometry.window(at: pointer, in: windows) { return .window(window) }
            return ScreenGeometry.display(at: pointer, in: displays).map { .screen($0) }
        case .window:
            return ScreenGeometry.window(at: pointer, in: windows).map { .window($0) }
        case .screen:
            return ScreenGeometry.display(at: pointer, in: displays).map { .screen($0) }
        }
    }

    private func rect(from anchor: CGPoint, to current: CGPoint) -> CGRect {
        var width = current.x - anchor.x
        var height = current.y - anchor.y
        if squareLock {
            let side = max(abs(width), abs(height))
            width = width < 0 ? -side : side
            height = height < 0 ? -side : side
        }
        return CGRect(x: anchor.x, y: anchor.y, width: width, height: height).standardized
    }
}

private extension CGPoint {
    func offset(by delta: CGSize) -> CGPoint {
        CGPoint(x: x + delta.width, y: y + delta.height)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SelectionModelTests`
Expected: PASS, 10 tests.

- [ ] **Step 5: Commit**

```bash
cd /Users/giovanni/work/reatool
git add PinxelKit
git commit -m "feat(capture): add selection overlay state machine"
```

---

### Task 4: CaptureKit — capture engine protocol, fake engine, ScreenCaptureKit engine, permission

**Files:**
- Create: `PinxelKit/Sources/CaptureKit/CaptureEngine.swift`
- Create: `PinxelKit/Sources/CaptureKit/ScreenCaptureKitEngine.swift`
- Create: `PinxelKit/Sources/CaptureKit/ScreenRecordingPermission.swift`
- Test: `PinxelKit/Tests/CaptureKitTests/FakeCaptureEngineTests.swift`

**Interfaces:**
- Consumes: `DisplayInfo`, `WindowInfo`, `FrozenDisplay`, `CaptureComposer`, `ScreenGeometry`.
- Produces:
  - `struct CaptureSnapshot: Sendable { let displays: [FrozenDisplay]; let windows: [WindowInfo]; func scale(for: WindowInfo) -> Double }`
  - `enum CaptureError: Error, Equatable { windowNotFound, displayNotFound, emptySelection }`
  - `@MainActor protocol CaptureEngine { func snapshot(excludingBundleIdentifier: String) async throws -> CaptureSnapshot; func captureWindow(_ id: UInt32, includeShadow: Bool) async throws -> CGImage }`
  - `@MainActor final class FakeCaptureEngine: CaptureEngine` — one 800×600 pt display at 2x (blue, red square at 100,100 200×150 pt), one window "Finestra finta" over the red square; `captureWindow(7, …)` returns a red 400×300 image, other IDs throw `windowNotFound`.
  - `@MainActor final class ScreenCaptureKitEngine: CaptureEngine` (real; covered by the manual checklist)
  - `@MainActor protocol ScreenRecordingPermission { var isGranted: Bool { get }; func request(); func openSystemSettings() }`, `SystemScreenRecordingPermission`, `GrantedScreenRecordingPermission`.

- [ ] **Step 1: Write the failing tests**

`PinxelKit/Tests/CaptureKitTests/FakeCaptureEngineTests.swift`:

```swift
import CoreGraphics
import Testing
@testable import CaptureKit
import PinxelTestSupport

@MainActor
struct FakeCaptureEngineTests {
    @Test func snapshotHasDisplayAndWindow() async throws {
        let snapshot = try await FakeCaptureEngine().snapshot(excludingBundleIdentifier: "com.degiorgi.pinxel")
        #expect(snapshot.displays.count == 1)
        #expect(snapshot.displays[0].image.width == 1600)
        #expect(snapshot.windows.map(\.title) == ["Finestra finta"])
        #expect(snapshot.scale(for: snapshot.windows[0]) == 2)
    }

    @Test func fakeAreaComposesRedSquare() async throws {
        let snapshot = try await FakeCaptureEngine().snapshot(excludingBundleIdentifier: "")
        let result = try #require(CaptureComposer.compose(CGRect(x: 100, y: 100, width: 200, height: 150), from: snapshot.displays))
        let pixels = PixelBuffer(result.image)
        #expect(pixels.width == 400 && pixels.height == 300)
        #expect(pixels.pixel(x: 200, y: 150) == RGBA8(r: 255, g: 0, b: 0))
    }

    @Test func missingWindowThrowsWindowNotFound() async {
        await #expect(throws: CaptureError.windowNotFound) {
            try await FakeCaptureEngine().captureWindow(999, includeShadow: true)
        }
    }

    @Test func windowCaptureReturnsImage() async throws {
        let image = try await FakeCaptureEngine().captureWindow(7, includeShadow: false)
        #expect(image.width == 400 && image.height == 300)
    }

    @Test func grantedPermission() {
        #expect(GrantedScreenRecordingPermission().isGranted)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter FakeCaptureEngineTests`
Expected: build FAILS — `cannot find 'FakeCaptureEngine' in scope`.

- [ ] **Step 3: Implement the protocol and the fake**

`PinxelKit/Sources/CaptureKit/CaptureEngine.swift`:

```swift
import CoreGraphics

/// Tutto ciò che serve all'overlay: immagini congelate degli schermi e finestre visibili (dalla più in primo piano).
public struct CaptureSnapshot: Sendable {
    public let displays: [FrozenDisplay]
    public let windows: [WindowInfo]

    public init(displays: [FrozenDisplay], windows: [WindowInfo]) {
        self.displays = displays
        self.windows = windows
    }

    /// Scala dello schermo che contiene il centro della finestra.
    public func scale(for window: WindowInfo) -> Double {
        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        return ScreenGeometry.display(at: center, in: displays.map(\.info))?.scale
            ?? displays.map(\.info.scale).max() ?? 1
    }
}

public enum CaptureError: Error, Equatable {
    case windowNotFound
    case displayNotFound
    case emptySelection
}

@MainActor
public protocol CaptureEngine {
    func snapshot(excludingBundleIdentifier bundleIdentifier: String) async throws -> CaptureSnapshot
    func captureWindow(_ id: UInt32, includeShadow: Bool) async throws -> CGImage
}

/// Motore deterministico per test e UI test: uno schermo blu 800×600 pt a 2x con un quadrato rosso.
@MainActor
public final class FakeCaptureEngine: CaptureEngine {
    public static let windowID: UInt32 = 7
    public static let redSquare = CGRect(x: 100, y: 100, width: 200, height: 150)

    public init() {}

    public func snapshot(excludingBundleIdentifier bundleIdentifier: String) async throws -> CaptureSnapshot {
        let info = DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 800, height: 600), scale: 2)
        let window = WindowInfo(id: Self.windowID, frame: Self.redSquare, title: "Finestra finta", appName: "Finta", bundleIdentifier: "com.example.fake")
        return CaptureSnapshot(displays: [FrozenDisplay(info: info, image: Self.makeScreen())], windows: [window])
    }

    public func captureWindow(_ id: UInt32, includeShadow: Bool) async throws -> CGImage {
        guard id == Self.windowID else { throw CaptureError.windowNotFound }
        return Self.solid(width: 400, height: 300, red: 1, green: 0, blue: 0)
    }

    private static func makeScreen() -> CGImage {
        let ctx = context(width: 1600, height: 1200)
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 1600, height: 1200))
        // Il contesto ha origine in basso a sinistra: converto il quadrato (punti, in alto a sinistra) in pixel.
        let square = CGRect(x: redSquare.minX * 2, y: 1200 - redSquare.maxY * 2, width: redSquare.width * 2, height: redSquare.height * 2)
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(square)
        return ctx.makeImage()!
    }

    private static func solid(width: Int, height: Int, red: CGFloat, green: CGFloat, blue: CGFloat) -> CGImage {
        let ctx = context(width: width, height: height)
        ctx.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    private static func context(width: Int, height: Int) -> CGContext {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CaptureComposer.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }
}
```

- [ ] **Step 4: Implement permission and the real engine**

`PinxelKit/Sources/CaptureKit/ScreenRecordingPermission.swift`:

```swift
import AppKit
import CoreGraphics

@MainActor
public protocol ScreenRecordingPermission {
    var isGranted: Bool { get }
    func request()
    func openSystemSettings()
}

@MainActor
public struct SystemScreenRecordingPermission: ScreenRecordingPermission {
    public init() {}

    public var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    public func request() {
        _ = CGRequestScreenCaptureAccess()
    }

    public func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Per test e UI test.
@MainActor
public struct GrantedScreenRecordingPermission: ScreenRecordingPermission {
    public init() {}
    public var isGranted: Bool { true }
    public func request() {}
    public func openSystemSettings() {}
}
```

`PinxelKit/Sources/CaptureKit/ScreenCaptureKitEngine.swift`:

```swift
import CoreGraphics
@preconcurrency import ScreenCaptureKit

/// Cattura reale con ScreenCaptureKit. Verificata dalla checklist manuale (docs/manual-tests/capture.md).
@MainActor
public final class ScreenCaptureKitEngine: CaptureEngine {
    public init() {}

    public func snapshot(excludingBundleIdentifier bundleIdentifier: String) async throws -> CaptureSnapshot {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let ownWindows = content.windows.filter { $0.owningApplication?.bundleIdentifier == bundleIdentifier }

        var displays: [FrozenDisplay] = []
        for display in content.displays {
            let filter = SCContentFilter(display: display, excludingWindows: ownWindows)
            let scale = Double(filter.pointPixelScale)
            let configuration = SCStreamConfiguration()
            configuration.width = Int((Double(display.width) * scale).rounded())
            configuration.height = Int((Double(display.height) * scale).rounded())
            configuration.showsCursor = false
            configuration.captureResolution = .best
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            displays.append(FrozenDisplay(info: DisplayInfo(id: display.displayID, frame: display.frame, scale: scale), image: image))
        }

        let rank = Dictionary(Self.frontToBackWindowIDs().enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let windows = content.windows
            .filter { window in
                window.isOnScreen && window.windowLayer == 0
                    && window.frame.width > 1 && window.frame.height > 1
                    && window.owningApplication?.bundleIdentifier != bundleIdentifier
            }
            .sorted { (rank[$0.windowID] ?? .max) < (rank[$1.windowID] ?? .max) }
            .map { window in
                WindowInfo(
                    id: window.windowID, frame: window.frame, title: window.title,
                    appName: window.owningApplication?.applicationName,
                    bundleIdentifier: window.owningApplication?.bundleIdentifier
                )
            }
        return CaptureSnapshot(displays: displays, windows: windows)
    }

    public func captureWindow(_ id: UInt32, includeShadow: Bool) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == id }) else { throw CaptureError.windowNotFound }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = Double(filter.pointPixelScale)
        let configuration = SCStreamConfiguration()
        configuration.width = Int((filter.contentRect.width * scale).rounded())
        configuration.height = Int((filter.contentRect.height * scale).rounded())
        configuration.showsCursor = false
        configuration.captureResolution = .best
        configuration.ignoreShadowsSingleWindow = !includeShadow
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    /// ID delle finestre sullo schermo, dalla più in primo piano.
    static func frontToBackWindowIDs() -> [UInt32] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return list.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter FakeCaptureEngineTests`
Expected: PASS, 5 tests. Also `swift build` must compile `ScreenCaptureKitEngine` without errors (warnings about deprecated `CGWindowListCopyWindowInfo` are acceptable; record them in the ledger).

- [ ] **Step 6: Commit**

```bash
cd /Users/giovanni/work/reatool
git add PinxelKit
git commit -m "feat(capture): add capture engine protocol, fake and ScreenCaptureKit engines"
```

---

### Task 5: AppCore — key combinations

**Files:**
- Create: `PinxelKit/Sources/AppCore/KeyCombo.swift`
- Delete: `PinxelKit/Tests/AppCoreTests/Placeholder.swift`
- Test: `PinxelKit/Tests/AppCoreTests/KeyComboTests.swift`

**Interfaces:**
- Produces:
  - `struct KeyCombo: Codable, Hashable, Sendable { var keyCode: UInt32; var modifiers: UInt32 /* Carbon */; var hasModifier: Bool; var displayString: String; static func carbonModifiers(fromCocoa: UInt) -> UInt32 }` with constants `KeyCombo.control/option/shift/command` (Carbon masks 0x1000/0x0800/0x0200/0x0100).
  - `enum HotKeyAction: String, Codable, CaseIterable, Sendable { area, window, screen, repeatLastArea; var title: String; var defaultCombo: KeyCombo }`

- [ ] **Step 1: Write the failing tests**

Delete `PinxelKit/Tests/AppCoreTests/Placeholder.swift`. Create `PinxelKit/Tests/AppCoreTests/KeyComboTests.swift`:

```swift
import Foundation
import Testing
@testable import AppCore

struct KeyComboTests {
    @Test func defaultsAreControlShiftDigits() {
        #expect(HotKeyAction.area.defaultCombo.displayString == "⌃⇧1")
        #expect(HotKeyAction.window.defaultCombo.displayString == "⌃⇧2")
        #expect(HotKeyAction.screen.defaultCombo.displayString == "⌃⇧3")
        #expect(HotKeyAction.repeatLastArea.defaultCombo.displayString == "⌃⇧4")
    }

    @Test func modifierGlyphOrder() {
        let combo = KeyCombo(keyCode: 0x00, modifiers: KeyCombo.command | KeyCombo.shift | KeyCombo.option | KeyCombo.control)
        #expect(combo.displayString == "⌃⌥⇧⌘A")
        #expect(KeyCombo(keyCode: 0x7A, modifiers: KeyCombo.command).displayString == "⌘F1")
        #expect(KeyCombo(keyCode: 0x31, modifiers: KeyCombo.option).displayString == "⌥Spazio")
        #expect(KeyCombo(keyCode: 0x5A, modifiers: KeyCombo.control).displayString == "⌃Tasto 90")
    }

    @Test func cocoaFlagsMapToCarbon() {
        let cocoa: UInt = (1 << 18) | (1 << 17) // control + shift
        #expect(KeyCombo.carbonModifiers(fromCocoa: cocoa) == KeyCombo.control | KeyCombo.shift)
        let all: UInt = (1 << 17) | (1 << 18) | (1 << 19) | (1 << 20) | (1 << 16) // + caps lock (ignorato)
        #expect(KeyCombo.carbonModifiers(fromCocoa: all) == KeyCombo.control | KeyCombo.shift | KeyCombo.option | KeyCombo.command)
    }

    @Test func bareKeyHasNoModifier() {
        #expect(!KeyCombo(keyCode: 0x12, modifiers: 0).hasModifier)
        #expect(KeyCombo(keyCode: 0x12, modifiers: KeyCombo.shift).hasModifier)
    }

    @Test func codableRoundTrip() throws {
        let combo = HotKeyAction.screen.defaultCombo
        let decoded = try JSONDecoder().decode(KeyCombo.self, from: JSONEncoder().encode(combo))
        #expect(decoded == combo)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter KeyComboTests`
Expected: build FAILS — `cannot find 'HotKeyAction' in scope`.

- [ ] **Step 3: Implement**

`PinxelKit/Sources/AppCore/KeyCombo.swift`:

```swift
import Foundation

/// Combinazione di tasti per le scorciatoie globali (codice tasto + modificatori Carbon).
public struct KeyCombo: Codable, Hashable, Sendable {
    public static let control: UInt32 = 0x1000
    public static let option: UInt32 = 0x0800
    public static let shift: UInt32 = 0x0200
    public static let command: UInt32 = 0x0100

    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Una scorciatoia globale senza modificatori ruberebbe il tasto a tutte le app.
    public var hasModifier: Bool {
        modifiers & (Self.control | Self.option | Self.shift | Self.command) != 0
    }

    public var displayString: String {
        var text = ""
        if modifiers & Self.control != 0 { text += "⌃" }
        if modifiers & Self.option != 0 { text += "⌥" }
        if modifiers & Self.shift != 0 { text += "⇧" }
        if modifiers & Self.command != 0 { text += "⌘" }
        return text + (Self.keyNames[keyCode] ?? "Tasto \(keyCode)")
    }

    /// Da `NSEvent.ModifierFlags.rawValue` ai modificatori Carbon.
    public static func carbonModifiers(fromCocoa flags: UInt) -> UInt32 {
        var result: UInt32 = 0
        if flags & (1 << 18) != 0 { result |= control }
        if flags & (1 << 19) != 0 { result |= option }
        if flags & (1 << 17) != 0 { result |= shift }
        if flags & (1 << 20) != 0 { result |= command }
        return result
    }

    static let keyNames: [UInt32: String] = [
        0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H", 0x05: "G", 0x06: "Z", 0x07: "X",
        0x08: "C", 0x09: "V", 0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R", 0x10: "Y",
        0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x16: "6", 0x17: "5", 0x19: "9",
        0x1A: "7", 0x1C: "8", 0x1D: "0", 0x1F: "O", 0x20: "U", 0x22: "I", 0x23: "P", 0x25: "L",
        0x26: "J", 0x28: "K", 0x2D: "N", 0x2E: "M", 0x31: "Spazio",
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5", 0x61: "F6",
        0x62: "F7", 0x64: "F8", 0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
    ]
}

public enum HotKeyAction: String, Codable, CaseIterable, Sendable {
    case area, window, screen, repeatLastArea

    public var title: String {
        switch self {
        case .area: "Cattura area"
        case .window: "Cattura finestra"
        case .screen: "Cattura schermo"
        case .repeatLastArea: "Ripeti ultima area"
        }
    }

    public var defaultCombo: KeyCombo {
        let modifiers = KeyCombo.control | KeyCombo.shift
        switch self {
        case .area: return KeyCombo(keyCode: 0x12, modifiers: modifiers)
        case .window: return KeyCombo(keyCode: 0x13, modifiers: modifiers)
        case .screen: return KeyCombo(keyCode: 0x14, modifiers: modifiers)
        case .repeatLastArea: return KeyCombo(keyCode: 0x15, modifiers: modifiers)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter KeyComboTests`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
cd /Users/giovanni/work/reatool
git add -A PinxelKit
git commit -m "feat(app-core): add key combinations and hotkey actions"
```

---

### Task 6: AppCore — settings and file naming

**Files:**
- Create: `PinxelKit/Sources/AppCore/CaptureSettings.swift`
- Create: `PinxelKit/Sources/AppCore/FileNamer.swift`
- Test: `PinxelKit/Tests/AppCoreTests/SettingsTests.swift`
- Test: `PinxelKit/Tests/AppCoreTests/FileNamerTests.swift`

**Interfaces:**
- Consumes: `KeyCombo`, `HotKeyAction`.
- Produces:
  - `enum PostCaptureAction: String, Codable, CaseIterable, Sendable { openEditor, quickPreview, clipboardOnly; var title: String }`
  - `enum SaveFormat: String, Codable, CaseIterable, Sendable { pinxel, png; var fileExtension: String }`
  - `struct CaptureSettings: Codable, Equatable, Sendable { postCaptureAction = .openEditor; autoSave = false; saveFolderPath: String (default "~/Pictures/Pinxel"); saveFormat = .pinxel; fileNameTemplate = FileNamer.defaultTemplate; includeWindowShadow = true; hotKeys: [HotKeyAction: KeyCombo] (defaults); var saveFolderURL: URL; func combo(for: HotKeyAction) -> KeyCombo }`
  - `struct SettingsStore { init(defaults: UserDefaults); func load() -> CaptureSettings; func save(_:) }` (key `"PinxelCaptureSettings"`)
  - `enum FileNamer { static let defaultTemplate = "'Pinxel' yyyy-MM-dd 'at' HH.mm.ss"; static func baseName(template:date:timeZone:) -> String; static func uniqueURL(in:baseName:fileExtension:fileManager:) -> URL }`

- [ ] **Step 1: Write the failing tests**

`PinxelKit/Tests/AppCoreTests/SettingsTests.swift`:

```swift
import Foundation
import Testing
@testable import AppCore

struct SettingsTests {
    func freshDefaults() -> UserDefaults {
        let name = "PinxelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func defaultsWhenEmpty() {
        let settings = SettingsStore(defaults: freshDefaults()).load()
        #expect(settings == CaptureSettings())
        #expect(settings.postCaptureAction == .openEditor)
        #expect(!settings.autoSave)
        #expect(settings.saveFormat == .pinxel)
        #expect(settings.combo(for: .area).displayString == "⌃⇧1")
        #expect(settings.saveFolderURL.path.hasSuffix("/Pictures/Pinxel"))
        #expect(!settings.saveFolderURL.path.contains("~"))
    }

    @Test func saveAndLoadRoundTrip() {
        let store = SettingsStore(defaults: freshDefaults())
        var settings = CaptureSettings()
        settings.postCaptureAction = .quickPreview
        settings.autoSave = true
        settings.saveFormat = .png
        settings.saveFolderPath = "/tmp/pinxel-out"
        settings.hotKeys[.window] = KeyCombo(keyCode: 0x0D, modifiers: KeyCombo.command | KeyCombo.option)
        store.save(settings)
        #expect(store.load() == settings)
    }

    @Test func corruptSettingsFallBackToDefaults() {
        let defaults = freshDefaults()
        defaults.set(Data("{not json".utf8), forKey: SettingsStore.key)
        #expect(SettingsStore(defaults: defaults).load() == CaptureSettings())
        defaults.set("a string", forKey: SettingsStore.key)
        #expect(SettingsStore(defaults: defaults).load() == CaptureSettings())
    }

    @Test func missingHotKeyFallsBackToDefault() {
        var settings = CaptureSettings()
        settings.hotKeys = [:]
        #expect(settings.combo(for: .screen) == HotKeyAction.screen.defaultCombo)
    }
}
```

`PinxelKit/Tests/AppCoreTests/FileNamerTests.swift`:

```swift
import Foundation
import Testing
@testable import AppCore

struct FileNamerTests {
    let date: Date = {
        var components = DateComponents(year: 2026, month: 10, day: 14, hour: 15, minute: 42, second: 10)
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }()

    @Test func defaultTemplate() {
        #expect(FileNamer.baseName(template: FileNamer.defaultTemplate, date: date, timeZone: TimeZone(identifier: "UTC")!)
            == "Pinxel 2026-10-14 at 15.42.10")
    }

    @Test func unsafeCharactersAreReplaced() {
        #expect(FileNamer.baseName(template: "yyyy/MM/dd HH:mm", date: date, timeZone: TimeZone(identifier: "UTC")!)
            == "2026-10-14 15-42")
        #expect(FileNamer.baseName(template: "''", date: date, timeZone: TimeZone(identifier: "UTC")!) == "Pinxel")
    }

    @Test func uniqueURLAppendsCounter() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pinxel-names-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = FileNamer.uniqueURL(in: folder, baseName: "Cattura", fileExtension: "png")
        #expect(first.lastPathComponent == "Cattura.png")
        try Data().write(to: first)
        let second = FileNamer.uniqueURL(in: folder, baseName: "Cattura", fileExtension: "png")
        #expect(second.lastPathComponent == "Cattura 2.png")
        try Data().write(to: second)
        #expect(FileNamer.uniqueURL(in: folder, baseName: "Cattura", fileExtension: "png").lastPathComponent == "Cattura 3.png")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "SettingsTests|FileNamerTests"`
Expected: build FAILS — `cannot find 'SettingsStore' in scope`.

- [ ] **Step 3: Implement**

`PinxelKit/Sources/AppCore/FileNamer.swift`:

```swift
import Foundation

public enum FileNamer {
    /// Modello `DateFormatter`: il testo fisso va tra apici.
    public static let defaultTemplate = "'Pinxel' yyyy-MM-dd 'at' HH.mm.ss"

    public static func baseName(template: String, date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = template
        let name = formatter.string(from: date)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Pinxel" : name
    }

    /// Primo URL libero: "Nome.ext", poi "Nome 2.ext", "Nome 3.ext"…
    public static func uniqueURL(in folder: URL, baseName: String, fileExtension: String, fileManager: FileManager = .default) -> URL {
        var candidate = folder.appendingPathComponent(baseName).appendingPathExtension(fileExtension)
        var counter = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(baseName) \(counter)").appendingPathExtension(fileExtension)
            counter += 1
        }
        return candidate
    }
}
```

`PinxelKit/Sources/AppCore/CaptureSettings.swift`:

```swift
import Foundation

public enum PostCaptureAction: String, Codable, CaseIterable, Sendable {
    case openEditor, quickPreview, clipboardOnly

    public var title: String {
        switch self {
        case .openEditor: "Apri l'editor"
        case .quickPreview: "Anteprima veloce"
        case .clipboardOnly: "Solo appunti"
        }
    }
}

public enum SaveFormat: String, Codable, CaseIterable, Sendable {
    case pinxel, png

    public var fileExtension: String { rawValue }
}

public struct CaptureSettings: Codable, Equatable, Sendable {
    public var postCaptureAction: PostCaptureAction = .openEditor
    public var autoSave = false
    public var saveFolderPath = "~/Pictures/Pinxel"
    public var saveFormat: SaveFormat = .pinxel
    public var fileNameTemplate = FileNamer.defaultTemplate
    public var includeWindowShadow = true
    public var hotKeys: [HotKeyAction: KeyCombo] = Dictionary(uniqueKeysWithValues: HotKeyAction.allCases.map { ($0, $0.defaultCombo) })

    public init() {}

    public var saveFolderURL: URL {
        URL(fileURLWithPath: (saveFolderPath as NSString).expandingTildeInPath, isDirectory: true)
    }

    public func combo(for action: HotKeyAction) -> KeyCombo {
        hotKeys[action] ?? action.defaultCombo
    }
}

/// Persistenza delle impostazioni in `UserDefaults` come JSON; dati illeggibili → valori predefiniti.
public struct SettingsStore {
    public static let key = "PinxelCaptureSettings"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> CaptureSettings {
        guard let data = defaults.data(forKey: Self.key),
              let settings = try? JSONDecoder().decode(CaptureSettings.self, from: data) else {
            return CaptureSettings()
        }
        return settings
    }

    public func save(_ settings: CaptureSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter "SettingsTests|FileNamerTests"`
Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
cd /Users/giovanni/work/reatool
git add PinxelKit
git commit -m "feat(app-core): add capture settings and file naming"
```

---

### Task 7: AppCore — capture documents, auto-save and post-capture routing

**Files:**
- Modify: `PinxelKit/Sources/Persistence/PinxelArchive.swift` (public initializer for `PinxelFileContents`)
- Create: `PinxelKit/Sources/AppCore/CaptureDocumentBuilder.swift`
- Create: `PinxelKit/Sources/AppCore/AutoSaver.swift`
- Create: `PinxelKit/Sources/AppCore/PostCaptureRouter.swift`
- Test: `PinxelKit/Tests/AppCoreTests/CaptureDocumentTests.swift`
- Test: `PinxelKit/Tests/AppCoreTests/AutoSaverTests.swift`
- Test: `PinxelKit/Tests/AppCoreTests/PostCaptureRouterTests.swift`

**Interfaces:**
- Consumes: `PinxelDocument`, `CaptureMetadata`, `ImageCodec`, `PinxelArchive`, `PinxelFileContents`, `Thumbnailer`, `DocumentRenderer`, `CaptureSettings`, `FileNamer`.
- Produces:
  - `PinxelFileContents.init(document:images:thumbnail:isReadOnly:)` (public)
  - `enum CaptureDocumentBuilder { static func make(image: CGImage, scale: Double, metadata: CaptureMetadata) throws -> PinxelFileContents }`
  - `enum AutoSaveError: Error, Equatable { folderNotWritable(String), writeFailed(String) }`
  - `struct AutoSaver { init(fileManager: = .default, appVersion: String = "0.1.0"); func save(_ contents: PinxelFileContents, settings: CaptureSettings, date: Date) throws -> URL }`
  - `enum PostCaptureStep: Equatable, Sendable { openEditor, copyToClipboard, autoSave }`
  - `struct PostCapturePlan: Equatable, Sendable { var immediate: [PostCaptureStep]; var showsQuickPreview: Bool; var afterPreview: [PostCaptureStep] }`
  - `enum PostCaptureRouter { static func plan(for: CaptureSettings) -> PostCapturePlan }`

- [ ] **Step 1: Write the failing tests**

`PinxelKit/Tests/AppCoreTests/CaptureDocumentTests.swift`:

```swift
import Foundation
import Testing
import DocumentModel
import Persistence
@testable import AppCore
import PinxelTestSupport

struct CaptureDocumentTests {
    @Test func buildsDocumentFromCapture() throws {
        let metadata = CaptureMetadata(captureDate: Date(timeIntervalSinceReferenceDate: 1000), appName: "Safari", bundleIdentifier: "com.apple.Safari", windowTitle: "Apple")
        let contents = try CaptureDocumentBuilder.make(image: TestImages.quadrants(), scale: 2, metadata: metadata)
        #expect(contents.document.canvasSize == PixelSize(width: 400, height: 300))
        #expect(contents.document.scale == 2)
        #expect(contents.document.annotations.isEmpty)
        #expect(contents.document.metadata == metadata)
        #expect(contents.document.background == ImageAssetRef(name: "background.png"))
        #expect(contents.document.validationError() == nil)
        let decoded = try #require(contents.assetProvider().image(for: contents.document.background))
        #expect(decoded.width == 400)

        let reread = try PinxelArchive.read(PinxelArchive.write(document: contents.document, images: contents.images, thumbnail: Data(), appVersion: "0.1.0"))
        #expect(reread.document == contents.document)
    }
}
```

`PinxelKit/Tests/AppCoreTests/AutoSaverTests.swift`:

```swift
import Foundation
import Testing
import DocumentModel
import Persistence
@testable import AppCore
import PinxelTestSupport

struct AutoSaverTests {
    let date = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func temporaryFolder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("pinxel-autosave-\(UUID().uuidString)")
    }

    func contents() throws -> PinxelFileContents {
        try CaptureDocumentBuilder.make(image: TestImages.quadrants(), scale: 2, metadata: CaptureMetadata(captureDate: date))
    }

    func settings(folder: URL, format: SaveFormat) -> CaptureSettings {
        var settings = CaptureSettings()
        settings.autoSave = true
        settings.saveFolderPath = folder.path
        settings.saveFormat = format
        settings.fileNameTemplate = "'Test' yyyy"
        return settings
    }

    @Test func savesPinxel() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try AutoSaver().save(contents(), settings: settings(folder: folder, format: .pinxel), date: date)
        #expect(url.pathExtension == "pinxel")
        #expect(url.lastPathComponent.hasPrefix("Test "))
        let reread = try PinxelArchive.read(Data(contentsOf: url))
        #expect(reread.document.canvasSize == PixelSize(width: 400, height: 300))
    }

    @Test func savesPNGAtNativePixels() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try AutoSaver().save(contents(), settings: settings(folder: folder, format: .png), date: date)
        let image = try ImageCodec.decode(Data(contentsOf: url))
        #expect(image.width == 400 && image.height == 300)
    }

    @Test func createsMissingFolder() throws {
        let folder = temporaryFolder().appendingPathComponent("nested/deeper")
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent().deletingLastPathComponent()) }
        let url = try AutoSaver().save(contents(), settings: settings(folder: folder, format: .png), date: date)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func unwritableFolderThrows() throws {
        let folder = temporaryFolder()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: folder.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
            try? FileManager.default.removeItem(at: folder)
        }
        #expect(throws: AutoSaveError.folderNotWritable(folder.path)) {
            try AutoSaver().save(contents(), settings: settings(folder: folder, format: .png), date: date)
        }
    }

    @Test func neverOverwrites() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let saver = AutoSaver()
        let first = try saver.save(contents(), settings: settings(folder: folder, format: .png), date: date)
        let second = try saver.save(contents(), settings: settings(folder: folder, format: .png), date: date)
        #expect(first != second)
        #expect(FileManager.default.fileExists(atPath: first.path))
        #expect(FileManager.default.fileExists(atPath: second.path))
    }
}
```

`PinxelKit/Tests/AppCoreTests/PostCaptureRouterTests.swift`:

```swift
import Testing
@testable import AppCore

struct PostCaptureRouterTests {
    func settings(_ action: PostCaptureAction, autoSave: Bool) -> CaptureSettings {
        var settings = CaptureSettings()
        settings.postCaptureAction = action
        settings.autoSave = autoSave
        return settings
    }

    @Test func editor() {
        #expect(PostCaptureRouter.plan(for: settings(.openEditor, autoSave: false))
            == PostCapturePlan(immediate: [.openEditor], showsQuickPreview: false, afterPreview: []))
        #expect(PostCaptureRouter.plan(for: settings(.openEditor, autoSave: true))
            == PostCapturePlan(immediate: [.autoSave, .openEditor], showsQuickPreview: false, afterPreview: []))
    }

    @Test func quickPreviewSavesWhenItExpires() {
        #expect(PostCaptureRouter.plan(for: settings(.quickPreview, autoSave: true))
            == PostCapturePlan(immediate: [], showsQuickPreview: true, afterPreview: [.autoSave]))
        #expect(PostCaptureRouter.plan(for: settings(.quickPreview, autoSave: false))
            == PostCapturePlan(immediate: [], showsQuickPreview: true, afterPreview: []))
    }

    @Test func clipboard() {
        #expect(PostCaptureRouter.plan(for: settings(.clipboardOnly, autoSave: false))
            == PostCapturePlan(immediate: [.copyToClipboard], showsQuickPreview: false, afterPreview: []))
        #expect(PostCaptureRouter.plan(for: settings(.clipboardOnly, autoSave: true))
            == PostCapturePlan(immediate: [.copyToClipboard, .autoSave], showsQuickPreview: false, afterPreview: []))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "CaptureDocumentTests|AutoSaverTests|PostCaptureRouterTests"`
Expected: build FAILS — `cannot find 'CaptureDocumentBuilder' in scope`.

- [ ] **Step 3: Add the public initializer to `PinxelFileContents`**

In `PinxelKit/Sources/Persistence/PinxelArchive.swift`, inside `public struct PinxelFileContents`, after `public var isReadOnly: Bool`, add:

```swift

    public init(document: PinxelDocument, images: [ImageAssetRef: Data], thumbnail: Data? = nil, isReadOnly: Bool = false) {
        self.document = document
        self.images = images
        self.thumbnail = thumbnail
        self.isReadOnly = isReadOnly
    }
```

- [ ] **Step 4: Implement builder, auto-saver and router**

`PinxelKit/Sources/AppCore/CaptureDocumentBuilder.swift`:

```swift
import CoreGraphics
import DocumentModel
import Persistence

public enum CaptureDocumentBuilder {
    /// Nuovo documento senza annotazioni con la cattura come sfondo.
    public static func make(image: CGImage, scale: Double, metadata: CaptureMetadata) throws -> PinxelFileContents {
        let (ref, data) = try ImageCodec.encodeBackground(image)
        let document = PinxelDocument(
            background: ref,
            canvasSize: PixelSize(width: image.width, height: image.height),
            scale: scale,
            metadata: metadata
        )
        return PinxelFileContents(document: document, images: [ref: data])
    }
}
```

`PinxelKit/Sources/AppCore/AutoSaver.swift`:

```swift
import DocumentModel
import Foundation
import Persistence
import Rendering
import UniformTypeIdentifiers

public enum AutoSaveError: Error, Equatable {
    case folderNotWritable(String)
    case writeFailed(String)
}

public struct AutoSaver {
    private let fileManager: FileManager
    private let appVersion: String

    public init(fileManager: FileManager = .default, appVersion: String = "0.1.0") {
        self.fileManager = fileManager
        self.appVersion = appVersion
    }

    /// Scrive la cattura nella cartella delle impostazioni senza mai sovrascrivere file esistenti.
    public func save(_ contents: PinxelFileContents, settings: CaptureSettings, date: Date) throws -> URL {
        let folder = settings.saveFolderURL
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw AutoSaveError.folderNotWritable(folder.path)
        }
        guard fileManager.isWritableFile(atPath: folder.path) else { throw AutoSaveError.folderNotWritable(folder.path) }

        let baseName = FileNamer.baseName(template: settings.fileNameTemplate, date: date)
        let url = FileNamer.uniqueURL(in: folder, baseName: baseName, fileExtension: settings.saveFormat.fileExtension, fileManager: fileManager)
        let data: Data
        do {
            let assets = try contents.assetProvider()
            switch settings.saveFormat {
            case .pinxel:
                let thumbnail = try Thumbnailer.make(contents.document, assets: assets)
                data = try PinxelArchive.write(document: contents.document, images: contents.images, thumbnail: thumbnail, appVersion: appVersion)
            case .png:
                let image = try DocumentRenderer().renderImage(contents.document, assets: assets)
                data = try ImageCodec.encode(image, type: .png)
            }
            // `.withoutOverwriting`: se nel frattempo il file è comparso, fallisce invece di sovrascrivere.
            try data.write(to: url, options: [.atomic, .withoutOverwriting])
        } catch {
            throw AutoSaveError.writeFailed(url.path)
        }
        return url
    }
}
```

`PinxelKit/Sources/AppCore/PostCaptureRouter.swift`:

```swift
public enum PostCaptureStep: Equatable, Sendable {
    case openEditor
    case copyToClipboard
    case autoSave
}

public struct PostCapturePlan: Equatable, Sendable {
    public var immediate: [PostCaptureStep]
    public var showsQuickPreview: Bool
    /// Passi eseguiti quando l'anteprima veloce scade senza essere aperta.
    public var afterPreview: [PostCaptureStep]

    public init(immediate: [PostCaptureStep], showsQuickPreview: Bool, afterPreview: [PostCaptureStep]) {
        self.immediate = immediate
        self.showsQuickPreview = showsQuickPreview
        self.afterPreview = afterPreview
    }
}

public enum PostCaptureRouter {
    public static func plan(for settings: CaptureSettings) -> PostCapturePlan {
        let save: [PostCaptureStep] = settings.autoSave ? [.autoSave] : []
        switch settings.postCaptureAction {
        case .openEditor:
            return PostCapturePlan(immediate: save + [.openEditor], showsQuickPreview: false, afterPreview: [])
        case .quickPreview:
            return PostCapturePlan(immediate: [], showsQuickPreview: true, afterPreview: save)
        case .clipboardOnly:
            return PostCapturePlan(immediate: [.copyToClipboard] + save, showsQuickPreview: false, afterPreview: [])
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test`
Expected: PASS — every suite, including the new AppCore suites (CaptureDocumentTests 1, AutoSaverTests 5, PostCaptureRouterTests 3).

- [ ] **Step 6: Commit**

```bash
cd /Users/giovanni/work/reatool
git add PinxelKit
git commit -m "feat(app-core): build capture documents, auto-save and route post-capture steps"
```

---

### Task 8: Xcode project with XcodeGen and a minimal menu-bar app

**Files:**
- Create: `project.yml`
- Create: `App/Config/Base.xcconfig`
- Create (git-ignored): `App/Config/Signing.local.xcconfig`
- Create: `App/Pinxel/PinxelApp.swift`
- Create: `App/Pinxel/AppDelegate.swift`
- Create: `App/PinxelUITests/LaunchUITests.swift`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: PinxelKit products.
- Produces: an app target `Pinxel` (bundle `com.degiorgi.pinxel`, `LSUIElement`, document type + exported UTI for `.pinxel`), a UI-test target `PinxelUITests`, scheme `Pinxel`. `AppDelegate` is the `NSApplicationDelegate` used by later tasks.

**Prerequisite (user action):** Xcode → Settings → Accounts → sign in with an Apple ID so an "Apple Development" certificate exists. Without it the app still builds ad hoc, but macOS asks again for the screen-recording permission after every build.

- [ ] **Step 1: Write the failing UI test**

`App/PinxelUITests/LaunchUITests.swift`:

```swift
import XCTest

final class LaunchUITests: XCTestCase {
    func testAppLaunchesAsMenuBarAgent() {
        let app = XCUIApplication()
        app.launchArguments = ["-PinxelUITestFakeCapture"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10) || app.wait(for: .runningBackground, timeout: 10))
        // Agente: nessuna finestra all'avvio.
        XCTAssertEqual(app.windows.count, 0)
        app.terminate()
    }
}
```

- [ ] **Step 2: Write the project description and configuration**

`project.yml`:

```yaml
name: Pinxel
options:
  bundleIdPrefix: com.degiorgi
  deploymentTarget:
    macOS: "15.0"
  createIntermediateGroups: true
packages:
  PinxelKit:
    path: PinxelKit
configFiles:
  Debug: App/Config/Base.xcconfig
  Release: App/Config/Base.xcconfig
settings:
  base:
    SWIFT_VERSION: "6.0"
    MARKETING_VERSION: "0.1.0"
    CURRENT_PROJECT_VERSION: "1"
    ENABLE_HARDENED_RUNTIME: YES
targets:
  Pinxel:
    type: application
    platform: macOS
    sources: [App/Pinxel]
    dependencies:
      - package: PinxelKit
        product: DocumentModel
      - package: PinxelKit
        product: Rendering
      - package: PinxelKit
        product: Persistence
      - package: PinxelKit
        product: CaptureKit
      - package: PinxelKit
        product: AppCore
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.degiorgi.pinxel
        PRODUCT_NAME: Pinxel
        GENERATE_INFOPLIST_FILE: NO
    info:
      path: App/Pinxel/Info.plist
      properties:
        CFBundleDisplayName: Pinxel
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        LSUIElement: true
        LSApplicationCategoryType: public.app-category.graphics-design
        LSMinimumSystemVersion: "15.0"
        NSHumanReadableCopyright: "© 2026 Giovanni De Giorgi"
        CFBundleDocumentTypes:
          - CFBundleTypeName: Documento Pinxel
            CFBundleTypeRole: Editor
            LSHandlerRank: Owner
            LSItemContentTypes: [com.degiorgi.pinxel.document]
            NSDocumentClass: PinxelFileDocument
        UTExportedTypeDeclarations:
          - UTTypeIdentifier: com.degiorgi.pinxel.document
            UTTypeDescription: Documento Pinxel
            UTTypeConformsTo: [public.data, public.composite-content]
            UTTypeTagSpecification:
              public.filename-extension: [pinxel]
  PinxelUITests:
    type: bundle.ui-testing
    platform: macOS
    sources: [App/PinxelUITests]
    dependencies:
      - target: Pinxel
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.degiorgi.pinxel.uitests
        GENERATE_INFOPLIST_FILE: YES
schemes:
  Pinxel:
    build:
      targets:
        Pinxel: all
        PinxelUITests: [test]
    test:
      targets: [PinxelUITests]
```

`App/Config/Base.xcconfig`:

```
// Firma predefinita: ad hoc (funziona ovunque, ma macOS richiede di nuovo il permesso di
// Registrazione schermo a ogni build). Per una firma stabile crea Signing.local.xcconfig.
CODE_SIGN_STYLE = Manual
CODE_SIGN_IDENTITY = -
DEVELOPMENT_TEAM =

#include? "Signing.local.xcconfig"
```

Append to `/Users/giovanni/work/reatool/.gitignore`:

```
Pinxel.xcodeproj/
App/Config/Signing.local.xcconfig
App/Pinxel/Info.plist
build/
```

Create `App/Config/Signing.local.xcconfig` (not committed) once the Apple ID is configured. Find the team ID:

```bash
security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject
```

The `OU=` value is the team ID. Write it into the file:

```
CODE_SIGN_STYLE = Automatic
CODE_SIGN_IDENTITY = Apple Development
DEVELOPMENT_TEAM = <OU value>
```

If no certificate exists yet, skip this file and record a ledger note; the build stays ad hoc.

- [ ] **Step 3: Write the minimal app**

`App/Pinxel/PinxelApp.swift`:

```swift
import SwiftUI

@main
struct PinxelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Pinxel", systemImage: "camera.viewfinder") {
            Button("Esci da Pinxel") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
```

`App/Pinxel/AppDelegate.swift`:

```swift
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
```

- [ ] **Step 4: Generate, build and run the UI test**

Run:

```bash
cd /Users/giovanni/work/reatool
xcodegen generate
xcodebuild -project Pinxel.xcodeproj -scheme Pinxel -configuration Debug -destination 'platform=macOS' -allowProvisioningUpdates build-for-testing > build/xcodebuild.log 2>&1; echo "exit $?"
xcodebuild -project Pinxel.xcodeproj -scheme Pinxel -destination 'platform=macOS' -allowProvisioningUpdates test-without-building -only-testing:PinxelUITests/LaunchUITests >> build/xcodebuild.log 2>&1; echo "exit $?"
grep -E "error:|Test Suite .* (passed|failed)|\*\* TEST" build/xcodebuild.log | tail -5
```

(Create `build/` first with `mkdir -p build`.)
Expected: both commands exit 0; `LaunchUITests` passes. The first UI-test run may show a macOS prompt asking to allow Xcode/the test runner to control the computer — approve it and re-run. If signing fails with "requires a development team", the local xcconfig is wrong: remove it to fall back to ad hoc and record a ledger note.

- [ ] **Step 5: Commit**

```bash
cd /Users/giovanni/work/reatool
git add .gitignore project.yml App/Config/Base.xcconfig App/Pinxel App/PinxelUITests
git commit -m "feat(app): add XcodeGen project and minimal menu-bar app"
```

---

### Task 9: Document window (read-only viewer until plan 3) and Dock behaviour

**Files:**
- Create: `App/Pinxel/Document/PinxelFileDocument.swift`
- Create: `App/Pinxel/Document/ViewerWindowController.swift`
- Create: `App/Pinxel/Document/DocumentOpener.swift`
- Modify: `App/Pinxel/AppDelegate.swift`
- Modify: `App/PinxelUITests/LaunchUITests.swift` (add a test)

**Interfaces:**
- Consumes: `PinxelFileContents`, `PinxelArchive`, `Thumbnailer`, `DocumentRenderer`.
- Produces:
  - `@objc(PinxelFileDocument) final class PinxelFileDocument: NSDocument` — `convenience init(contents: PinxelFileContents)`; reads/writes `.pinxel`; refuses to save files from newer versions.
  - `@MainActor enum DocumentOpener { static func open(_ contents: PinxelFileContents) }` — shows a new untitled document window and switches to `.regular` activation.
  - `AppDelegate` returns to `.accessory` when the last document closes.
  - Viewer image view accessibility identifier: `pinxel.viewer.image`.
  - Launch argument `-PinxelUITestOpenSample` opens a generated sample document at launch (UI test hook).

- [ ] **Step 1: Write the failing UI test**

Add to `App/PinxelUITests/LaunchUITests.swift`, inside the class:

```swift
    func testSampleDocumentOpensViewerWindow() {
        let app = XCUIApplication()
        app.launchArguments = ["-PinxelUITestFakeCapture", "-PinxelUITestOpenSample"]
        app.launch()
        XCTAssertTrue(app.images["pinxel.viewer.image"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.windows.count, 1)
        app.terminate()
    }
```

Run: `xcodegen generate && xcodebuild -project Pinxel.xcodeproj -scheme Pinxel -destination 'platform=macOS' -allowProvisioningUpdates test -only-testing:PinxelUITests/LaunchUITests > build/xcodebuild.log 2>&1; grep -E "error:|Test Case .*(passed|failed)" build/xcodebuild.log | tail -5`
Expected: `testSampleDocumentOpensViewerWindow` FAILS (no window appears).

- [ ] **Step 2: Implement the document and the viewer**

`App/Pinxel/Document/PinxelFileDocument.swift`:

```swift
import AppKit
import AppCore
import DocumentModel
import Persistence
import Rendering

@objc(PinxelFileDocument)
final class PinxelFileDocument: NSDocument {
    private(set) var contents: PinxelFileContents?

    convenience init(contents: PinxelFileContents) {
        self.init()
        self.contents = contents
        fileType = "com.degiorgi.pinxel.document"
    }

    override class var autosavesInPlace: Bool { true }

    override func read(from data: Data, ofType typeName: String) throws {
        do {
            contents = try PinxelArchive.read(data)
        } catch {
            throw Self.userError(for: error, data: data)
        }
    }

    override func data(ofType typeName: String) throws -> Data {
        guard let contents else { throw CocoaError(.fileWriteUnknown) }
        guard !contents.isReadOnly else {
            throw NSError(domain: "com.degiorgi.pinxel", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Questo documento è stato creato da una versione più recente di Pinxel e si può solo leggere.",
            ])
        }
        let assets = try contents.assetProvider()
        let thumbnail = try Thumbnailer.make(contents.document, assets: assets)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        return try PinxelArchive.write(document: contents.document, images: contents.images, thumbnail: thumbnail, appVersion: version)
    }

    override func makeWindowControllers() {
        MainActor.assumeIsolated {
            guard let contents else { return }
            do {
                let image = try DocumentRenderer().renderImage(contents.document, assets: try contents.assetProvider())
                addWindowController(ViewerWindowController(image: image, scale: contents.document.scale))
            } catch {
                presentError(error)
            }
        }
    }

    private static func userError(for error: Error, data: Data) -> NSError {
        let reason: String
        switch error {
        case PinxelArchiveError.notAPinxelFile: reason = "Il file non è un documento Pinxel."
        case PinxelArchiveError.invalidDocument(let detail): reason = "Il documento è danneggiato (\(detail))."
        case PinxelArchiveError.missingAsset(let name): reason = "Nel documento manca l'immagine \(name)."
        default: reason = "Il file è danneggiato o illeggibile."
        }
        var info: [String: Any] = [NSLocalizedDescriptionKey: reason]
        if PinxelArchive.recoverBackground(data) != nil {
            info[NSLocalizedRecoverySuggestionErrorKey] = "L'immagine originale è integra e si può recuperare."
        }
        return NSError(domain: "com.degiorgi.pinxel", code: 2, userInfo: info)
    }
}
```

`App/Pinxel/Document/ViewerWindowController.swift`:

```swift
import AppKit

/// Finestra di sola visualizzazione; nel piano 3 diventa l'editor.
@MainActor
final class ViewerWindowController: NSWindowController {
    convenience init(image: CGImage, scale: Double) {
        let size = NSSize(width: Double(image.width) / scale, height: Double(image.height) / scale)
        let imageView = NSImageView(frame: NSRect(origin: .zero, size: size))
        imageView.image = NSImage(cgImage: image, size: size)
        imageView.imageScaling = .scaleNone
        imageView.setAccessibilityIdentifier("pinxel.viewer.image")

        let scrollView = NSScrollView()
        scrollView.documentView = imageView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .windowBackgroundColor

        let visible = NSScreen.main?.visibleFrame.size ?? size
        let contentSize = NSSize(width: min(max(size.width, 320), visible.width * 0.8),
                                 height: min(max(size.height, 240), visible.height * 0.8))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: contentSize),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.contentView = scrollView
        window.center()
        self.init(window: window)
    }
}
```

`App/Pinxel/Document/DocumentOpener.swift`:

```swift
import AppKit
import Persistence

@MainActor
enum DocumentOpener {
    static func open(_ contents: PinxelFileContents) {
        let document = PinxelFileDocument(contents: contents)
        NSDocumentController.shared.addDocument(document)
        document.makeWindowControllers()
        NSApp.setActivationPolicy(.regular)
        document.showWindows()
        NSApp.activate()
    }
}
```

- [ ] **Step 3: Dock behaviour and the sample hook**

Replace `App/Pinxel/AppDelegate.swift`:

```swift
import AppCore
import AppKit
import DocumentModel
import Persistence

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { _ in
            // Dopo la chiusura, senza documenti aperti l'app torna agente (niente icona nel Dock).
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if NSDocumentController.shared.documents.isEmpty {
                        NSApp.setActivationPolicy(.accessory)
                    }
                }
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-PinxelUITestOpenSample") {
            openSample()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    private func openSample() {
        let size = 200
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.setFillColor(CGColor(srgbRed: 0.2, green: 0.5, blue: 0.9, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        guard let image = ctx.makeImage(),
              let contents = try? CaptureDocumentBuilder.make(image: image, scale: 1, metadata: CaptureMetadata()) else { return }
        DocumentOpener.open(contents)
    }
}
```

- [ ] **Step 4: Run the UI tests**

Run: `xcodegen generate && xcodebuild -project Pinxel.xcodeproj -scheme Pinxel -destination 'platform=macOS' -allowProvisioningUpdates test -only-testing:PinxelUITests/LaunchUITests > build/xcodebuild.log 2>&1; echo "exit $?"; grep -E "error:|Test Case .*(passed|failed)" build/xcodebuild.log | tail -5`
Expected: exit 0, both `LaunchUITests` tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/giovanni/work/reatool
git add App
git commit -m "feat(app): add .pinxel document window and agent/Dock switching"
```

---

### Task 10: Global hotkeys, app environment, menu and preferences

**Files:**
- Create: `App/Pinxel/HotKeyCenter.swift`
- Create: `App/Pinxel/AppEnvironment.swift`
- Create: `App/Pinxel/MenuContent.swift`
- Create: `App/Pinxel/Settings/SettingsView.swift`
- Modify: `App/Pinxel/PinxelApp.swift`
- Modify: `App/Pinxel/AppDelegate.swift`

**Interfaces:**
- Consumes: `SettingsStore`, `CaptureSettings`, `KeyCombo`, `HotKeyAction`, `CaptureMode`.
- Produces:
  - `@MainActor final class HotKeyCenter { func register(_: KeyCombo, id: UInt32, action: @escaping @MainActor () -> Void) -> Bool; func unregister(id: UInt32); func unregisterAll() }`
  - `@MainActor @Observable final class AppEnvironment { static let shared: AppEnvironment; private(set) var settings: CaptureSettings; private(set) var hotKeyConflicts: Set<HotKeyAction>; func update(_ change: (inout CaptureSettings) -> Void); func capture(_: CaptureMode); func repeatLastArea() }` — `capture`/`repeatLastArea` are stubs logging "not wired" until Task 13.
  - `MenuContent` (menu items of spec §7.1) and `SettingsView` (post-capture action, auto-save folder/format/template, window shadow, four shortcut recorders with conflict warnings).

- [ ] **Step 1: Implement the hotkey center**

`App/Pinxel/HotKeyCenter.swift`:

```swift
import Carbon.HIToolbox
import AppCore

/// Scorciatoie globali con `RegisterEventHotKey` (non richiede il permesso Accessibilità).
@MainActor
final class HotKeyCenter {
    private var references: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: @MainActor () -> Void] = [:]
    private var handlerInstalled = false
    private static let signature: OSType = 0x5058_4C21 // 'PXL!'

    /// `false` se la combinazione è già usata da un'altra app o non ha modificatori.
    func register(_ combo: KeyCombo, id: UInt32, action: @escaping @MainActor () -> Void) -> Bool {
        unregister(id: id)
        guard combo.hasModifier else { return false }
        installHandlerIfNeeded()
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, EventHotKeyID(signature: Self.signature, id: id),
                                         GetApplicationEventTarget(), 0, &reference)
        guard status == noErr, let reference else { return false }
        references[id] = reference
        actions[id] = action
        return true
    }

    func unregister(id: UInt32) {
        if let reference = references.removeValue(forKey: id) { UnregisterEventHotKey(reference) }
        actions[id] = nil
    }

    func unregisterAll() {
        for id in Array(references.keys) { unregister(id: id) }
    }

    fileprivate func fire(_ id: UInt32) {
        actions[id]?()
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr else { return status }
            let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
            let id = hotKeyID.id
            // Gli eventi Carbon arrivano sul thread principale.
            MainActor.assumeIsolated { center.fire(id) }
            return noErr
        }, 1, &spec, userData, nil)
    }
}
```

- [ ] **Step 2: Implement the environment, menu and preferences**

`App/Pinxel/AppEnvironment.swift`:

```swift
import AppCore
import CaptureKit
import Foundation
import Observation
import os

@MainActor
@Observable
final class AppEnvironment {
    static let shared = AppEnvironment()

    let isUITesting: Bool
    private(set) var settings: CaptureSettings
    private(set) var hotKeyConflicts: Set<HotKeyAction> = []

    @ObservationIgnored private let store: SettingsStore
    @ObservationIgnored private let hotKeys = HotKeyCenter()
    @ObservationIgnored let logger = Logger(subsystem: "com.degiorgi.pinxel", category: "app")

    private init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        isUITesting = arguments.contains("-PinxelUITestFakeCapture")
        if isUITesting {
            let suite = "com.degiorgi.pinxel.uitests"
            let defaults = UserDefaults(suiteName: suite)!
            defaults.removePersistentDomain(forName: suite)
            store = SettingsStore(defaults: defaults)
        } else {
            store = SettingsStore()
        }
        var loaded = store.load()
        if let index = arguments.firstIndex(of: "-PinxelUITestPostCapture"), index + 1 < arguments.count,
           let action = PostCaptureAction(rawValue: arguments[index + 1]) {
            loaded.postCaptureAction = action
        }
        settings = loaded
    }

    func start() {
        applyHotKeys()
    }

    func update(_ change: (inout CaptureSettings) -> Void) {
        var copy = settings
        change(&copy)
        guard copy != settings else { return }
        let hotKeysChanged = copy.hotKeys != settings.hotKeys
        settings = copy
        store.save(copy)
        if hotKeysChanged { applyHotKeys() }
    }

    func capture(_ mode: CaptureMode) {
        logger.info("capture \(mode.rawValue, privacy: .public) requested (not wired yet)")
    }

    func repeatLastArea() {
        logger.info("repeat last area requested (not wired yet)")
    }

    private func applyHotKeys() {
        guard !isUITesting else { return }
        hotKeys.unregisterAll()
        var conflicts = Set<HotKeyAction>()
        for (index, action) in HotKeyAction.allCases.enumerated() {
            let registered = hotKeys.register(settings.combo(for: action), id: UInt32(index + 1)) { [weak self] in
                self?.perform(action)
            }
            if !registered { conflicts.insert(action) }
        }
        hotKeyConflicts = conflicts
    }

    private func perform(_ action: HotKeyAction) {
        switch action {
        case .area: capture(.area)
        case .window: capture(.window)
        case .screen: capture(.screen)
        case .repeatLastArea: repeatLastArea()
        }
    }
}
```

`App/Pinxel/MenuContent.swift`:

```swift
import AppCore
import CaptureKit
import SwiftUI

struct MenuContent: View {
    let environment: AppEnvironment

    var body: some View {
        Button("\(HotKeyAction.area.title)  \(environment.settings.combo(for: .area).displayString)") { environment.capture(.area) }
        Button("\(HotKeyAction.window.title)  \(environment.settings.combo(for: .window).displayString)") { environment.capture(.window) }
        Button("\(HotKeyAction.screen.title)  \(environment.settings.combo(for: .screen).displayString)") { environment.capture(.screen) }
        Button("\(HotKeyAction.repeatLastArea.title)  \(environment.settings.combo(for: .repeatLastArea).displayString)") { environment.repeatLastArea() }
        Divider()
        Button("Apri…") {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
            NSDocumentController.shared.openDocument(nil)
        }
        SettingsLink { Text("Preferenze…") }
            .keyboardShortcut(",")
        Divider()
        Button("Esci da Pinxel") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
```

`App/Pinxel/Settings/SettingsView.swift`:

```swift
import AppCore
import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var environment: AppEnvironment

    var body: some View {
        Form {
            Section("Dopo la cattura") {
                Picker("Azione", selection: binding(\.postCaptureAction)) {
                    ForEach(PostCaptureAction.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle("Includi l'ombra nelle catture di finestre", isOn: binding(\.includeWindowShadow))
            }
            Section("Salvataggio automatico") {
                Toggle("Salva automaticamente ogni cattura", isOn: binding(\.autoSave))
                LabeledContent("Cartella") {
                    HStack {
                        Text(environment.settings.saveFolderURL.path).lineLimit(1).truncationMode(.middle)
                        Button("Scegli…", action: chooseFolder)
                    }
                }
                Picker("Formato", selection: binding(\.saveFormat)) {
                    Text("Documento Pinxel (.pinxel)").tag(SaveFormat.pinxel)
                    Text("Immagine PNG").tag(SaveFormat.png)
                }
                TextField("Nome file", text: binding(\.fileNameTemplate))
                Text("Esempio: \(FileNamer.baseName(template: environment.settings.fileNameTemplate, date: Date()))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Scorciatoie globali") {
                ForEach(HotKeyAction.allCases, id: \.self) { action in
                    LabeledContent(action.title) {
                        VStack(alignment: .trailing) {
                            ShortcutRecorder(combo: Binding(
                                get: { environment.settings.combo(for: action) },
                                set: { combo in environment.update { $0.hotKeys[action] = combo } }
                            ))
                            if environment.hotKeyConflicts.contains(action) {
                                Text("Combinazione già in uso da un'altra app").font(.caption).foregroundStyle(.red)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .padding()
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<CaptureSettings, Value>) -> Binding<Value> {
        Binding(
            get: { environment.settings[keyPath: keyPath] },
            set: { value in environment.update { $0[keyPath: keyPath] = value } }
        )
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = environment.settings.saveFolderURL
        if panel.runModal() == .OK, let url = panel.url {
            environment.update { $0.saveFolderPath = url.path }
        }
    }
}

/// Registra una combinazione: richiede almeno un modificatore; Esc annulla.
struct ShortcutRecorder: View {
    @Binding var combo: KeyCombo
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? "Premi la combinazione…" : combo.displayString) {
            recording ? stop() : start()
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Esc
                stop()
                return nil
            }
            let candidate = KeyCombo(keyCode: UInt32(event.keyCode),
                                     modifiers: KeyCombo.carbonModifiers(fromCocoa: event.modifierFlags.rawValue))
            if candidate.hasModifier {
                combo = candidate
                stop()
            }
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
```

Replace `App/Pinxel/PinxelApp.swift`:

```swift
import SwiftUI

@main
struct PinxelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let environment = AppEnvironment.shared

    var body: some Scene {
        MenuBarExtra("Pinxel", systemImage: "camera.viewfinder") {
            MenuContent(environment: environment)
        }
        Settings {
            SettingsView(environment: environment)
        }
    }
}
```

In `App/Pinxel/AppDelegate.swift`, at the start of `applicationDidFinishLaunching`, after `NSApp.setActivationPolicy(.accessory)`, add:

```swift
        AppEnvironment.shared.start()
```

- [ ] **Step 3: Build and run the UI tests**

Run: `xcodegen generate && xcodebuild -project Pinxel.xcodeproj -scheme Pinxel -destination 'platform=macOS' -allowProvisioningUpdates test > build/xcodebuild.log 2>&1; echo "exit $?"; grep -E "error:|warning: .*Pinxel|Test Case .*(passed|failed)" build/xcodebuild.log | tail -8`
Expected: exit 0, no compiler errors, existing UI tests pass.

- [ ] **Step 4: Manual check**

Launch the built app (`open build/…` is not needed: run `xcodebuild … build` then `open "$(xcodebuild -project Pinxel.xcodeproj -scheme Pinxel -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2}')/Pinxel.app"`). Verify: camera icon in the menu bar; menu shows the four capture items with `⌃⇧1…4`; "Preferenze…" opens the settings window; recording a shortcut updates the menu label; pressing `⌃⇧1` logs `capture area requested` in Console.app (subsystem `com.degiorgi.pinxel`). Record the result in the ledger.

- [ ] **Step 5: Commit**

```bash
cd /Users/giovanni/work/reatool
git add App
git commit -m "feat(app): add global hotkeys, menu and preferences"
```

---

### Task 11: Selection overlay

**Files:**
- Create: `App/Pinxel/Capture/OverlayController.swift`
- Create: `App/Pinxel/Capture/SelectionView.swift`
- Create: `App/Pinxel/Capture/SelectionProviders.swift`

**Interfaces:**
- Consumes: `CaptureSnapshot`, `FrozenDisplay`, `SelectionModel`, `SelectionResult`, `SelectionKey`, `CaptureMode`, `ScreenGeometry`.
- Produces:
  - `@MainActor protocol SelectionProvider { func select(mode: CaptureMode, snapshot: CaptureSnapshot) async -> SelectionResult }`
  - `OverlaySelectionProvider` (real overlay) and `FixedSelectionProvider(result:)` (UI tests).
  - `@MainActor final class OverlayController { init(snapshot:mode:); func run() async -> SelectionResult }` — one borderless `.screenSaver`-level window per screen showing its frozen image; dims everything except the selection/highlight; crosshair cursor; loupe with centre-pixel colour and size label.

- [ ] **Step 1: Implement providers and controller**

`App/Pinxel/Capture/SelectionProviders.swift`:

```swift
import CaptureKit

@MainActor
protocol SelectionProvider {
    func select(mode: CaptureMode, snapshot: CaptureSnapshot) async -> SelectionResult
}

@MainActor
struct OverlaySelectionProvider: SelectionProvider {
    func select(mode: CaptureMode, snapshot: CaptureSnapshot) async -> SelectionResult {
        await OverlayController(snapshot: snapshot, mode: mode).run()
    }
}

/// Per gli UI test: nessun overlay, risultato prestabilito.
@MainActor
struct FixedSelectionProvider: SelectionProvider {
    let result: SelectionResult

    func select(mode: CaptureMode, snapshot: CaptureSnapshot) async -> SelectionResult {
        result
    }
}
```

`App/Pinxel/Capture/OverlayController.swift`:

```swift
import AppKit
import CaptureKit

/// Finestra senza bordi che può ricevere la tastiera.
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class OverlayController {
    private(set) var model: SelectionModel
    private let snapshot: CaptureSnapshot
    private var windows: [OverlayWindow] = []
    private var views: [SelectionView] = []
    private var continuation: CheckedContinuation<SelectionResult, Never>?

    init(snapshot: CaptureSnapshot, mode: CaptureMode) {
        self.snapshot = snapshot
        model = SelectionModel(mode: mode, windows: snapshot.windows, displays: snapshot.displays.map(\.info))
    }

    func run() async -> SelectionResult {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            present()
        }
    }

    /// Modifica il modello, ridisegna e, se c'è un risultato, chiude l'overlay.
    func update(_ change: (inout SelectionModel) -> SelectionResult?) {
        let result = change(&model)
        views.forEach { $0.needsDisplay = true }
        if let result { finish(result) }
    }

    private func present() {
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let display = snapshot.displays.first(where: { $0.info.id == number.uint32Value }) else { continue }
            let window = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = .screenSaver
            window.isOpaque = true
            window.hasShadow = false
            window.backgroundColor = .black
            window.acceptsMouseMovedEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            let view = SelectionView(display: display, controller: self)
            window.contentView = view
            window.setFrame(screen.frame, display: false)
            windows.append(window)
            views.append(view)
        }
        guard !windows.isEmpty else {
            finish(.cancelled)
            return
        }
        NSApp.activate()
        let mouse = NSEvent.mouseLocation
        let keyWindow = windows.first { $0.frame.contains(mouse) } ?? windows[0]
        windows.forEach { $0.orderFrontRegardless() }
        keyWindow.makeKeyAndOrderFront(nil)
        keyWindow.makeFirstResponder(keyWindow.contentView)
        let primary = NSScreen.screens.first?.frame.height ?? 0
        update { model in
            model.mouseMoved(to: ScreenGeometry.topLeft(fromAppKit: CGRect(origin: mouse, size: .zero), primaryHeight: primary).origin)
            return nil
        }
        NSCursor.crosshair.push()
    }

    private func finish(_ result: SelectionResult) {
        guard let continuation else { return }
        self.continuation = nil
        NSCursor.pop()
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        views.removeAll()
        continuation.resume(returning: result)
    }
}
```

- [ ] **Step 2: Implement the selection view**

`App/Pinxel/Capture/SelectionView.swift`:

```swift
import AppKit
import CaptureKit

/// Disegna l'immagine congelata di uno schermo e la selezione; traduce mouse e tastiera per il modello.
@MainActor
final class SelectionView: NSView {
    private let display: FrozenDisplay
    private weak var controller: OverlayController?
    private var spaceHeld = false
    private var lastDragPoint: CGPoint?

    init(display: FrozenDisplay, controller: OverlayController) {
        self.display = display
        self.controller = controller
        super.init(frame: NSRect(origin: .zero, size: display.info.frame.size))
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate], owner: self))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }

    // MARK: Coordinate

    private func globalPoint(_ event: NSEvent) -> CGPoint {
        let local = convert(event.locationInWindow, from: nil)
        return CGPoint(x: display.info.frame.minX + local.x, y: display.info.frame.minY + local.y)
    }

    private func localRect(_ global: CGRect) -> CGRect {
        global.offsetBy(dx: -display.info.frame.minX, dy: -display.info.frame.minY)
    }

    // MARK: Eventi

    override func mouseMoved(with event: NSEvent) {
        let point = globalPoint(event)
        controller?.update { $0.mouseMoved(to: point); return nil }
    }

    override func mouseDown(with event: NSEvent) {
        let point = globalPoint(event)
        lastDragPoint = point
        controller?.update { $0.mouseDown(at: point); return nil }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = globalPoint(event)
        let square = event.modifierFlags.contains(.shift)
        if spaceHeld, let last = lastDragPoint {
            let delta = CGSize(width: point.x - last.x, height: point.y - last.y)
            controller?.update { $0.moveSelection(by: delta); return nil }
        } else {
            controller?.update { $0.mouseDragged(to: point, square: square); return nil }
        }
        lastDragPoint = point
    }

    override func mouseUp(with event: NSEvent) {
        let point = globalPoint(event)
        lastDragPoint = nil
        controller?.update { $0.mouseUp(at: point) }
    }

    override func keyDown(with event: NSEvent) {
        let shift = event.modifierFlags.contains(.shift)
        let key: SelectionKey?
        switch event.keyCode {
        case 53: key = .escape
        case 36, 76: key = .enter
        case 123: key = .left
        case 124: key = .right
        case 125: key = .down
        case 126: key = .up
        case 49:
            spaceHeld = true
            key = nil
        default: key = nil
        }
        if let key { controller?.update { $0.key(key, shift: shift) } }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 { spaceHeld = false }
    }

    // MARK: Disegno

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, let model = controller?.model else { return }
        // Immagine congelata (la vista è capovolta: la ridisegno dritta).
        ctx.saveGState()
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(display.image, in: bounds)
        ctx.restoreGState()

        var focus: CGRect?
        if let rect = model.selectionRect {
            focus = localRect(rect)
        } else if let window = model.highlightedWindow {
            focus = localRect(window.frame)
        } else if let screen = model.highlightedDisplay, screen.id == display.info.id {
            focus = bounds
        }

        // Oscuro tutto tranne la zona in evidenza.
        let dim = CGMutablePath()
        dim.addRect(bounds)
        if let focus { dim.addRect(focus) }
        ctx.addPath(dim)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.fillPath(using: .evenOdd)

        if let focus {
            ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
            ctx.setLineWidth(model.selectionRect == nil ? 3 : 1)
            ctx.stroke(focus.insetBy(dx: 0.5, dy: 0.5))
        }
        if let rect = model.selectionRect {
            let pixels = "\(Int((rect.width * display.info.scale).rounded())) × \(Int((rect.height * display.info.scale).rounded()))"
            drawLabel(pixels, near: CGPoint(x: localRect(rect).minX, y: localRect(rect).maxY + 6))
        }
        drawLoupe(at: model.pointer)
    }

    private func drawLabel(_ text: String, near point: CGPoint) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let box = CGRect(x: point.x, y: min(point.y, bounds.height - size.height - 8), width: size.width + 12, height: size.height + 6)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
        (text as NSString).draw(at: CGPoint(x: box.minX + 6, y: box.minY + 3), withAttributes: attributes)
    }

    /// Lente 11×11 pixel ingrandita 10×, con mirino e colore del pixel centrale.
    private func drawLoupe(at global: CGPoint) {
        guard display.info.frame.insetBy(dx: -1, dy: -1).contains(global) else { return }
        let scale = display.info.scale
        let local = CGPoint(x: global.x - display.info.frame.minX, y: global.y - display.info.frame.minY)
        let centerX = Int(local.x * scale), centerY = Int(local.y * scale)
        let radius = 5
        guard let crop = display.image.cropping(to: CGRect(x: centerX - radius, y: centerY - radius, width: radius * 2 + 1, height: radius * 2 + 1)) else { return }

        let side: CGFloat = 110
        var origin = CGPoint(x: local.x + 20, y: local.y + 20)
        if origin.x + side > bounds.width { origin.x = local.x - 20 - side }
        if origin.y + side + 24 > bounds.height { origin.y = local.y - 20 - side - 24 }
        let loupe = CGRect(origin: origin, size: CGSize(width: side, height: side))

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.addEllipse(in: loupe)
        ctx.clip()
        ctx.interpolationQuality = .none
        ctx.translateBy(x: loupe.minX, y: loupe.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(crop, in: CGRect(origin: .zero, size: loupe.size))
        ctx.restoreGState()

        let cell = side / CGFloat(radius * 2 + 1)
        ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(CGRect(x: loupe.midX - cell / 2, y: loupe.midY - cell / 2, width: cell, height: cell))
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(2)
        ctx.strokeEllipse(in: loupe)

        if let color = pixelColor(x: centerX, y: centerY) {
            drawLabel(String(format: "#%02X%02X%02X", color.0, color.1, color.2), near: CGPoint(x: loupe.minX, y: loupe.maxY + 4))
        }
    }

    private func pixelColor(x: Int, y: Int) -> (UInt8, UInt8, UInt8)? {
        guard x >= 0, y >= 0, x < display.image.width, y < display.image.height,
              let pixel = display.image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else { return nil }
        var data = [UInt8](repeating: 0, count: 4)
        let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        return drawn ? (data[0], data[1], data[2]) : nil
    }
}
```

- [ ] **Step 3: Build**

Run: `xcodegen generate && xcodebuild -project Pinxel.xcodeproj -scheme Pinxel -destination 'platform=macOS' -allowProvisioningUpdates build > build/xcodebuild.log 2>&1; echo "exit $?"; grep -E "error:" build/xcodebuild.log | head -5`
Expected: exit 0. (The overlay is exercised manually in Task 14; its decisions are covered by `SelectionModelTests`.)

- [ ] **Step 4: Commit**

```bash
cd /Users/giovanni/work/reatool
git add App
git commit -m "feat(app): add frozen-screen selection overlay with loupe"
```

---

### Task 12: Post-capture actions — clipboard, quick preview, notifications

**Files:**
- Create: `App/Pinxel/PostCapture/Clipboard.swift`
- Create: `App/Pinxel/PostCapture/Notifier.swift`
- Create: `App/Pinxel/PostCapture/QuickPreview.swift`
- Create: `App/Pinxel/PostCapture/PostCaptureActions.swift`

**Interfaces:**
- Consumes: `PostCapturePlan`, `PostCaptureStep`, `AutoSaver`, `AutoSaveError`, `CaptureSettings`, `PinxelFileContents`, `DocumentOpener`, `CaptureError`.
- Produces:
  - `@MainActor enum Clipboard { static func copy(_ image: CGImage) }` (PNG + TIFF)
  - `@MainActor final class Notifier { init(enabled: Bool); func failure(_ error: Error); func info(_ text: String) }`
  - `@MainActor final class QuickPreviewController { init(image:scale:onOpen:onExpire:); func show() }` — 5 s, hover pauses, click opens, drag exports a PNG file.
  - `@MainActor final class PostCaptureActions { init(notifier:autoSaver:); func perform(_ plan: PostCapturePlan, contents: PinxelFileContents, image: CGImage, settings: CaptureSettings) }` — on auto-save failure: notification and the capture opens in a document window (spec §10).

- [ ] **Step 1: Implement**

`App/Pinxel/PostCapture/Clipboard.swift`:

```swift
import AppKit

@MainActor
enum Clipboard {
    static func copy(_ image: CGImage) {
        let representation = NSBitmapImageRep(cgImage: image)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let png = representation.representation(using: .png, properties: [:]) {
            pasteboard.setData(png, forType: .png)
        }
        if let tiff = representation.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
    }
}
```

`App/Pinxel/PostCapture/Notifier.swift`:

```swift
import AppCore
import CaptureKit
import Foundation
import os
import UserNotifications

@MainActor
final class Notifier {
    private let enabled: Bool
    private let logger = Logger(subsystem: "com.degiorgi.pinxel", category: "notifications")

    init(enabled: Bool) {
        self.enabled = enabled
    }

    func failure(_ error: Error) {
        let message = Self.message(for: error)
        logger.error("\(message, privacy: .public)")
        post(title: "Cattura non riuscita", body: message)
    }

    func info(_ text: String) {
        post(title: "Pinxel", body: text)
    }

    static func message(for error: Error) -> String {
        switch error {
        case CaptureError.windowNotFound: "La finestra è stata chiusa prima della cattura."
        case CaptureError.displayNotFound: "Lo schermo non è più disponibile."
        case CaptureError.emptySelection: "La selezione è vuota."
        case AutoSaveError.folderNotWritable(let path): "Impossibile scrivere in \(path). Scegli un'altra cartella nelle Preferenze."
        case AutoSaveError.writeFailed(let path): "Salvataggio non riuscito: \(path)."
        default: error.localizedDescription
        }
    }

    private func post(title: String, body: String) {
        guard enabled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}
```

`App/Pinxel/PostCapture/QuickPreview.swift`:

```swift
import AppKit
import UniformTypeIdentifiers

/// Miniatura in basso a destra per 5 s: clic apre l'editor, trascinamento esporta un PNG.
@MainActor
final class QuickPreviewController {
    private let panel: NSPanel
    private var timer: Timer?
    private let onOpen: () -> Void
    private let onExpire: () -> Void
    private var finished = false

    init(image: CGImage, scale: Double, onOpen: @escaping () -> Void, onExpire: @escaping () -> Void) {
        self.onOpen = onOpen
        self.onExpire = onExpire
        let maxSide: CGFloat = 220
        let pointSize = NSSize(width: Double(image.width) / scale, height: Double(image.height) / scale)
        let factor = min(1, maxSide / max(pointSize.width, pointSize.height))
        let size = NSSize(width: max(pointSize.width * factor, 40), height: max(pointSize.height * factor, 40))
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.nonactivatingPanel, .borderless],
                        backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = QuickPreviewView(image: image, size: size)
        view.onClick = { [weak self] in self?.complete(open: true) }
        view.onHover = { [weak self] hovering in hovering ? self?.pause() : self?.resume() }
        panel.contentView = view
    }

    func show() {
        if let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.maxX - panel.frame.width - 20, y: screen.minY + 20))
        }
        panel.orderFrontRegardless()
        resume()
    }

    private func pause() {
        timer?.invalidate()
        timer = nil
    }

    private func resume() {
        pause()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.complete(open: false) }
        }
    }

    private func complete(open: Bool) {
        guard !finished else { return }
        finished = true
        pause()
        panel.orderOut(nil)
        open ? onOpen() : onExpire()
    }
}

@MainActor
final class QuickPreviewView: NSView, NSDraggingSource {
    var onClick: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    private let image: CGImage
    private var dragged = false

    init(image: CGImage, size: NSSize) {
        self.image = image
        super.init(frame: NSRect(origin: .zero, size: size))
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        layer?.contents = image
        layer?.contentsGravity = .resizeAspectFill
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }

    override func mouseDown(with event: NSEvent) {
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragged, let url = writeTemporaryPNG() else { return }
        dragged = true
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        item.setDraggingFrame(bounds, contents: NSImage(cgImage: image, size: bounds.size))
        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        if !dragged { onClick?() }
    }

    nonisolated func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    private func writeTemporaryPNG() -> URL? {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Pinxel", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("Pinxel \(Int(Date().timeIntervalSince1970)).png")
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
              (try? png.write(to: url)) != nil else { return nil }
        return url
    }
}
```

`App/Pinxel/PostCapture/PostCaptureActions.swift`:

```swift
import AppCore
import AppKit
import Persistence

@MainActor
final class PostCaptureActions {
    private let notifier: Notifier
    private let autoSaver: AutoSaver
    private var previews: [QuickPreviewController] = []

    init(notifier: Notifier, autoSaver: AutoSaver = AutoSaver()) {
        self.notifier = notifier
        self.autoSaver = autoSaver
    }

    func perform(_ plan: PostCapturePlan, contents: PinxelFileContents, image: CGImage, settings: CaptureSettings) {
        var editorOpened = false
        run(plan.immediate, contents: contents, image: image, settings: settings, editorOpened: &editorOpened)
        guard plan.showsQuickPreview else { return }
        let preview = QuickPreviewController(
            image: image, scale: contents.document.scale,
            onOpen: { [weak self] in
                DocumentOpener.open(contents)
                self?.previews.removeAll()
            },
            onExpire: { [weak self] in
                guard let self else { return }
                var opened = false
                self.run(plan.afterPreview, contents: contents, image: image, settings: settings, editorOpened: &opened)
                self.previews.removeAll()
            }
        )
        previews.append(preview)
        preview.show()
    }

    private func run(_ steps: [PostCaptureStep], contents: PinxelFileContents, image: CGImage, settings: CaptureSettings, editorOpened: inout Bool) {
        for step in steps {
            switch step {
            case .openEditor:
                if !editorOpened {
                    DocumentOpener.open(contents)
                    editorOpened = true
                }
            case .copyToClipboard:
                Clipboard.copy(image)
                notifier.info("Cattura copiata negli appunti")
            case .autoSave:
                do {
                    _ = try autoSaver.save(contents, settings: settings, date: contents.document.metadata.captureDate)
                } catch {
                    notifier.failure(error)
                    // La cattura non va persa: resta aperta in una finestra.
                    if !editorOpened {
                        DocumentOpener.open(contents)
                        editorOpened = true
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodegen generate && xcodebuild -project Pinxel.xcodeproj -scheme Pinxel -destination 'platform=macOS' -allowProvisioningUpdates build > build/xcodebuild.log 2>&1; echo "exit $?"; grep -E "error:" build/xcodebuild.log | head -5`
Expected: exit 0.

- [ ] **Step 3: Commit**

```bash
cd /Users/giovanni/work/reatool
git add App
git commit -m "feat(app): add clipboard, quick preview, notifications and post-capture actions"
```

---

### Task 13: Capture coordinator, permission window and end-to-end UI tests

**Files:**
- Create: `App/Pinxel/Capture/CaptureCoordinator.swift`
- Create: `App/Pinxel/Capture/PermissionWindow.swift`
- Modify: `App/Pinxel/AppEnvironment.swift`
- Modify: `App/Pinxel/AppDelegate.swift`
- Create: `App/PinxelUITests/CaptureFlowUITests.swift`

**Interfaces:**
- Consumes: everything above.
- Produces:
  - `@MainActor final class CaptureCoordinator { init(engine:permission:selection:actions:settings:); func capture(_: CaptureMode) async; func repeatLastArea() async }` — never runs two captures at once; remembers the last area; window captures use the dedicated window image; metadata from the window or the frontmost app.
  - `@MainActor final class PermissionWindowController` — explains the permission, requests it, opens System Settings, offers "Riavvia Pinxel".
  - UI-test launch arguments: `-PinxelUITestFakeCapture` (fake engine + granted permission + fixed area 100,100 200×150 pt + notifications off), `-PinxelUITestCaptureOnLaunch` (start an area capture after launch), `-PinxelUITestPostCapture <action>`.

- [ ] **Step 1: Write the failing UI tests**

`App/PinxelUITests/CaptureFlowUITests.swift`:

```swift
import AppKit
import XCTest

final class CaptureFlowUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testAreaCaptureOpensDocumentWindow() {
        let app = XCUIApplication()
        app.launchArguments = ["-PinxelUITestFakeCapture", "-PinxelUITestCaptureOnLaunch"]
        app.launch()
        XCTAssertTrue(app.images["pinxel.viewer.image"].waitForExistence(timeout: 15))
        app.terminate()
    }

    func testClipboardOnlyPutsCaptureOnPasteboard() {
        NSPasteboard.general.clearContents()
        let app = XCUIApplication()
        app.launchArguments = ["-PinxelUITestFakeCapture", "-PinxelUITestCaptureOnLaunch", "-PinxelUITestPostCapture", "clipboardOnly"]
        app.launch()
        let deadline = Date().addingTimeInterval(15)
        var png = NSPasteboard.general.data(forType: .png)
        while png == nil, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            png = NSPasteboard.general.data(forType: .png)
        }
        let data = try! XCTUnwrap(png)
        let image = try! XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(image.pixelsWide, 400)
        XCTAssertEqual(image.pixelsHigh, 300)
        XCTAssertEqual(app.windows.count, 0)
        app.terminate()
    }
}
```

Run: `xcodegen generate && xcodebuild -project Pinxel.xcodeproj -scheme Pinxel -destination 'platform=macOS' -allowProvisioningUpdates test -only-testing:PinxelUITests/CaptureFlowUITests > build/xcodebuild.log 2>&1; grep -E "Test Case .*(passed|failed)" build/xcodebuild.log`
Expected: both tests FAIL (nothing is captured yet).

- [ ] **Step 2: Implement the coordinator and the permission window**

`App/Pinxel/Capture/CaptureCoordinator.swift`:

```swift
import AppCore
import AppKit
import CaptureKit
import DocumentModel

@MainActor
final class CaptureCoordinator {
    private let engine: any CaptureEngine
    private let permission: any ScreenRecordingPermission
    private let selection: any SelectionProvider
    private let actions: PostCaptureActions
    private let settings: () -> CaptureSettings
    private var isCapturing = false
    private var lastArea: CGRect?
    private var permissionWindow: PermissionWindowController?

    init(engine: any CaptureEngine, permission: any ScreenRecordingPermission, selection: any SelectionProvider,
         actions: PostCaptureActions, settings: @escaping () -> CaptureSettings) {
        self.engine = engine
        self.permission = permission
        self.selection = selection
        self.actions = actions
        self.settings = settings
    }

    func capture(_ mode: CaptureMode) async {
        await run { [selection] snapshot in await selection.select(mode: mode, snapshot: snapshot) }
    }

    func repeatLastArea() async {
        guard let area = lastArea else {
            await capture(.area)
            return
        }
        await run { _ in .area(area) }
    }

    private func run(_ choose: (CaptureSnapshot) async -> SelectionResult) async {
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
            let image: CGImage
            let scale: Double
            var metadata = CaptureMetadata(captureDate: Date(), appName: frontmost?.localizedName, bundleIdentifier: frontmost?.bundleIdentifier)

            switch await choose(snapshot) {
            case .cancelled:
                return
            case .area(let rect):
                guard let composed = CaptureComposer.compose(rect, from: snapshot.displays) else { throw CaptureError.emptySelection }
                image = composed.image
                scale = composed.scale
                lastArea = rect
            case .window(let window):
                image = try await engine.captureWindow(window.id, includeShadow: current.includeWindowShadow)
                scale = snapshot.scale(for: window)
                metadata.appName = window.appName
                metadata.bundleIdentifier = window.bundleIdentifier
                metadata.windowTitle = window.title
            case .screen(let display):
                guard let frozen = snapshot.displays.first(where: { $0.info.id == display.id }) else { throw CaptureError.displayNotFound }
                image = frozen.image
                scale = display.scale
            }

            let contents = try CaptureDocumentBuilder.make(image: image, scale: scale, metadata: metadata)
            actions.perform(PostCaptureRouter.plan(for: current), contents: contents, image: image, settings: current)
        } catch {
            AppEnvironment.shared.notifier.failure(error)
        }
    }

    private func showPermissionWindow() {
        let controller = permissionWindow ?? PermissionWindowController(permission: permission)
        permissionWindow = controller
        controller.showWindow(nil)
        NSApp.activate()
    }
}
```

`App/Pinxel/Capture/PermissionWindow.swift`:

```swift
import AppKit
import CaptureKit
import SwiftUI

@MainActor
final class PermissionWindowController: NSWindowController {
    convenience init(permission: any ScreenRecordingPermission) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 260), styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "Permesso di registrazione schermo"
        window.contentView = NSHostingView(rootView: PermissionView(permission: permission))
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)
    }
}

private struct PermissionView: View {
    let permission: any ScreenRecordingPermission

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pinxel deve poter registrare lo schermo").font(.title3).bold()
            Text("Serve per catturare schermate. Le immagini restano sul tuo Mac. Concedi l'accesso in Impostazioni di Sistema → Privacy e sicurezza → Registrazione schermo e audio, poi riavvia Pinxel.")
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Concedi accesso…") {
                    permission.request()
                    permission.openSystemSettings()
                }
                .keyboardShortcut(.defaultAction)
                Button("Riavvia Pinxel", action: relaunch)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}
```

- [ ] **Step 3: Wire the coordinator into the environment**

In `App/Pinxel/AppEnvironment.swift`:

1. Add stored properties after `@ObservationIgnored let logger = …`:

```swift
    @ObservationIgnored let notifier: Notifier
    @ObservationIgnored private var coordinator: CaptureCoordinator!
```

2. At the end of `private init(arguments:)`, after `settings = loaded`, add:

```swift
        notifier = Notifier(enabled: !isUITesting)
        let engine: any CaptureEngine = isUITesting ? FakeCaptureEngine() : ScreenCaptureKitEngine()
        let permission: any ScreenRecordingPermission = isUITesting ? GrantedScreenRecordingPermission() : SystemScreenRecordingPermission()
        let selection: any SelectionProvider = isUITesting
            ? FixedSelectionProvider(result: .area(FakeCaptureEngine.redSquare))
            : OverlaySelectionProvider()
        let actions = PostCaptureActions(notifier: notifier)
        coordinator = CaptureCoordinator(engine: engine, permission: permission, selection: selection, actions: actions) { [unowned self] in
            self.settings
        }
```

3. Replace the bodies of `capture(_:)` and `repeatLastArea()`:

```swift
    func capture(_ mode: CaptureMode) {
        Task {
            // Lascia chiudere il menu, altrimenti finisce nell'immagine congelata.
            try? await Task.sleep(for: .milliseconds(250))
            await coordinator.capture(mode)
        }
    }

    func repeatLastArea() {
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            await coordinator.repeatLastArea()
        }
    }
```

In `App/Pinxel/AppDelegate.swift`, in `applicationDidFinishLaunching`, after the `-PinxelUITestOpenSample` block, add:

```swift
        if ProcessInfo.processInfo.arguments.contains("-PinxelUITestCaptureOnLaunch") {
            AppEnvironment.shared.capture(.area)
        }
```

- [ ] **Step 4: Run all UI tests**

Run: `xcodegen generate && xcodebuild -project Pinxel.xcodeproj -scheme Pinxel -destination 'platform=macOS' -allowProvisioningUpdates test > build/xcodebuild.log 2>&1; echo "exit $?"; grep -E "error:|Test Case .*(passed|failed)" build/xcodebuild.log`
Expected: exit 0; `LaunchUITests` (2) and `CaptureFlowUITests` (2) pass. Then `cd PinxelKit && swift test` — all package tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/giovanni/work/reatool
git add App
git commit -m "feat(app): wire capture coordinator, permission window and end-to-end UI tests"
```

---

### Task 14: Manual checklist with real ScreenCaptureKit

**Files:**
- Create: `docs/manual-tests/capture.md`

**Interfaces:** none (verification only).

- [ ] **Step 1: Write the checklist**

`docs/manual-tests/capture.md`:

```markdown
# Test manuali — cattura (ScreenCaptureKit reale)

Build: `xcodegen generate && xcodebuild -project Pinxel.xcodeproj -scheme Pinxel build`, poi avvia Pinxel.app.
Segna ogni voce con ✅ / ❌ e note.

| # | Passi | Atteso |
|---|-------|--------|
| M1 | Primo avvio senza permesso, premi ⌃⇧1 | Si apre la finestra "Permesso di registrazione schermo"; nessuna cattura nera |
| M2 | Concedi il permesso, premi "Riavvia Pinxel", poi ⌃⇧1 | Overlay su tutti gli schermi con l'immagine congelata, cursore a mirino, lente con colore |
| M3 | Trascina un'area e rilascia | Si apre una finestra con esattamente l'area selezionata, nitida (Retina) |
| M4 | ⌃⇧1, passa sopra una finestra e clicca | Cattura della sola finestra, senza finestre sovrapposte; ombra secondo le Preferenze |
| M5 | ⌃⇧2, scegli una finestra che si chiude da sola (es. un popup) prima del clic | Notifica "La finestra è stata chiusa prima della cattura", nessun documento |
| M6 | Revoca il permesso in Impostazioni di Sistema, premi ⌃⇧1 | Di nuovo la finestra del permesso, nessuna cattura nera |
| M7 | Con due monitor a scale diverse, seleziona un'area a cavallo | Immagine unica, alla scala maggiore, allineata |
| M8 | ⌃⇧3 e clic su uno schermo | Cattura dello schermo intero |
| M9 | ⌃⇧4 dopo una cattura d'area | Ricattura la stessa area senza overlay |
| M10 | Durante il trascinamento: ⇧ (quadrato), frecce, Spazio (sposta), Esc | Comportamenti come da spec §7.2 |
| M11 | Preferenze → Anteprima veloce; cattura | Miniatura in basso a destra per 5 s; trascinala su Finder (crea un PNG); clic apre il documento |
| M12 | Preferenze → Solo appunti; cattura, incolla in Anteprima → Nuovo dagli appunti | Immagine incollata corretta, notifica di conferma |
| M13 | Salvataggio automatico attivo in una cartella in sola lettura | Notifica di errore e la cattura resta aperta in una finestra |
| M14 | Assegna una scorciatoia già usata da un'altra app | Avviso rosso nelle Preferenze |
| M15 | Apri un documento: l'icona compare nel Dock; chiudilo | L'icona sparisce dal Dock |
| M16 | Ricompila l'app e cattura | Con firma Apple Development il permesso resta concesso |
```

- [ ] **Step 2: Run the checklist**

Build and run the app as described, execute M1–M16 and fill in the results in the file. Any ❌ is a bug: fix it with a failing test first where the behaviour is in CaptureKit/AppCore, otherwise fix and re-run the item. Record the outcome in the ledger.

- [ ] **Step 3: Commit**

```bash
cd /Users/giovanni/work/reatool
git add docs/manual-tests/capture.md
git commit -m "docs: add manual capture checklist with results"
```

---

## Spec coverage (self-review)

| Spec section | Covered by |
|---|---|
| §2 decisions (SwiftUI + AppKit, ScreenCaptureKit, NSDocument, configurable post-capture) | Tasks 4, 8–13 |
| §4 modules (CaptureKit, App) | Tasks 1–4, 8 |
| §7.1 menu bar, hotkeys (Carbon, defaults), agent/Dock | Tasks 5, 8, 9, 10 |
| §7.2 frozen overlay, unified mode, loupe, size label, ⇧/arrows/Space/Esc/Enter, window capture, multi-monitor | Tasks 1–3, 11, 13 (decision on Enter recorded in Global Constraints) |
| §7.3 permission flow, never black | Tasks 4, 13, manual M1/M6 |
| §7.4 post-capture modes, auto-save, metadata | Tasks 6, 7, 12, 13 |
| §8 document type / UTI, read-only newer files | Tasks 8, 9 |
| §10 errors: permission, capture failure, unwritable folder, hotkey conflict, corrupt file | Tasks 4, 7, 9, 10, 12, 13, manual M5/M6/M13/M14 |
| §11 tests: CaptureKit pure logic, few XCUITests, manual capture | Tasks 1–7, 8, 9, 13, 14 |
| §6 editor UI, §9 export from UI, copy/paste of annotations | **plan 3** |
| Deferred from plan 1 review: Display P3 colour space | still deferred — plan 2 records sRGB documents; revisit with the editor |
