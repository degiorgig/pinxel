import CoreGraphics
import Testing
@testable import CaptureKit

struct ScreenGeometryTests {
    let displays = [
        DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100), scale: 1),
        DisplayInfo(id: 2, frame: CGRect(x: 100, y: 0, width: 100, height: 100), scale: 2),
    ]

    @Test func appKitConversionOfPrimary() {
        let topLeft = ScreenGeometry.topLeft(fromAppKit: CGRect(x: 0, y: 900, width: 100, height: 100), primaryHeight: 1000)
        #expect(topLeft == CGRect(x: 0, y: 0, width: 100, height: 100))
    }

    @Test func appKitConversionHandlesDisplaysAbovePrimary() {
        // Screen above the main one: in AppKit y ≥ the main screen's height, in CG y is negative.
        let rect = CGRect(x: -200, y: 1000, width: 500, height: 300)
        let topLeft = ScreenGeometry.topLeft(fromAppKit: rect, primaryHeight: 1000)
        #expect(topLeft == CGRect(x: -200, y: -300, width: 500, height: 300))
        #expect(ScreenGeometry.appKit(fromTopLeft: topLeft, primaryHeight: 1000) == rect)
    }

    @Test func displayAtPoint() {
        #expect(ScreenGeometry.display(at: CGPoint(x: 150, y: 50), in: displays)?.id == 2)
        #expect(ScreenGeometry.display(at: CGPoint(x: 0, y: 0), in: displays)?.id == 1)
        // The right/bottom edge of the last screen still belongs to that screen.
        #expect(ScreenGeometry.display(at: CGPoint(x: 200, y: 100), in: displays)?.id == 2)
        #expect(ScreenGeometry.display(at: CGPoint(x: 500, y: 500), in: displays) == nil)
    }

    @Test func topmostWindowWins() {
        let windows = [
            WindowInfo(id: 10, frame: CGRect(x: 0, y: 0, width: 50, height: 50), title: "Davanti", appName: nil, bundleIdentifier: nil),
            WindowInfo(id: 11, frame: CGRect(x: 0, y: 0, width: 100, height: 100), title: "Dietro", appName: nil, bundleIdentifier: nil),
        ]
        #expect(ScreenGeometry.window(at: CGPoint(x: 10, y: 10), in: windows)?.id == 10)
        #expect(ScreenGeometry.window(at: CGPoint(x: 70, y: 70), in: windows)?.id == 11)
        #expect(ScreenGeometry.window(at: CGPoint(x: 150, y: 150), in: windows) == nil)
    }
}
