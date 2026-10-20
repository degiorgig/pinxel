import Foundation

public struct LibraryFolder: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String

    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

/// A library capture: the file name is its identity.
public struct LibraryItem: Codable, Equatable, Sendable, Identifiable {
    public var file: String
    public var added: Date
    public var captureDate: Date
    public var appName: String?
    public var windowTitle: String?
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var folder: UUID?
    public var tags: [String]

    public var id: String { file }

    public init(file: String, added: Date, captureDate: Date, appName: String?, windowTitle: String?,
                pixelWidth: Int, pixelHeight: Int, folder: UUID? = nil, tags: [String] = []) {
        self.file = file
        self.added = added
        self.captureDate = captureDate
        self.appName = appName
        self.windowTitle = windowTitle
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.folder = folder
        self.tags = tags
    }
}

public enum LibraryIndexError: Error, Equatable {
    case futureVersion(Int)
    case emptyName
    case duplicateName
}

/// Contents of `library.json`: folders and captures. Labels have no list of their own:
/// they are the ones used by the captures.
public struct LibraryIndex: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public private(set) var version = LibraryIndex.currentVersion
    public private(set) var folders: [LibraryFolder] = []
    public private(set) var items: [LibraryItem] = []

    public init() {}

    private enum CodingKeys: String, CodingKey { case version, folders, items }

    /// An unreadable entry is skipped without losing the others; an index from a future version is left untouched.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decode(Int.self, forKey: .version)
        guard version <= Self.currentVersion else { throw LibraryIndexError.futureVersion(version) }
        folders = (try? c.decode([Lenient<LibraryFolder>].self, forKey: .folders))?.compactMap(\.value) ?? []
        items = (try? c.decode([Lenient<LibraryItem>].self, forKey: .items))?.compactMap(\.value) ?? []
    }

    public func item(_ file: String) -> LibraryItem? {
        items.first { $0.file == file }
    }

    public func folder(_ id: UUID) -> LibraryFolder? {
        folders.first { $0.id == id }
    }

    public mutating func add(_ item: LibraryItem) {
        if let i = items.firstIndex(where: { $0.file == item.file }) {
            items[i] = item
        } else {
            items.append(item)
        }
    }

    public mutating func update(_ file: String, pixelWidth: Int, pixelHeight: Int) {
        guard let i = items.firstIndex(where: { $0.file == file }) else { return }
        items[i].pixelWidth = pixelWidth
        items[i].pixelHeight = pixelHeight
    }

    public mutating func remove(_ files: Set<String>) {
        items.removeAll { files.contains($0.file) }
    }

    public mutating func move(_ files: Set<String>, to folder: UUID?) {
        for i in items.indices where files.contains(items[i].file) { items[i].folder = folder }
    }

    public mutating func addTag(_ tag: String, to files: Set<String>) {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Same label written differently: the spelling already present is used.
        let spelling = allTags.first { Self.same($0, trimmed) } ?? trimmed
        for i in items.indices where files.contains(items[i].file) && !items[i].tags.contains(where: { Self.same($0, spelling) }) {
            items[i].tags.append(spelling)
        }
    }

    public mutating func removeTag(_ tag: String, from files: Set<String>) {
        for i in items.indices where files.contains(items[i].file) {
            items[i].tags.removeAll { Self.same($0, tag) }
        }
    }

    public mutating func createFolder(named name: String) throws -> LibraryFolder {
        let folder = LibraryFolder(name: try validName(name, excluding: nil))
        folders.append(folder)
        return folder
    }

    public mutating func renameFolder(_ id: UUID, to name: String) throws {
        let valid = try validName(name, excluding: id)
        guard let i = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[i].name = valid
    }

    public mutating func deleteFolder(_ id: UUID) {
        folders.removeAll { $0.id == id }
        for i in items.indices where items[i].folder == id { items[i].folder = nil }
    }

    /// Labels in use, one per spelling (the first encountered), in alphabetical order.
    public var allTags: [String] {
        var seen: [String] = []
        for tag in items.flatMap(\.tags) where !seen.contains(where: { Self.same($0, tag) }) { seen.append(tag) }
        return seen.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Files rule: those without an entry are added, entries without a file are removed; a vanished folder becomes "none".
    public func reconciled(withFiles files: Set<String>, makeItem: (String) -> LibraryItem) -> LibraryIndex {
        var result = self
        result.items.removeAll { !files.contains($0.file) }
        let known = Set(result.items.map(\.file))
        for file in files.sorted() where !known.contains(file) { result.items.append(makeItem(file)) }
        let folderIDs = Set(result.folders.map(\.id))
        for i in result.items.indices where result.items[i].folder.map({ !folderIDs.contains($0) }) ?? false {
            result.items[i].folder = nil
        }
        return result
    }

    private func validName(_ name: String, excluding id: UUID?) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LibraryIndexError.emptyName }
        guard !folders.contains(where: { $0.id != id && Self.same($0.name, trimmed) }) else { throw LibraryIndexError.duplicateName }
        return trimmed
    }

    static func same(_ a: String, _ b: String) -> Bool {
        a.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(b.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }
}

/// Decoding that does not fail: an unreadable element becomes `nil`.
private struct Lenient<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}
