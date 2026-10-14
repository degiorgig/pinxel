import CoreGraphics
import Testing
@testable import CaptureKit

struct SelectionPixelStepTests {
    @Test func arrowsMoveOnePixelOnRetinaDisplays() {
        var model = SelectionModel(mode: .area, windows: [], displays: [])
        model.mouseDown(at: CGPoint(x: 10, y: 10))
        model.mouseDragged(to: CGPoint(x: 110, y: 60), square: false)
        _ = model.key(.right, shift: false, pixelSize: 0.5)
        #expect(model.selectionRect == CGRect(x: 10, y: 10, width: 100.5, height: 50))
        _ = model.key(.down, shift: true, pixelSize: 0.5)
        #expect(model.selectionRect?.height == 55)
    }
}
