/// Cosa fa il clic su una miniatura (spec §2): mai chiudere un documento che non sta nell'archivio.
public enum LibraryOpenDecision: Equatable, Sendable {
    case focusExisting
    case replaceInWindow
    case openNewWindow

    public static func decide(targetAlreadyOpen: Bool, windowShowsLibraryItem: Bool) -> LibraryOpenDecision {
        if targetAlreadyOpen { return .focusExisting }
        return windowShowsLibraryItem ? .replaceInWindow : .openNewWindow
    }
}
