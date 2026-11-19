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

    /// The menu bar icon, if it can be clicked. With a full bar macOS hides it (it happens next to the notch
    /// of MacBooks): the click would not open the menu and the test would fail because of the screen layout, not because of Pinxel.
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

    @MainActor
    func testOpeningQuickPreviewAutoSavesOneCapture() throws {
        let app = XCUIApplication()
        let folder = launchQuickPreviewWithAutoSave(app)
        defer { app.terminate() }

        let preview = app.buttons["pinxel.quickPreview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 4))
        preview.click()
        XCTAssertTrue(app.images["pinxel.editor.canvas"].waitForExistence(timeout: 10))
        try assertOneSavedCapture(in: folder)
    }

    @MainActor
    func testExpiringQuickPreviewAutoSavesOneCaptureWithoutOpeningEditor() throws {
        let app = XCUIApplication()
        let folder = launchQuickPreviewWithAutoSave(app)
        defer { app.terminate() }

        let fileAppears = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (try? FileManager.default.contentsOfDirectory(atPath: folder.path).contains { $0.hasSuffix(".png") }) == true
        }, object: nil)
        wait(for: [fileAppears], timeout: 15)
        try assertOneSavedCapture(in: folder)
        XCTAssertFalse(app.images["pinxel.editor.canvas"].exists)
    }

    @MainActor
    private func launchQuickPreviewWithAutoSave(_ app: XCUIApplication) -> URL {
        // AutoSaver creates the folder. The sandboxed test runner can read it.
        let folder = URL(fileURLWithPath: "/private/tmp/pinxel-uitest-autosave-\(UUID().uuidString)", isDirectory: true)
        app.launchEnvironment["PINXEL_UITEST_AUTO_SAVE_FOLDER"] = folder.path
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-PinxelUITestPostCapture", "quickPreview",
                               "-PinxelUITestFakeCapture", "-PinxelUITestCaptureOnLaunch"]
        app.launch()
        return folder
    }

    private func assertOneSavedCapture(in folder: URL, file: StaticString = #filePath, line: UInt = #line) throws {
        let images = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "png" }
        XCTAssertEqual(images.count, 1, file: file, line: line)
        let url = try XCTUnwrap(images.first, file: file, line: line)
        let image = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: url)), file: file, line: line)
        XCTAssertEqual(image.pixelsWide, 400, file: file, line: line)
        XCTAssertEqual(image.pixelsHigh, 300, file: file, line: line)
    }

    func testMenuBarIconOpensLastCaptureInEditor() throws {
        NSPasteboard.general.clearContents()
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(it)", "-PinxelUITestFakeCapture", "-PinxelUITestCaptureOnLaunch", "-PinxelUITestPostCapture", "clipboardOnly"]
        app.launch()
        let statusItem = try clickableStatusItem(of: app)
        // The capture is done when it arrives on the clipboard.
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
