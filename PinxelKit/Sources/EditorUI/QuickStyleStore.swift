import DocumentModel
import Foundation
import Observation

/// Ultimi 8 stili usati per strumento, salvati nelle preferenze (spec §6.1). Condiviso da tutte le finestre.
@MainActor
@Observable
public final class QuickStyleStore {
    public static let shared = QuickStyleStore()
    public static let limit = 8
    static let defaultsKey = "PinxelQuickStyles"

    public private(set) var styles: [EditorTool: [Style]] = [:]
    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let raw = try? JSONDecoder().decode([String: [Style]].self, from: data) {
            for (name, list) in raw {
                if let tool = EditorTool(rawValue: name) { styles[tool] = Array(list.prefix(Self.limit)) }
            }
        }
    }

    public func styles(for tool: EditorTool) -> [Style] {
        styles[tool] ?? []
    }

    /// Mette `style` in cima alla lista dello strumento, senza doppioni.
    public func record(_ style: Style, for tool: EditorTool) {
        var list = styles(for: tool)
        list.removeAll { $0 == style }
        list.insert(style, at: 0)
        if list.count > Self.limit { list.removeLast(list.count - Self.limit) }
        styles[tool] = list
        let raw = Dictionary(uniqueKeysWithValues: styles.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(raw) { defaults.set(data, forKey: Self.defaultsKey) }
    }
}
