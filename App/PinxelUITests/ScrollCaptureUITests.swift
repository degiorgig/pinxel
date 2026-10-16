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

    /// La pagina finta è larga 400 px e lunga 1200: la cattura a scorrimento la deve ricostruire intera.
    func testScrollingCaptureOpensTheWholePageInTheEditor() {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-PinxelUITestFakeCapture", "-PinxelUITestFakeScrolling",
                               "-PinxelUITestPostCapture", "openEditor", "-PinxelUITestScrollOnLaunch"]
        app.launch()
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
}
