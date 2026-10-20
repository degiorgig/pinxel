/// What the window in which a thumbnail is clicked shows.
public enum WindowContent: Equatable, Sendable {
    /// A library capture: it saves itself where it is.
    case libraryItem
    /// Another `.pinxel` file: it saves itself where it is.
    case otherFile
    /// An untitled document; `blank` if it is empty (New with nothing in it).
    case untitled(blank: Bool)
}

/// What clicking a thumbnail does: it always stays in the same window, never losing what was there.
public enum LibraryOpenDecision: Equatable, Sendable {
    case focusExisting
    case replaceInWindow
    /// The untitled document first enters the library, then the chosen capture takes its place.
    case keepInLibraryThenReplace

    public static func decide(targetAlreadyOpen: Bool, current: WindowContent) -> LibraryOpenDecision {
        if targetAlreadyOpen { return .focusExisting }
        return current == .untitled(blank: false) ? .keepInLibraryThenReplace : .replaceInWindow
    }
}
