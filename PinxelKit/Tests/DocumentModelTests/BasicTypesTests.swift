import Foundation
import Testing
@testable import DocumentModel

struct BasicTypesTests {
    @Test func styleRoundTrips() throws {
        let style = Style(
            stroke: .accentRed, fill: .highlightYellow, lineWidth: 3, dash: .dotted, opacity: 0.5,
            shadow: Shadow(offset: CGSize(width: 2, height: 3), blur: 4, color: .black)
        )
        #expect(try roundTrip(style) == style)
    }

    @Test func styleWithoutColorsRoundTrips() throws {
        let style = Style(stroke: nil)
        #expect(try roundTrip(style) == style)
        #expect(style.fill == nil)
    }

    @Test func pixelRectClampsToImage() {
        let size = PixelSize(width: 100, height: 50)
        #expect(PixelRect(x: -10, y: 10, width: 50, height: 100).clamped(to: size)
            == PixelRect(x: 0, y: 10, width: 40, height: 40))
        #expect(PixelRect(x: 200, y: 0, width: 10, height: 10).clamped(to: size).width == 0)
    }

    @Test func boundingRectOfPoints() {
        let rect = CGRect.bounding([CGPoint(x: 5, y: 9), CGPoint(x: -1, y: 2), CGPoint(x: 3, y: 4)])
        #expect(rect == CGRect(x: -1, y: 2, width: 6, height: 7))
        #expect(CGRect.bounding([]).isNull)
    }

    @Test func lineAndPathRoundTrip() throws {
        let line = LineGeometry(start: CGPoint(x: 1, y: 2), end: CGPoint(x: 3.5, y: 4))
        let path = PathGeometry(points: [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)])
        #expect(try roundTrip(line) == line)
        #expect(try roundTrip(path) == path)
    }
}
