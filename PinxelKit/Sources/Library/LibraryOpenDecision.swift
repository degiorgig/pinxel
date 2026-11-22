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

    /// A new capture shows up in the editor window already open, as a click on its thumbnail would. Not over an
    /// untitled document with something in it: that is kept out of the library on purpose (an incomplete capture),
    /// so it keeps its window and the capture gets a new one.
    public static func capturesReuseWindow(showing current: WindowContent) -> Bool {
        current != .untitled(blank: false)
    }
}
