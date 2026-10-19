import AppKit
import Library

/// Miniature lette dai `.pinxel`, una per file e data di modifica; letture fuori dal thread principale.
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()

    private func key(_ url: URL, _ revision: Date) -> NSString {
        "\(url.path)|\(revision.timeIntervalSinceReferenceDate)" as NSString
    }

    func cached(_ url: URL, revision: Date) -> NSImage? {
        cache.object(forKey: key(url, revision))
    }

    func load(_ url: URL, revision: Date) async -> NSImage? {
        if let image = cached(url, revision: revision) { return image }
        let data = await Task.detached(priority: .utility) { LibraryStore.thumbnail(at: url) }.value
        guard let data, let image = NSImage(data: data) else { return nil }
        cache.setObject(image, forKey: key(url, revision))
        return image
    }
}
