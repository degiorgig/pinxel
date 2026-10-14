import AppKit
import XCTest

final class CaptureFlowUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testAreaCaptureOpensDocumentWindow() {
        let app = XCUIApplication()
        app.launchArguments = ["-PinxelUITestFakeCapture", "-PinxelUITestCaptureOnLaunch"]
        app.launch()
        XCTAssertTrue(app.images["pinxel.viewer.image"].waitForExistence(timeout: 15))
        app.terminate()
    }

    func testClipboardOnlyPutsCaptureOnPasteboard() {
        NSPasteboard.general.clearContents()
        let app = XCUIApplication()
        app.launchArguments = ["-PinxelUITestFakeCapture", "-PinxelUITestCaptureOnLaunch", "-PinxelUITestPostCapture", "clipboardOnly"]
        app.launch()
        let deadline = Date().addingTimeInterval(15)
        var png = NSPasteboard.general.data(forType: .png)
        while png == nil, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            png = NSPasteboard.general.data(forType: .png)
        }
        let data = try! XCTUnwrap(png)
        let image = try! XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(image.pixelsWide, 400)
        XCTAssertEqual(image.pixelsHigh, 300)
        XCTAssertEqual(app.windows.count, 0)
        app.terminate()
    }
}
