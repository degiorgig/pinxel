import AppCore
import AppKit
import CaptureKit
import DocumentModel
import Foundation
import Library
import Observation
import os
import Persistence

@MainActor
@Observable
final class AppEnvironment {
    static let shared = AppEnvironment()

    let isUITesting: Bool
    private(set) var settings: CaptureSettings
    private(set) var hotKeyConflicts: Set<HotKeyAction> = []
    /// The last capture of this session, to reopen it in the editor even if it only went to the pasteboard:
    /// the library file, or the contents if it did not enter the library.
    private(set) var lastCapture: LastCapture?

    enum LastCapture {
        case file(URL)
        case contents(PinxelFileContents)
    }

    @ObservationIgnored private let store: SettingsStore
    @ObservationIgnored private let hotKeys = HotKeyCenter()
    @ObservationIgnored let logger = Logger(subsystem: "com.degiorgi.pinxel", category: "app")
    @ObservationIgnored let notifier: Notifier
    @ObservationIgnored private var coordinator: CaptureCoordinator!
    @ObservationIgnored let library: LibraryModel

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
        notifier = Notifier(enabled: !isUITesting)
        let engine: any CaptureEngine = isUITesting ? FakeCaptureEngine() : ScreenCaptureKitEngine()
        let permission: any ScreenRecordingPermission = isUITesting ? GrantedScreenRecordingPermission() : SystemScreenRecordingPermission()
        let selection: any SelectionProvider = isUITesting
            ? FixedSelectionProvider(result: .area(FakeCaptureEngine.redSquare))
            : OverlaySelectionProvider()
        let libraryFolder: URL
        if let index = arguments.firstIndex(of: "-PinxelLibraryFolder"), index + 1 < arguments.count {
            libraryFolder = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        } else if isUITesting || arguments.contains("-PinxelUITestLibraryName") {
            // Tests must never write to the real library. The folder is in Pinxel's temporary directory (the test's own one is in
            // its sandbox, and writing there would ask for a permission); with a given name, several launches find it again.
            let name = arguments.firstIndex(of: "-PinxelUITestLibraryName").flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
                ?? UUID().uuidString
            libraryFolder = FileManager.default.temporaryDirectory.appendingPathComponent("pinxel-uitest-library-\(name)", isDirectory: true)
        } else {
            libraryFolder = LibraryStore.defaultFolder
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        library = LibraryModel(store: LibraryStore(folder: libraryFolder, appVersion: version), notifier: notifier)
        let actions = PostCaptureActions(notifier: notifier, library: library)
        actions.onCapture = { [unowned self] capture in self.lastCapture = capture }
        let scrolling: ScrollCaptureDependencies
        if arguments.contains("-PinxelUITestFakeScrolling") {
            // 200×150 pt at 2x like the fake area: a 400×1200 px noise page, which "the user" scrolls by 60 px per frame.
            let page = FakeScrollingPage(content: Self.fakeScrollingContent(), viewportHeight: 300, scale: 2)
            page.onFrame = { [unowned page] count in if count > 1 { page.scrollTo(page.position + 60) } }
            scrolling = ScrollCaptureDependencies(makeSource: { page }, presenter: ScrollCaptureController())
        } else {
            let bundle = Bundle.main.bundleIdentifier ?? "com.degiorgi.pinxel"
            scrolling = ScrollCaptureDependencies(makeSource: { DebugFrameDump.wrap(ScreenCaptureKitFrameSource(excludingBundleIdentifier: bundle)) },
                                                  presenter: ScrollCaptureController())
        }
        coordinator = CaptureCoordinator(engine: engine, permission: permission, selection: selection, actions: actions, scrolling: scrolling) { [unowned self] in
            self.settings
        }
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

    /// `fromMenu`: waits for the menu to close, otherwise it ends up in the frozen image.
    /// From keyboard shortcuts the capture starts immediately.
    func capture(_ mode: CaptureMode, fromMenu: Bool = false) {
        Task {
            if fromMenu { try? await Task.sleep(for: .milliseconds(250)) }
            await coordinator.capture(mode)
        }
    }

    func repeatLastArea(fromMenu: Bool = false) {
        Task {
            if fromMenu { try? await Task.sleep(for: .milliseconds(250)) }
            await coordinator.repeatLastArea()
        }
    }

    func captureScrolling(fromMenu: Bool = false) {
        Task {
            if fromMenu { try? await Task.sleep(for: .milliseconds(250)) }
            await coordinator.captureScrolling()
        }
    }

    /// Deterministic noise: every row is different, so the seam is verifiable.
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

    func openLastCapture() {
        switch lastCapture {
        case .file(let url): DocumentOpener.open(url: url)
        case .contents(let contents): DocumentOpener.open(contents)
        case nil: break
        }
    }

    /// Opens an empty editor, with no objects: then you paste a screenshot, drag an image or draw.
    func openBlank() {
        do {
            DocumentOpener.open(try CaptureDocumentBuilder.blank(scale: Double(NSScreen.main?.backingScaleFactor ?? 2)))
        } catch {
            notifier.failure(error)
        }
    }

    /// Opens the image on the pasteboard in the editor.
    func openClipboard() {
        // Activate before reading: the read can wait for the app that copied the image to provide it, and by then
        // macOS no longer ties the activation to the click and leaves the new window behind the other apps.
        NSApp.activate()
        guard let (image, scale) = Clipboard.image() else {
            notifier.info(String(localized: "There's no image on the clipboard"))
            return
        }
        do {
            DocumentOpener.open(try CaptureDocumentBuilder.make(image: image, scale: scale, metadata: CaptureMetadata()))
        } catch {
            notifier.failure(error)
        }
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
        case .scrolling: captureScrolling()
        case .repeatLastArea: repeatLastArea()
        }
    }
}
