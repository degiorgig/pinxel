import CoreGraphics
import Testing
@testable import Library

struct LibraryStripLayoutTests {
    @Test func theHeightStaysWithinBounds() {
        #expect(LibraryStripLayout.clampedHeight(20) == LibraryStripLayout.minHeight)
        #expect(LibraryStripLayout.clampedHeight(200) == 200)
        #expect(LibraryStripLayout.clampedHeight(5000) == LibraryStripLayout.maxHeight)
    }

    /// A small window leaves less room, but never less than the minimum.
    @Test func theWindowLimitsTheHeight() {
        #expect(LibraryStripLayout.clampedHeight(300, limit: 180) == 180)
        #expect(LibraryStripLayout.clampedHeight(300, limit: 40) == LibraryStripLayout.minHeight)
    }

    /// The thumbnails fit inside the strip, whatever its height.
    @Test func thumbnailsFitTheStrip() {
        for height in [LibraryStripLayout.minHeight, LibraryStripLayout.defaultHeight, 250, LibraryStripLayout.maxHeight] {
            let size = LibraryStripLayout.thumbnailSize(stripHeight: height)
            #expect(size.height + LibraryStripLayout.chrome == height)
            #expect(size.width > size.height)
        }
        #expect(LibraryStripLayout.thumbnailSize(stripHeight: 300).height > LibraryStripLayout.thumbnailSize(stripHeight: 140).height)
    }
}
