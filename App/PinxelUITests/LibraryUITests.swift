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

    @MainActor
    func testDeleteButtonIsReachableFromTheEmptyEdgeOfATallThumbnail() {
        let app = launch(["-PinxelUITestFakeScrolling", "-PinxelUITestScrollOnLaunch"])
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["1200 px"].waitForExistence(timeout: 15))
        app.buttons["Fine"].click()

        let canvas = app.images["pinxel.editor.canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 15))
        XCTAssertTrue(waitForItems(app, count: 1))
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).hover()

        let thumbnail = items(app).firstMatch
        let delete = app.buttons["pinxel.library.item.delete"]
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: delete)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 4), .completed)
        // A tall capture leaves empty space on both sides of its image: hover there, below the button.
        thumbnail.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.75)).hover()
        XCTAssertTrue(delete.waitForExistence(timeout: 4))
        delete.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).hover()
        XCTAssertTrue(delete.isHittable)
        delete.click()
        XCTAssertTrue(waitForItems(app, count: 0))
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
