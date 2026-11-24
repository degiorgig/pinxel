/// What a window shows after the capture it showed is deleted: its neighbour in the strip, so the window stays.
public enum LibraryDeletion {
    /// The next capture in the strip (the older one), otherwise the previous one, skipping the deleted ones and
    /// those `unavailable` (already open in another window). Nil when nothing is left: then the window closes.
    /// `order` is the strip as it was before the deletion; a capture not in it (filtered out) takes the first one left.
    public static func replacement(for file: String, in order: [String], deleted: Set<String>, unavailable: Set<String> = []) -> String? {
        let usable = { (candidate: String) in !deleted.contains(candidate) && !unavailable.contains(candidate) && candidate != file }
        guard let position = order.firstIndex(of: file) else { return order.first(where: usable) }
        return order[(position + 1)...].first(where: usable) ?? order[..<position].reversed().first(where: usable)
    }
}
