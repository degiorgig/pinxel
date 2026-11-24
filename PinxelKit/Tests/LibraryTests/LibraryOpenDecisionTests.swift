import Testing
@testable import Library

struct LibraryOpenDecisionTests {
    @Test func aCaptureAlreadyOpenIsBroughtForward() {
        for current in [WindowContent.libraryItem, .otherFile, .untitled(blank: true), .untitled(blank: false), .keptOutOfLibrary] {
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

    /// An incomplete capture never enters the library behind the user's back: it keeps its window.
    @Test func aDocumentKeptOutOfTheLibraryKeepsItsWindow() {
        #expect(LibraryOpenDecision.decide(targetAlreadyOpen: false, current: .keptOutOfLibrary) == .openInNewWindow)
        #expect(!LibraryOpenDecision.capturesReuseWindow(showing: .keptOutOfLibrary))
    }

    /// A new capture takes the open window, except from an untitled document with something in it (an incomplete
    /// capture, kept out of the library on purpose): that one keeps its window.
    @Test func aNewCaptureReusesTheWindowUnlessItHoldsUnsavedWork() {
        #expect(LibraryOpenDecision.capturesReuseWindow(showing: .libraryItem))
        #expect(LibraryOpenDecision.capturesReuseWindow(showing: .otherFile))
        #expect(LibraryOpenDecision.capturesReuseWindow(showing: .untitled(blank: true)))
        #expect(!LibraryOpenDecision.capturesReuseWindow(showing: .untitled(blank: false)))
    }
}
