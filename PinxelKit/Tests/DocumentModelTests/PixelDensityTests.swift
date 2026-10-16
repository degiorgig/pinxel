import Testing
@testable import DocumentModel

struct PixelDensityTests {
    @Test func roundsAndClampsTheScale() {
        #expect(PixelDensity.scale(pixelWidth: 800, pointWidth: 400) == 2)
        #expect(PixelDensity.scale(pixelWidth: 640, pointWidth: 640) == 1)
        #expect(PixelDensity.scale(pixelWidth: 1000, pointWidth: 480) == 2)
        #expect(PixelDensity.scale(pixelWidth: 100, pointWidth: 400) == 1)
        #expect(PixelDensity.scale(pixelWidth: 4000, pointWidth: 400) == 3)
        #expect(PixelDensity.scale(pixelWidth: 400, pointWidth: 0) == 1)
    }
}
