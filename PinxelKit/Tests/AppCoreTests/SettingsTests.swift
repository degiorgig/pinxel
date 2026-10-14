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
