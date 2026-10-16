import CoreGraphics
import Testing
@testable import CaptureKit
import PinxelTestSupport

@MainActor
struct FakeScrollingPageTests {
    let display = DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 800, height: 600), scale: 2)

    @Test func framesShowTheViewportBetweenHeaderAndFooter() async throws {
        let content = TestImages.noise(width: 40, height: 200)
        let page = FakeScrollingPage(content: content, viewportHeight: 50,
                                     header: TestImages.solid(width: 40, height: 10, red: 1, green: 0, blue: 0),
                                     footer: TestImages.solid(width: 40, height: 6, red: 0, green: 0, blue: 1))
        page.scroll(by: 15, at: .zero) // 15 pt × 2 = 30 px
        #expect(page.position == 30)
        let frame = PixelBuffer(try await page.frame(of: .zero, on: display))
        #expect(frame.height == 66)
        #expect(frame.pixel(x: 3, y: 2) == RGBA8(r: 255, g: 0, b: 0))
        #expect(frame.pixel(x: 3, y: 63) == RGBA8(r: 0, g: 0, b: 255))
        #expect(frame.pixel(x: 7, y: 10) == PixelBuffer(content).pixel(x: 7, y: 30))
        #expect(page.frameCount == 1)
    }

    @Test func scrollingStopsAtTheEndsAndHonoursTheFactor() {
        let page = FakeScrollingPage(content: TestImages.noise(width: 20, height: 100), viewportHeight: 40, scale: 1, scrollFactor: 1.5)
        page.scroll(by: 10, at: .zero)
        #expect(page.position == 15)
        page.scroll(by: 1000, at: .zero)
        #expect(page.position == 60)
        page.scroll(by: -1000, at: .zero)
        #expect(page.position == 0)
        #expect(page.scrollCalls == [10, 1000, -1000])
    }

    @Test func expectedImageStacksHeaderContentAndFooter() {
        let page = FakeScrollingPage(content: TestImages.noise(width: 20, height: 100), viewportHeight: 40,
                                     header: TestImages.solid(width: 20, height: 5, red: 1, green: 0, blue: 0))
        #expect(page.expectedImage.height == 105)
    }
}
