import Testing
@testable import Library

struct LibraryOpenDecisionTests {
    @Test func aCaptureAlreadyOpenIsBroughtForward() {
        for current in [WindowContent.libraryItem, .otherFile, .untitled(blank: true), .untitled(blank: false)] {
            #expect(LibraryOpenDecision.decide(targetAlreadyOpen: true, current: current) == .focusExisting)
        }
    }

    /// The click always stays in the same window; an untitled document with something in it first enters the library.
    @Test func otherwiseTheSameWindowIsUsed() {
        #expect(LibraryOpenDecision.decide(targetAlreadyOpen: false, current: .libraryItem) == .replaceInWindow)
        #expect(LibraryOpenDecision.decide(targetAlreadyOpen: false, current: .otherFile) == .replaceInWindow)
        #expect(LibraryOpenDecision.decide(targetAlreadyOpen: false, current: .untitled(blank: true)) == .replaceInWindow)
        #expect(LibraryOpenDecision.decide(targetAlreadyOpen: false, current: .untitled(blank: false)) == .keepInLibraryThenReplace)
    }
}
