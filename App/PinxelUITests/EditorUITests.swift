import XCTest

final class EditorUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launchWithSample() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-PinxelUITestFakeCapture", "-PinxelUITestOpenSample"]
        app.launch()
        return app
    }

    private func waitForValue(_ element: XCUIElement, prefix: String) {
        let predicate = NSPredicate(format: "value BEGINSWITH %@", prefix)
        wait(for: [expectation(for: predicate, evaluatedWith: element)], timeout: 5)
    }

    func testDrawShapeThenUndoAndRedo() {
        let app = launchWithSample()
        let canvas = app.images["pinxel.editor.canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        waitForValue(canvas, prefix: "Annotazioni: 0")

        canvas.click()
        canvas.typeKey("r", modifierFlags: [])
        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.35))
        let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.6))
        start.click(forDuration: 0.1, thenDragTo: end)
        waitForValue(canvas, prefix: "Annotazioni: 1")

        app.typeKey("z", modifierFlags: .command)
        waitForValue(canvas, prefix: "Annotazioni: 0")
        app.typeKey("z", modifierFlags: [.command, .shift])
        waitForValue(canvas, prefix: "Annotazioni: 1")
        app.terminate()
    }

    func testExportOpensASaveSheet() {
        let app = launchWithSample()
        let canvas = app.images["pinxel.editor.canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        canvas.click()
        app.typeKey("e", modifierFlags: .command)
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
        app.terminate()
    }
}
