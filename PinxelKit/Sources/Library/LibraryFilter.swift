import Foundation

public enum FolderScope: Hashable, Sendable {
    case all
    case unfiled
    case folder(UUID)
}

/// Cosa mostra il carosello: cartella, etichetta e testo insieme (E logico), dalla cattura più nuova.
public struct LibraryFilter: Equatable, Sendable {
    public var folder: FolderScope = .all
    public var tag: String?
    public var text = ""

    public init() {}

    public func apply(to index: LibraryIndex, timeZone: TimeZone = .current) -> [LibraryItem] {
        let words = Self.fold(text).split(whereSeparator: \.isWhitespace).map(String.init)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return index.items
            .filter { item in
                switch folder {
                case .all: true
                case .unfiled: item.folder == nil
                case .folder(let id): item.folder == id
                }
            }
            .filter { item in tag.map { tag in item.tags.contains { LibraryIndex.same($0, tag) } } ?? true }
            .filter { item in
                guard !words.isEmpty else { return true }
                var fields = [item.appName, item.windowTitle, item.folder.flatMap { index.folder($0)?.name }, formatter.string(from: item.captureDate)]
                    .compactMap { $0 }
                fields += item.tags
                let haystack = fields.map(Self.fold)
                return words.allSatisfy { word in haystack.contains { $0.contains(word) } }
            }
            .sorted { $0.added != $1.added ? $0.added > $1.added : $0.file > $1.file }
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
