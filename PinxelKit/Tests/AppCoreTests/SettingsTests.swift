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

    @Test func loginItemQuestionIsRemembered() {
        let store = SettingsStore(defaults: freshDefaults())
        #expect(!store.load().loginItemAsked)
        var settings = CaptureSettings()
        settings.loginItemAsked = true
        store.save(settings)
        #expect(store.load().loginItemAsked)
    }

    @Test func chosenFolderKeepsPathAndBookmark() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pinxel-folder-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = SettingsStore(defaults: freshDefaults())
        var settings = CaptureSettings()
        settings.chooseSaveFolder(folder)
        #expect(settings.saveFolderPath == folder.path)
        #expect(settings.saveFolderBookmark != nil)
        store.save(settings)
        #expect(store.load().saveFolderBookmark == settings.saveFolderBookmark)
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

    @Test func oneUnreadableFieldKeepsTheOthers() throws {
        let defaults = freshDefaults()
        var settings = CaptureSettings()
        settings.autoSave = true
        settings.saveFormat = .png
        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        object["postCaptureAction"] = "dimenticata"
        defaults.set(try JSONSerialization.data(withJSONObject: object), forKey: SettingsStore.key)
        let loaded = SettingsStore(defaults: defaults).load()
        #expect(loaded.autoSave && loaded.saveFormat == .png)
        #expect(loaded.postCaptureAction == .openEditor)
    }

    @Test func invalidAndDuplicateShortcutsFallBackToDefaults() {
        let store = SettingsStore(defaults: freshDefaults())
        var settings = CaptureSettings()
        let custom = KeyCombo(keyCode: 0x0D, modifiers: KeyCombo.command | KeyCombo.option)
        settings.hotKeys[.area] = KeyCombo(keyCode: 0x00, modifiers: KeyCombo.shift)
        settings.hotKeys[.window] = custom
        settings.hotKeys[.screen] = custom
        store.save(settings)
        let loaded = store.load()
        #expect(loaded.combo(for: .area) == HotKeyAction.area.defaultCombo)
        #expect(loaded.combo(for: .window) == custom)
        #expect(loaded.combo(for: .screen) == HotKeyAction.screen.defaultCombo)
    }

    @Test func effectiveShortcutsStayUniqueWhenAFallbackCollides() {
        var settings = CaptureSettings()
        // The area has an invalid combination and reverts to the default, which the window took for itself.
        settings.hotKeys[.area] = KeyCombo(keyCode: 0x00, modifiers: KeyCombo.shift)
        settings.hotKeys[.window] = HotKeyAction.area.defaultCombo
        settings.sanitizeHotKeys()
        let effective = HotKeyAction.allCases.map { settings.combo(for: $0) }
        #expect(Set(effective).count == effective.count)
        #expect(settings.combo(for: .area) == HotKeyAction.area.defaultCombo)
        #expect(settings.combo(for: .window) == HotKeyAction.window.defaultCombo)
    }

    @Test func settingsFromBeforeScrollingKeepTheirShortcuts() throws {
        var old = CaptureSettings()
        old.hotKeys = [.area: KeyCombo(keyCode: 0x15, modifiers: KeyCombo.command | KeyCombo.shift)]
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
        // An earlier version did not know `scrolling`: remove it from the JSON, whatever form it is encoded in.
        if var keys = json["hotKeys"] as? [String: Any] { keys["scrolling"] = nil; json["hotKeys"] = keys }
        if var pairs = json["hotKeys"] as? [Any], let index = pairs.firstIndex(where: { ($0 as? String) == "scrolling" }) {
            pairs.removeSubrange(index...index + 1); json["hotKeys"] = pairs
        }
        let decoded = try JSONDecoder().decode(CaptureSettings.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.combo(for: .area) == KeyCombo(keyCode: 0x15, modifiers: KeyCombo.command | KeyCombo.shift))
        #expect(decoded.combo(for: .scrolling) == HotKeyAction.scrolling.defaultCombo)
    }
}
