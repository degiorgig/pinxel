import XCTest

/// The capture is an object like the others: it is selected with a click, moved, and the canvas follows it.
final class ObjectsUITests: XCTestCase {
    private var app: XCUIApplication!
    private var pasteboardGuard: PasteboardGuard?

    override func setUp() {
        continueAfterFailure = false
        pasteboardGuard = PasteboardGuard()
        app = XCUIApplication()
        // Key-value pairs before the valueless flags (see LibraryUITests); the tests' library is not the real one.
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(it)", "-PinxelUITestLibraryName", UUID().uuidString, "-PinxelUITestFakeCapture", "-PinxelUITestOpenSample"]
        app.launch()
        app.activate()
    }

    override func tearDown() {
        app.terminate()
        pasteboardGuard?.restore()
    }

    /// A rectangle on the capture, then click on the capture and drag right: the rectangle stays put and the canvas
    /// widens to contain both (the accessibility value reports the size). With a single object the canvas
    /// would follow it without changing size.
    func testMovingTheCaptureGrowsTheCanvas() throws {
        let canvas = app.images["pinxel.editor.canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        let before = try XCTUnwrap((canvas.value as? String)?.components(separatedBy: "immagine: ").last)
        let center = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        // The sample is small and centered: these points fall on the capture.
        canvas.typeKey("r", modifierFlags: [])
        center.withOffset(CGVector(dx: -45, dy: -45)).click(forDuration: 0.1, thenDragTo: center.withOffset(CGVector(dx: -25, dy: -25)))
        wait(for: [expectation(for: NSPredicate(format: "value BEGINSWITH %@", "Annotazioni: 2"), evaluatedWith: canvas)], timeout: 5)
        canvas.typeKey("v", modifierFlags: [])
        let onCapture = center.withOffset(CGVector(dx: 30, dy: 30))
        onCapture.click()
        wait(for: [expectation(for: NSPredicate(format: "value CONTAINS %@", "selezionate: 1"), evaluatedWith: canvas)], timeout: 5)
        onCapture.click(forDuration: 0.2, thenDragTo: onCapture.withOffset(CGVector(dx: 150, dy: 0)))
        let grown = NSPredicate(format: "NOT (value ENDSWITH %@)", "immagine: \(before)")
        wait(for: [expectation(for: grown, evaluatedWith: canvas)], timeout: 5)
        // A single ⌘Z restores capture and canvas as they were.
        app.typeKey("z", modifierFlags: .command)
        wait(for: [expectation(for: NSPredicate(format: "value ENDSWITH %@", "immagine: \(before)"), evaluatedWith: canvas)], timeout: 5)
    }

    /// The Bring to Front / Send to Back buttons in the bar: off with no selection, on with an object selected.
    func testArrangeButtonsFollowTheSelection() throws {
        let canvas = app.images["pinxel.editor.canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        let back = app.toolbars.buttons["In fondo"]
        let front = app.toolbars.buttons["In primo piano"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertFalse(back.isEnabled)
        XCTAssertFalse(front.isEnabled)
        // A freshly drawn rectangle is selected.
        let center = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        canvas.typeKey("r", modifierFlags: [])
        center.withOffset(CGVector(dx: -30, dy: -30)).click(forDuration: 0.1, thenDragTo: center.withOffset(CGVector(dx: 10, dy: 10)))
        wait(for: [expectation(for: NSPredicate(format: "value CONTAINS %@", "selezionate: 1"), evaluatedWith: canvas)], timeout: 5)
        wait(for: [expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: back)], timeout: 5)
        XCTAssertTrue(front.isEnabled)
        back.click()
        // The button registered a command: the first ⌘Z undoes the move (the rectangle stays),
        // only the second removes the rectangle.
        app.typeKey("z", modifierFlags: .command)
        let removed = expectation(for: NSPredicate(format: "value BEGINSWITH %@", "Annotazioni: 1"), evaluatedWith: canvas)
        removed.isInverted = true
        wait(for: [removed], timeout: 2)
        app.typeKey("z", modifierFlags: .command)
        wait(for: [expectation(for: NSPredicate(format: "value BEGINSWITH %@", "Annotazioni: 1"), evaluatedWith: canvas)], timeout: 5)
    }
}
