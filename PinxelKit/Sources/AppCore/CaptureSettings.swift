import Foundation

public enum PostCaptureAction: String, Codable, CaseIterable, Sendable {
    case openEditor, quickPreview, clipboardOnly

    public var title: String {
        switch self {
        case .openEditor: String(localized: "Open Editor", bundle: .module, comment: "After capture")
        case .quickPreview: String(localized: "Quick Preview", bundle: .module, comment: "After capture")
        case .clipboardOnly: String(localized: "Clipboard Only", bundle: .module, comment: "After capture")
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
    /// The saved template; while it equals the historical default it follows the language (see `effectiveFileNameTemplate`).
    public var fileNameTemplate = FileNamer.legacyDefaultTemplate
    public var includeWindowShadow = true
    public var hotKeys: [HotKeyAction: KeyCombo] = Dictionary(uniqueKeysWithValues: HotKeyAction.allCases.map { ($0, $0.defaultCombo) })

    public init() {}

    /// The template to use: the saved one, or the default in the current language if it is still the old default.
    public var effectiveFileNameTemplate: String {
        fileNameTemplate == FileNamer.legacyDefaultTemplate ? FileNamer.defaultTemplate : fileNameTemplate
    }

    private enum CodingKeys: String, CodingKey {
        case postCaptureAction, autoSave, saveFolderPath, saveFormat, fileNameTemplate, includeWindowShadow, hotKeys
    }

    /// Each unreadable field reverts to its default value without losing the others (e.g. a value from a
    /// future version); invalid or duplicate shortcuts revert to the defaults.
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try? c.decode(PostCaptureAction.self, forKey: .postCaptureAction) { postCaptureAction = value }
        if let value = try? c.decode(Bool.self, forKey: .autoSave) { autoSave = value }
        if let value = try? c.decode(String.self, forKey: .saveFolderPath) { saveFolderPath = value }
        if let value = try? c.decode(SaveFormat.self, forKey: .saveFormat) { saveFormat = value }
        if let value = try? c.decode(String.self, forKey: .fileNameTemplate) { fileNameTemplate = value }
        if let value = try? c.decode(Bool.self, forKey: .includeWindowShadow) { includeWindowShadow = value }
        if let value = try? c.decode([HotKeyAction: KeyCombo].self, forKey: .hotKeys) { hotKeys = value }
        sanitizeHotKeys()
    }

    /// Removes shortcuts without ⌃, ⌥ or ⌘ and resolves duplicates among the effective ones (defaults included):
    /// between two custom ones the first stays; a custom one that equals another action's default
    /// reverts to its own. The defaults are all distinct, so the loop terminates.
    public mutating func sanitizeHotKeys() {
        for action in HotKeyAction.allCases where hotKeys[action]?.hasModifier == false {
            hotKeys[action] = nil
        }
        var resolved = false
        while !resolved {
            resolved = true
            var owners: [KeyCombo: HotKeyAction] = [:]
            for action in HotKeyAction.allCases {
                let combo = combo(for: action)
                guard let other = owners[combo] else {
                    owners[combo] = action
                    continue
                }
                if hotKeys[action] != nil {
                    hotKeys[action] = nil
                } else if hotKeys[other] != nil {
                    hotKeys[other] = nil
                } else {
                    continue
                }
                resolved = false
                break
            }
        }
    }

    public var saveFolderURL: URL {
        URL(fileURLWithPath: (saveFolderPath as NSString).expandingTildeInPath, isDirectory: true)
    }

    public func combo(for action: HotKeyAction) -> KeyCombo {
        hotKeys[action] ?? action.defaultCombo
    }
}

/// Settings persistence in `UserDefaults` as JSON; unreadable data → default values.
public struct SettingsStore {
    public static let key = "PinxelCaptureSettings"
    public let defaults: UserDefaults

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
