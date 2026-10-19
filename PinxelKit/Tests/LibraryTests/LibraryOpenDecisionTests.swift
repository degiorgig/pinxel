import Testing
@testable import Library

struct LibraryOpenDecisionTests {
    @Test func aCaptureAlreadyOpenIsBroughtForward() {
        for current in [WindowContent.libraryItem, .otherFile, .untitled(blank: true), .untitled(blank: false)] {
            #expect(LibraryOpenDecision.decide(targetAlreadyOpen: true, current: current) == .focusExisting)
        }
    }

    /// Il clic resta sempre nella stessa finestra; un documento senza titolo con qualcosa dentro entra prima nella libreria.
    @Test func otherwiseTheSameWindowIsUsed() {
        #expect(LibraryOpenDecision.decide(targetAlreadyOpen: false, current: .libraryItem) == .replaceInWindow)
        #expect(LibraryOpenDecision.decide(targetAlreadyOpen: false, current: .otherFile) == .replaceInWindow)
        #expect(LibraryOpenDecision.decide(targetAlreadyOpen: false, current: .untitled(blank: true)) == .replaceInWindow)
        #expect(LibraryOpenDecision.decide(targetAlreadyOpen: false, current: .untitled(blank: false)) == .keepInLibraryThenReplace)
    }
}
