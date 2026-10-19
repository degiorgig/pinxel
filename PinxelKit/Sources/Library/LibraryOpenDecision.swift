/// Cosa mostra la finestra in cui si clicca una miniatura.
public enum WindowContent: Equatable, Sendable {
    /// Una cattura dell'archivio: si salva da sola dove sta.
    case libraryItem
    /// Un altro file `.pinxel`: si salva da solo dove sta.
    case otherFile
    /// Un documento senza titolo; `blank` se è vuoto (Nuovo senza niente dentro).
    case untitled(blank: Bool)
}

/// Cosa fa il clic su una miniatura: resta sempre nella stessa finestra, senza mai perdere quello che c'era.
public enum LibraryOpenDecision: Equatable, Sendable {
    case focusExisting
    case replaceInWindow
    /// Il documento senza titolo entra prima nella libreria, poi la cattura scelta prende il suo posto.
    case keepInLibraryThenReplace

    public static func decide(targetAlreadyOpen: Bool, current: WindowContent) -> LibraryOpenDecision {
        if targetAlreadyOpen { return .focusExisting }
        return current == .untitled(blank: false) ? .keepInLibraryThenReplace : .replaceInWindow
    }
}
