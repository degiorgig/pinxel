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
