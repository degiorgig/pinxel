import AppKit
import XCTest

final class CaptureFlowUITests: XCTestCase {
    private var pasteboardGuard: PasteboardGuard?

    override func setUp() {
        continueAfterFailure = false
        pasteboardGuard = PasteboardGuard()
    }

    override func tearDown() {
        pasteboardGuard?.restore()
    }

    func testAreaCaptureOpensDocumentWindow() {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-PinxelUITestFakeCapture", "-PinxelUITestCaptureOnLaunch"]
        app.launch()
        XCTAssertTrue(app.images["pinxel.editor.canvas"].waitForExistence(timeout: 15))
        app.terminate()
    }

    func testClipboardOnlyPutsCaptureOnPasteboard() {
        NSPasteboard.general.clearContents()
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-PinxelUITestFakeCapture", "-PinxelUITestCaptureOnLaunch", "-PinxelUITestPostCapture", "clipboardOnly"]
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

    func testMenuBarIconOpensLastCaptureInEditor() {
        NSPasteboard.general.clearContents()
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-PinxelUITestFakeCapture", "-PinxelUITestCaptureOnLaunch", "-PinxelUITestPostCapture", "clipboardOnly"]
        app.launch()
        let statusItem = app.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 10))
        // La cattura è finita quando arriva negli appunti.
        let deadline = Date().addingTimeInterval(15)
        while NSPasteboard.general.data(forType: .png) == nil, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        statusItem.click()
        let item = statusItem.menuItems["Modifica ultima cattura"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        XCTAssertTrue(item.isEnabled)
        item.click()
        XCTAssertTrue(app.images["pinxel.editor.canvas"].waitForExistence(timeout: 10))
        app.terminate()
    }

    func testMenuBarIconOpensClipboardImageInEditor() {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 120, pixelsHigh: 80, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(rep.representation(using: .png, properties: [:]), forType: .png)
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-PinxelUITestFakeCapture"]
        app.launch()
        let statusItem = app.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 10))
        statusItem.click()
        statusItem.menuItems["Nuova dagli appunti"].click()
        XCTAssertTrue(app.images["pinxel.editor.canvas"].waitForExistence(timeout: 10))
        app.terminate()
    }

    func testMenuBarNewOpensAnEmptyEditor() {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-PinxelUITestFakeCapture"]
        app.launch()
        let statusItem = app.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 10))
        statusItem.click()
        statusItem.menuItems["Nuovo"].click()
        let canvas = app.images["pinxel.editor.canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        XCTAssertTrue((canvas.value as? String)?.hasPrefix("Annotazioni: 0") == true)
        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.lifetime = .keepAlways
        add(shot)
        app.terminate()
    }
}
