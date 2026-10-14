import CoreGraphics
import Testing
@testable import CaptureKit
import PinxelTestSupport

struct CaptureComposerTests {
    let red = RGBA8(r: 255, g: 0, b: 0)
    let blue = RGBA8(r: 0, g: 0, b: 255)

    var twoDisplays: [FrozenDisplay] {
        [
            FrozenDisplay(info: DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100), scale: 1),
                          image: TestImages.solid(width: 100, height: 100, red: 1, green: 0, blue: 0)),
            FrozenDisplay(info: DisplayInfo(id: 2, frame: CGRect(x: 100, y: 0, width: 100, height: 100), scale: 2),
                          image: TestImages.solid(width: 200, height: 200, red: 0, green: 0, blue: 1)),
        ]
    }

    @Test func singleDisplayIsPixelExact() throws {
        let quadrants = FrozenDisplay(info: DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 400, height: 300), scale: 1), image: TestImages.quadrants())
        let result = try #require(CaptureComposer.compose(CGRect(x: 190, y: 140, width: 20, height: 20), from: [quadrants]))
        #expect(result.scale == 1)
        let pixels = PixelBuffer(result.image)
        #expect(pixels.width == 20 && pixels.height == 20)
        #expect(pixels.pixel(x: 2, y: 2) == red)
        #expect(pixels.pixel(x: 17, y: 2) == RGBA8(r: 0, g: 255, b: 0))
        #expect(pixels.pixel(x: 2, y: 17) == blue)
    }

    @Test func composesAcrossDisplaysAtMaxScale() throws {
        let result = try #require(CaptureComposer.compose(CGRect(x: 50, y: 10, width: 100, height: 50), from: twoDisplays))
        #expect(result.scale == 2)
        let pixels = PixelBuffer(result.image)
        #expect(pixels.width == 200 && pixels.height == 100)
        #expect(pixels.pixel(x: 10, y: 50) == red)
        #expect(pixels.pixel(x: 190, y: 50) == blue)
    }

    @Test func negativeOriginDisplayComposes() throws {
        let above = FrozenDisplay(info: DisplayInfo(id: 3, frame: CGRect(x: -50, y: -100, width: 100, height: 100), scale: 1),
                                  image: TestImages.solid(width: 100, height: 100, red: 0, green: 0, blue: 1))
        let primary = twoDisplays[0]
        let result = try #require(CaptureComposer.compose(CGRect(x: 0, y: -20, width: 40, height: 40), from: [above, primary]))
        let pixels = PixelBuffer(result.image)
        #expect(pixels.pixel(x: 20, y: 5) == blue)
        #expect(pixels.pixel(x: 20, y: 35) == red)
    }

    @Test func gapsBetweenDisplaysAreTransparent() throws {
        let left = twoDisplays[0]
        let farRight = FrozenDisplay(info: DisplayInfo(id: 2, frame: CGRect(x: 200, y: 0, width: 100, height: 100), scale: 1),
                                     image: TestImages.solid(width: 100, height: 100, red: 0, green: 0, blue: 1))
        let result = try #require(CaptureComposer.compose(CGRect(x: 50, y: 0, width: 200, height: 50), from: [left, farRight]))
        #expect(PixelBuffer(result.image).pixel(x: 100, y: 10).a == 0)
    }

    @Test func outsideOrTinyReturnsNil() {
        #expect(CaptureComposer.compose(CGRect(x: 500, y: 500, width: 10, height: 10), from: twoDisplays) == nil)
        #expect(CaptureComposer.compose(CGRect(x: 10, y: 10, width: 0.4, height: 10), from: twoDisplays) == nil)
    }
}
