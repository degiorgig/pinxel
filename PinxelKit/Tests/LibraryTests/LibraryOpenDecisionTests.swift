import Testing
@testable import Library

struct LibraryOpenDecisionTests {
    @Test func rules() {
        #expect(LibraryOpenDecision.decide(targetAlreadyOpen: true, windowShowsLibraryItem: true) == .focusExisting)
        #expect(LibraryOpenDecision.decide(targetAlreadyOpen: true, windowShowsLibraryItem: false) == .focusExisting)
        #expect(LibraryOpenDecision.decide(targetAlreadyOpen: false, windowShowsLibraryItem: true) == .replaceInWindow)
        // Documento esterno o senza titolo: non si chiude, la cattura va in una finestra nuova.
        #expect(LibraryOpenDecision.decide(targetAlreadyOpen: false, windowShowsLibraryItem: false) == .openNewWindow)
    }
}
