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

    private enum CodingKeys: String, CodingKey {
        case postCaptureAction, autoSave, saveFolderPath, saveFormat, fileNameTemplate, includeWindowShadow, hotKeys
    }

    /// Ogni campo illeggibile torna al valore predefinito senza perdere gli altri (es. un valore di una
    /// versione futura); le scorciatoie non valide o doppie tornano a quelle predefinite.
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

    /// Toglie le scorciatoie senza ⌃, ⌥ o ⌘ e quelle uguali a un'azione precedente: tornano alle predefinite.
    public mutating func sanitizeHotKeys() {
        var seen = Set<KeyCombo>()
        for action in HotKeyAction.allCases {
            guard let combo = hotKeys[action] else { continue }
            if !combo.hasModifier || seen.contains(combo) {
                hotKeys[action] = nil
            } else {
                seen.insert(combo)
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
