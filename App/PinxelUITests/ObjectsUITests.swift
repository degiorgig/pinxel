import XCTest

/// La cattura è un oggetto come gli altri: si seleziona con un clic, si sposta, e la tela la segue.
final class ObjectsUITests: XCTestCase {
    private var app: XCUIApplication!
    private var pasteboardGuard: PasteboardGuard?

    override func setUp() {
        continueAfterFailure = false
        pasteboardGuard = PasteboardGuard()
        app = XCUIApplication()
        // Le coppie chiave-valore prima dei flag senza valore (vedi LibraryUITests); la libreria dei test non è quella vera.
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-PinxelUITestLibraryName", UUID().uuidString, "-PinxelUITestOpenSample"]
        app.launch()
        app.activate()
    }

    override func tearDown() {
        app.terminate()
        pasteboardGuard?.restore()
    }

    /// Un rettangolo sulla cattura, poi clic sulla cattura e trascinata a destra: il rettangolo resta fermo e la tela
    /// si allarga per contenerli entrambi (il valore di accessibilità riporta le dimensioni). Con un solo oggetto la tela
    /// lo seguirebbe senza cambiare dimensioni.
    func testMovingTheCaptureGrowsTheCanvas() throws {
        let canvas = app.images["pinxel.editor.canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        let before = try XCTUnwrap((canvas.value as? String)?.components(separatedBy: "immagine: ").last)
        let center = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        // Il campione è piccolo e centrato: questi punti cadono sulla cattura.
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
        // Un solo ⌘Z riporta cattura e tela com'erano.
        app.typeKey("z", modifierFlags: .command)
        wait(for: [expectation(for: NSPredicate(format: "value ENDSWITH %@", "immagine: \(before)"), evaluatedWith: canvas)], timeout: 5)
    }

    /// I pulsanti In primo piano / In fondo nella barra: spenti senza selezione, accesi con un oggetto selezionato.
    func testArrangeButtonsFollowTheSelection() throws {
        let canvas = app.images["pinxel.editor.canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        let back = app.toolbars.buttons["In fondo"]
        let front = app.toolbars.buttons["In primo piano"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertFalse(back.isEnabled)
        XCTAssertFalse(front.isEnabled)
        // Un rettangolo appena disegnato è selezionato.
        let center = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        canvas.typeKey("r", modifierFlags: [])
        center.withOffset(CGVector(dx: -30, dy: -30)).click(forDuration: 0.1, thenDragTo: center.withOffset(CGVector(dx: 10, dy: 10)))
        wait(for: [expectation(for: NSPredicate(format: "value CONTAINS %@", "selezionate: 1"), evaluatedWith: canvas)], timeout: 5)
        wait(for: [expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: back)], timeout: 5)
        XCTAssertTrue(front.isEnabled)
        back.click()
        // Il pulsante ha registrato un comando: il primo ⌘Z annulla lo spostamento (il rettangolo resta),
        // solo il secondo toglie il rettangolo.
        app.typeKey("z", modifierFlags: .command)
        let removed = expectation(for: NSPredicate(format: "value BEGINSWITH %@", "Annotazioni: 1"), evaluatedWith: canvas)
        removed.isInverted = true
        wait(for: [removed], timeout: 2)
        app.typeKey("z", modifierFlags: .command)
        wait(for: [expectation(for: NSPredicate(format: "value BEGINSWITH %@", "Annotazioni: 1"), evaluatedWith: canvas)], timeout: 5)
    }
}
