import AppCore
import AppKit
import CaptureKit
import DocumentModel
import Foundation
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
    /// L'ultima cattura di questa sessione, per riaprirla nell'editor anche se è andata solo negli appunti.
    private(set) var lastCapture: PinxelFileContents?

    @ObservationIgnored private let store: SettingsStore
    @ObservationIgnored private let hotKeys = HotKeyCenter()
    @ObservationIgnored let logger = Logger(subsystem: "com.degiorgi.pinxel", category: "app")
    @ObservationIgnored let notifier: Notifier
    @ObservationIgnored private var coordinator: CaptureCoordinator!

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
        let actions = PostCaptureActions(notifier: notifier)
        actions.onCapture = { [unowned self] contents in self.lastCapture = contents }
        coordinator = CaptureCoordinator(engine: engine, permission: permission, selection: selection, actions: actions) { [unowned self] in
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

    /// `fromMenu`: aspetta che il menu si chiuda, altrimenti finisce nell'immagine congelata.
    /// Dalle scorciatoie la cattura parte subito.
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

    func captureScrolling(fromMenu: Bool = false) {}

    func openLastCapture() {
        guard let lastCapture else { return }
        DocumentOpener.open(lastCapture)
    }

    /// Apre un editor vuoto e trasparente, grande quanto una finestra media: poi ci si incolla uno screenshot.
    func openBlank() {
        do {
            DocumentOpener.open(try CaptureDocumentBuilder.blank(pointSize: CGSize(width: 800, height: 500),
                                                                 scale: Double(NSScreen.main?.backingScaleFactor ?? 2)))
        } catch {
            notifier.failure(error)
        }
    }

    /// Apre nell'editor l'immagine negli appunti.
    func openClipboard() {
        guard let (image, scale) = Clipboard.image() else {
            notifier.info("Negli appunti non c'è un'immagine")
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
