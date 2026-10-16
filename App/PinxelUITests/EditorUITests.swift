import AppKit
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

    func testTextToolTypesAndCommitsWithEscape() {
        let app = launchWithSample()
        let canvas = app.images["pinxel.editor.canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        canvas.click()
        canvas.typeKey("t", modifierFlags: [])
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.42, dy: 0.45)).click()
        app.typeText("Ciao")
        app.typeKey(.escape, modifierFlags: [])
        waitForValue(canvas, prefix: "Annotazioni: 1")
        app.typeKey("z", modifierFlags: .command)
        waitForValue(canvas, prefix: "Annotazioni: 0")
        app.terminate()
    }

    func testCropWithReturnChangesTheImageSize() {
        let app = launchWithSample()
        let canvas = app.images["pinxel.editor.canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        canvas.click()
        canvas.typeKey("k", modifierFlags: [])
        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.42, dy: 0.42))
        let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.55))
        start.click(forDuration: 0.1, thenDragTo: end)
        app.typeKey(.return, modifierFlags: [])
        let cropped = NSPredicate(format: "NOT (value CONTAINS %@)", "200×200")
        wait(for: [expectation(for: cropped, evaluatedWith: canvas)], timeout: 5)
        app.terminate()
    }

    func testArrangeMenuFollowsTheSelection() {
        let app = launchWithSample()
        let canvas = app.images["pinxel.editor.canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        canvas.click()
        let arrange = app.menuBars.menuBarItems["Disponi"]
        arrange.click()
        XCTAssertFalse(arrange.menuItems["Duplica"].isEnabled)
        app.typeKey(.escape, modifierFlags: [])
        canvas.typeKey("r", modifierFlags: [])
        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.4))
        let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.55))
        start.click(forDuration: 0.1, thenDragTo: end)
        waitForValue(canvas, prefix: "Annotazioni: 1")
        arrange.click()
        XCTAssertTrue(arrange.menuItems["Duplica"].isEnabled)
        app.typeKey(.escape, modifierFlags: [])
        app.terminate()
    }

    func testToolsAreVisibleAtTheInitialWindowSize() {
        let app = launchWithSample()
        XCTAssertTrue(app.images["pinxel.editor.canvas"].waitForExistence(timeout: 10))
        // Sotto una certa larghezza la toolbar va tutta nel menu di overflow.
        XCTAssertTrue(app.radioButtons["Selezione"].isHittable)
        XCTAssertTrue(app.radioButtons["Taglia e ricuci"].isHittable)
        XCTAssertTrue(app.images["Trascina l'immagine"].isHittable)
        app.terminate()
    }

    func testOpeningAPNGOpensItInANewDocument() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("pinxel-open-test.png")
        let image = NSImage(size: NSSize(width: 120, height: 80), flipped: false) { rect in
            NSColor.systemOrange.setFill()
            rect.fill()
            return true
        }
        let rep = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        let pixels = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try pixels.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-PinxelUITestFakeCapture"]
        app.launch()
        app.open(url)
        let canvas = app.images["pinxel.editor.canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        XCTAssertTrue(app.windows["pinxel-open-test"].exists)
        app.terminate()
    }
}
