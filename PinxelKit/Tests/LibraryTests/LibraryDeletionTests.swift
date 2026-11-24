import Testing
@testable import Library

struct LibraryDeletionTests {
    private let strip = ["e", "d", "c", "b", "a"]

    @Test func theNextCaptureTakesThePlace() {
        #expect(LibraryDeletion.replacement(for: "c", in: strip, deleted: ["c"]) == "b")
    }

    @Test func theLastOneFallsBackToThePrevious() {
        #expect(LibraryDeletion.replacement(for: "a", in: strip, deleted: ["a"]) == "b")
    }

    /// Several deleted together: they are skipped, and so are captures already open in another window.
    @Test func deletedAndOpenCapturesAreSkipped() {
        #expect(LibraryDeletion.replacement(for: "c", in: strip, deleted: ["c", "b"]) == "a")
        #expect(LibraryDeletion.replacement(for: "c", in: strip, deleted: ["c", "b"], unavailable: ["a"]) == "d")
    }

    @Test func nothingLeftClosesTheWindow() {
        #expect(LibraryDeletion.replacement(for: "c", in: strip, deleted: Set(strip)) == nil)
        #expect(LibraryDeletion.replacement(for: "c", in: ["c"], deleted: ["c"]) == nil)
    }

    /// The open capture is filtered out of the strip: the first one shown takes its place.
    @Test func aCaptureOutsideTheFilterTakesTheFirstOne() {
        #expect(LibraryDeletion.replacement(for: "x", in: strip, deleted: ["x"]) == "e")
    }
}
