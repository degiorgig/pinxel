import AppKit
import XCTest

final class LibraryUITests: XCTestCase {
    private var folder: URL!

    override func setUp() {
        continueAfterFailure = false
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("pinxel-uitest-lib-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-PinxelUITestFakeCapture", "-PinxelLibraryFolder", folder.path] + extra
        app.launch()
        return app
    }

    func testCaptureLandsInTheGivenLibraryAndInTheStrip() {
        let app = launch(["-PinxelUITestCaptureOnLaunch"])
        XCTAssertTrue(app.images["pinxel.editor.canvas"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.otherElements["pinxel.library.strip"].waitForExistence(timeout: 5) || app.groups["pinxel.library.strip"].exists)
        let items = app.descendants(matching: .any).matching(identifier: "pinxel.library.item")
        XCTAssertEqual(items.count, 1)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        XCTAssertEqual(files.filter { $0.hasSuffix(".pinxel") }.count, 1)
        XCTAssertTrue(files.contains("library.json"))
        app.terminate()
    }

    func testClipboardOnlyCaptureStillEntersTheLibrary() {
        let app = launch(["-PinxelUITestCaptureOnLaunch", "-PinxelUITestPostCapture", "clipboardOnly"])
        let deadline = Date().addingTimeInterval(15)
        var files: [String] = []
        while Date() < deadline {
            files = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasSuffix(".pinxel") }
            if !files.isEmpty { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertEqual(files.count, 1)
        app.terminate()
    }

    func testClickingAThumbnailReplacesTheCaptureInTheWindow() {
        // Prima esecuzione: due catture nella stessa libreria.
        var app = launch(["-PinxelUITestCaptureOnLaunch"])
        XCTAssertTrue(app.images["pinxel.editor.canvas"].waitForExistence(timeout: 15))
        app.terminate()
        app = launch(["-PinxelUITestCaptureOnLaunch"])
        XCTAssertTrue(app.images["pinxel.editor.canvas"].waitForExistence(timeout: 15))
        app.activate()
        let items = app.descendants(matching: .any).matching(identifier: "pinxel.library.item")
        XCTAssertEqual(items.count, 2)
        let windowTitle = app.windows.firstMatch.title
        items.element(boundBy: 1).click()
        let changed = NSPredicate(format: "title != %@", windowTitle)
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: changed, object: app.windows.firstMatch)], timeout: 5), .completed)
        XCTAssertEqual(app.windows.count, 1)
        app.terminate()
    }
}
