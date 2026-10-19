import AppKit
import XCTest

/// La libreria dei test sta nella cartella temporanea di Pinxel con un nome scelto qui: più avvii ritrovano le stesse catture,
/// e la libreria vera non si tocca mai.
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
        // Le coppie chiave-valore prima dei flag senza valore: AppKit legge gli argomenti a coppie, e un valore rimasto
        // spaiato verrebbe aperto come file (avviso modale che blocca l'app).
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-PinxelUITestLibraryName", libraryName] + extra + ["-PinxelUITestFakeCapture"]
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
        // Nessuna finestra: si aspetta che la cattura arrivi negli appunti, poi si riapre con un editor vuoto.
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

    /// Una finestra con un documento senza titolo (come "Nuova dagli appunti"): il clic resta lì e il documento entra
    /// nella libreria invece di andare perso.
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
