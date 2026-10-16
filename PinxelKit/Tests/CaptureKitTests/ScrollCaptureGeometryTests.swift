import CoreGraphics
import Testing
@testable import CaptureKit

struct ScrollCaptureGeometryTests {
    let display = DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 2)

    @Test func areaIsClippedToItsScreenAndMustBeTallEnough() {
        #expect(ScrollCaptureGeometry.prepare(CGRect(x: 100, y: 100, width: 300, height: 99), on: display, maxHeight: 32768) == nil)
        // Dentro lo schermo restano 140×100 punti: esattamente il minimo, quindi accettata.
        let boundary = ScrollCaptureGeometry.prepare(CGRect(x: 1300, y: 800, width: 300, height: 300), on: display, maxHeight: 32768)
        #expect(boundary?.rect == CGRect(x: 1300, y: 800, width: 140, height: 100))
        let ok = ScrollCaptureGeometry.prepare(CGRect(x: 1300, y: 700, width: 300, height: 300), on: display, maxHeight: 32768)
        #expect(ok?.rect == CGRect(x: 1300, y: 700, width: 140, height: 200))
        #expect(ok?.narrowed == false)
    }

    @Test func widthIsLimitedByTheMemoryBudget() {
        let wide = DisplayInfo(id: 2, frame: CGRect(x: 0, y: 0, width: 6000, height: 2000), scale: 2)
        let prepared = ScrollCaptureGeometry.prepare(CGRect(x: 0, y: 0, width: 6000, height: 500), on: wide, maxHeight: 32768)
        // 1 GB / (32768 × 4) = 8192 px = 4096 pt a 2x.
        #expect(prepared?.rect.width == 4096)
        #expect(prepared?.narrowed == true)
    }

    @Test func panelGoesBelowThenAboveThenBeside() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let size = CGSize(width: 340, height: 64)
        let below = ScrollCaptureGeometry.panelFrame(size: size, around: CGRect(x: 500, y: 100, width: 400, height: 400), in: screen)
        #expect(below == CGRect(x: 530, y: 512, width: 340, height: 64))
        let above = ScrollCaptureGeometry.panelFrame(size: size, around: CGRect(x: 500, y: 300, width: 400, height: 580), in: screen)
        #expect(above == CGRect(x: 530, y: 224, width: 340, height: 64))
        let beside = ScrollCaptureGeometry.panelFrame(size: size, around: CGRect(x: 100, y: 20, width: 400, height: 860), in: screen)
        #expect(beside == CGRect(x: 512, y: 20, width: 340, height: 64))
        let inside = ScrollCaptureGeometry.panelFrame(size: size, around: screen, in: screen)
        #expect(screen.contains(inside))
    }
}
