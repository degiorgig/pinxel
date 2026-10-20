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

    /// L'icona nella barra dei menu, se si può cliccare. Con la barra piena macOS la nasconde (succede accanto alla tacca
    /// dei MacBook): il clic non aprirebbe il menu e il test fallirebbe per la disposizione dello schermo, non per Pinxel.
    private func clickableStatusItem(of app: XCUIApplication) throws -> XCUIElement {
        let statusItem = app.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 10))
        let visible = NSPredicate(format: "hittable == true")
        let found = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: visible, object: statusItem)], timeout: 5) == .completed
        try XCTSkipUnless(found, "L'icona di Pinxel non è visibile nella barra dei menu (barra piena o tacca): libera spazio per questo test")
        return statusItem
    }

    func testAreaCaptureOpensDocumentWindow() {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(it)", "-PinxelUITestFakeCapture", "-PinxelUITestCaptureOnLaunch"]
        app.launch()
        XCTAssertTrue(app.images["pinxel.editor.canvas"].waitForExistence(timeout: 15))
        app.terminate()
    }

    func testClipboardOnlyPutsCaptureOnPasteboard() {
        NSPasteboard.general.clearContents()
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(it)", "-PinxelUITestFakeCapture", "-PinxelUITestCaptureOnLaunch", "-PinxelUITestPostCapture", "clipboardOnly"]
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

    func testMenuBarIconOpensLastCaptureInEditor() throws {
        NSPasteboard.general.clearContents()
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(it)", "-PinxelUITestFakeCapture", "-PinxelUITestCaptureOnLaunch", "-PinxelUITestPostCapture", "clipboardOnly"]
        app.launch()
        let statusItem = try clickableStatusItem(of: app)
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

    func testMenuBarIconOpensClipboardImageInEditor() throws {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 120, pixelsHigh: 80, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(rep.representation(using: .png, properties: [:]), forType: .png)
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(it)", "-PinxelUITestFakeCapture"]
        app.launch()
        let statusItem = try clickableStatusItem(of: app)
        statusItem.click()
        statusItem.menuItems["Nuova dagli appunti"].click()
        XCTAssertTrue(app.images["pinxel.editor.canvas"].waitForExistence(timeout: 10))
        app.terminate()
    }

    func testMenuBarNewOpensAnEmptyEditor() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(it)", "-PinxelUITestFakeCapture"]
        app.launch()
        let statusItem = try clickableStatusItem(of: app)
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
