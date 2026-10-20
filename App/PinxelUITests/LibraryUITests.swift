import AppKit
import XCTest

/// The tests' library lives in Pinxel's temporary folder with a name chosen here: several launches find the same captures,
/// and the real library is never touched.
final class LibraryUITests: XCTestCase {
    private var libraryName = ""
    private var pasteboardGuard: PasteboardGuard?

    override func setUp() {
        continueAfterFailure = false
        libraryName = UUID().uuidString
        pasteboardGuard = PasteboardGuard()
    }

    override func tearDown() {
        pasteboardGuard?.restore()
    }

    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        // Key-value pairs before valueless flags: AppKit reads arguments in pairs, and a leftover
        // unpaired value would be opened as a file (modal alert that blocks the app).
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(it)", "-PinxelUITestLibraryName", libraryName] + extra + ["-PinxelUITestFakeCapture"]
        app.launch()
        return app
    }

    private func items(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "pinxel.library.item")
    }

    private func waitForItems(_ app: XCUIApplication, count: Int) -> Bool {
        let predicate = NSPredicate(format: "count == %d", count)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: items(app))], timeout: 10) == .completed
    }

    func testCaptureAppearsInTheStrip() {
        let app = launch(["-PinxelUITestCaptureOnLaunch"])
        XCTAssertTrue(app.images["pinxel.editor.canvas"].waitForExistence(timeout: 15))
        XCTAssertTrue(waitForItems(app, count: 1))
        app.terminate()
    }

    func testClipboardOnlyCaptureStillEntersTheLibrary() {
        NSPasteboard.general.clearContents()
        var app = launch(["-PinxelUITestPostCapture", "clipboardOnly", "-PinxelUITestCaptureOnLaunch"])
        // No window: wait for the capture to arrive on the pasteboard, then reopen with an empty editor.
        let deadline = Date().addingTimeInterval(15)
        while NSPasteboard.general.data(forType: .png) == nil, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        app.terminate()
        app = launch(["-PinxelUITestOpenBlank"])
        XCTAssertTrue(app.images["pinxel.editor.canvas"].waitForExistence(timeout: 15))
        XCTAssertTrue(waitForItems(app, count: 1))
        app.terminate()
    }

    func testClickingAThumbnailReplacesTheCaptureInTheWindow() {
        var app = launch(["-PinxelUITestCaptureOnLaunch"])
        XCTAssertTrue(app.images["pinxel.editor.canvas"].waitForExistence(timeout: 15))
        app.terminate()
        app = launch(["-PinxelUITestCaptureOnLaunch"])
        XCTAssertTrue(app.images["pinxel.editor.canvas"].waitForExistence(timeout: 15))
        app.activate()
        XCTAssertTrue(waitForItems(app, count: 2))
        let window = app.windows.firstMatch
        let title = window.title
        items(app).element(boundBy: 1).click()
        let changed = NSPredicate(format: "title != %@", title)
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: changed, object: window)], timeout: 5), .completed)
        XCTAssertEqual(app.windows.count, 1)
        app.terminate()
    }

    /// A window with an untitled document (like "New from Pasteboard"): the click stays there and the document enters
    /// the library instead of being lost.
    func testClickingAThumbnailInAnUntitledWindowKeepsTheWindowAndTheDocument() {
        var app = launch(["-PinxelUITestCaptureOnLaunch"])
        XCTAssertTrue(app.images["pinxel.editor.canvas"].waitForExistence(timeout: 15))
        app.terminate()
        app = launch(["-PinxelUITestOpenSample"])
        XCTAssertTrue(app.images["pinxel.editor.canvas"].waitForExistence(timeout: 15))
        app.activate()
        XCTAssertTrue(waitForItems(app, count: 1))
        items(app).element(boundBy: 0).click()
        XCTAssertTrue(waitForItems(app, count: 2))
        XCTAssertEqual(app.windows.count, 1)
        app.terminate()
    }
}
