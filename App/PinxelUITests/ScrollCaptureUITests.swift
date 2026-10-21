import XCTest

final class ScrollCaptureUITests: XCTestCase {
    private var pasteboardGuard: PasteboardGuard?

    override func setUp() {
        continueAfterFailure = false
        pasteboardGuard = PasteboardGuard()
    }

    override func tearDown() {
        pasteboardGuard?.restore()
    }

    /// The fake page is 400 px wide and 1200 long: scrolled all the way down, the capture must rebuild it whole.
    func testScrollingCaptureOpensTheWholePageInTheEditor() {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(it)", "-PinxelUITestFakeCapture", "-PinxelUITestFakeScrolling",
                               "-PinxelUITestPostCapture", "openEditor", "-PinxelUITestScrollOnLaunch"]
        app.launch()
        // The fake page scrolls by itself as the user would; the capture ends with Done.
        let finish = app.buttons["Fine"]
        XCTAssertTrue(finish.waitForExistence(timeout: 10))
        sleep(4)
        finish.click()
        let canvas = app.images["pinxel.editor.canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 20))
        let whole = NSPredicate(format: "value ENDSWITH %@", "immagine: 400\u{00D7}1200")
        wait(for: [expectation(for: whole, evaluatedWith: canvas)], timeout: 5)
        app.activate()
        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.lifetime = .keepAlways
        add(shot)
        app.terminate()
    }

    /// Return is a global shortcut while the capture runs: it finishes it before any app sees the key.
    func testReturnFinishesTheScrollingCapture() {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(it)", "-PinxelUITestFakeCapture", "-PinxelUITestFakeScrolling",
                               "-PinxelUITestPostCapture", "openEditor", "-PinxelUITestScrollOnLaunch"]
        app.launch()
        XCTAssertTrue(app.buttons["Fine"].waitForExistence(timeout: 10))
        sleep(2)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.images["pinxel.editor.canvas"].waitForExistence(timeout: 20))
        app.terminate()
    }
}
