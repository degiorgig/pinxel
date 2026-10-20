import AppKit
import XCTest

final class EditorUITests: XCTestCase {
    private var pasteboardGuard: PasteboardGuard?

    override func setUp() {
        continueAfterFailure = false
        pasteboardGuard = PasteboardGuard()
    }

    override func tearDown() {
        pasteboardGuard?.restore()
    }

    private func launchWithSample() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(it)", "-PinxelUITestFakeCapture", "-PinxelUITestOpenSample"]
        app.launch()
        return app
    }

    private func waitForValue(_ element: XCUIElement, prefix: String) {
        let predicate = NSPredicate(format: "value BEGINSWITH %@", prefix)
        wait(for: [expectation(for: predicate, evaluatedWith: element)], timeout: 5)
    }

    // La cattura è un oggetto: nel conteggio c'è sempre anche lei.
    func testDrawShapeThenUndoAndRedo() {
        let app = launchWithSample()
        let canvas = app.images["pinxel.editor.canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        waitForValue(canvas, prefix: "Annotazioni: 1")

        canvas.click()
        canvas.typeKey("r", modifierFlags: [])
        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.35))
        let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.6))
        start.click(forDuration: 0.1, thenDragTo: end)
        waitForValue(canvas, prefix: "Annotazioni: 2")

        app.typeKey("z", modifierFlags: .command)
        waitForValue(canvas, prefix: "Annotazioni: 1")
        app.typeKey("z", modifierFlags: [.command, .shift])
        waitForValue(canvas, prefix: "Annotazioni: 2")
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
        waitForValue(canvas, prefix: "Annotazioni: 2")
        app.typeKey("z", modifierFlags: .command)
        waitForValue(canvas, prefix: "Annotazioni: 1")
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
        // Il clic ha selezionato la cattura: Esc toglie la selezione.
        canvas.typeKey(.escape, modifierFlags: [])
        let arrange = app.menuBars.menuBarItems["Disponi"]
        arrange.click()
        XCTAssertFalse(arrange.menuItems["Duplica"].isEnabled)
        app.typeKey(.escape, modifierFlags: [])
        canvas.typeKey("r", modifierFlags: [])
        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.4))
        let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.55))
        start.click(forDuration: 0.1, thenDragTo: end)
        waitForValue(canvas, prefix: "Annotazioni: 2")
        arrange.click()
        XCTAssertTrue(arrange.menuItems["Duplica"].isEnabled)
        app.typeKey(.escape, modifierFlags: [])
        app.terminate()
    }

    func testToolsAreVisibleAtTheInitialWindowSize() {
        let app = launchWithSample()
        XCTAssertTrue(app.images["pinxel.editor.canvas"].waitForExistence(timeout: 10))
        // Un'app agente non passa davanti da sola: senza, un'altra finestra può coprire la toolbar.
        app.activate()
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
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(it)", "-PinxelUITestFakeCapture"]
        app.launch()
        app.open(url)
        let canvas = app.images["pinxel.editor.canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        XCTAssertTrue(app.windows["pinxel-open-test"].exists)
        app.terminate()
    }

    func testNewEditorIsEmptyUntilAScreenshotIsPasted() throws {
        let image = NSImage(size: NSSize(width: 640, height: 400), flipped: false) { rect in
            NSColor.systemGreen.setFill()
            rect.fill()
            return true
        }
        let rep = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(it)", "-PinxelUITestFakeCapture", "-PinxelUITestOpenBlank"]
        app.launch()
        let canvas = app.images["pinxel.editor.canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        waitForValue(canvas, prefix: "Annotazioni: 0")
        app.activate()
        let blankValue = try XCTUnwrap(canvas.value as? String)
        let empty = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        empty.name = "vuoto"
        empty.lifetime = .keepAlways
        add(empty)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(png, forType: .png)
        canvas.click()
        app.typeKey("v", modifierFlags: .command)
        // La tela prende le dimensioni dello screenshot (in pixel del documento, che dipendono dalla scala dello schermo).
        let pasted = NSPredicate(format: "value BEGINSWITH %@ AND value != %@", "Annotazioni: 1", blankValue)
        wait(for: [expectation(for: pasted, evaluatedWith: canvas)], timeout: 5)
        let size = try XCTUnwrap((canvas.value as? String)?.components(separatedBy: "immagine: ").last)
        XCTAssertNotEqual(size, blankValue.components(separatedBy: "immagine: ").last)
        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.name = "incollato"
        shot.lifetime = .keepAlways
        add(shot)
        app.terminate()
    }

    func testScissorsRemoveABandAndCloseTheGap() throws {
        // Righe colorate numerate: dopo il taglio si vede quali sono sparite e come si ricuciono.
        let image = NSImage(size: NSSize(width: 600, height: 400), flipped: true) { rect in
            let colors: [NSColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue, .systemPurple, .systemPink, .systemTeal]
            for row in 0..<8 {
                colors[row].setFill()
                NSRect(x: 0, y: CGFloat(row) * 50, width: rect.width, height: 50).fill()
                ("Riga \(row + 1)" as NSString).draw(at: NSPoint(x: 20, y: CGFloat(row) * 50 + 12),
                                                     withAttributes: [.font: NSFont.boldSystemFont(ofSize: 22)])
            }
            return true
        }
        let rep = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(it)", "-PinxelUITestFakeCapture", "-PinxelUITestOpenBlank"]
        app.launch()
        let canvas = app.images["pinxel.editor.canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        app.activate()
        let blankValue = try XCTUnwrap(canvas.value as? String)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(png, forType: .png)
        canvas.click()
        app.typeKey("v", modifierFlags: .command)
        wait(for: [expectation(for: NSPredicate(format: "value != %@", blankValue), evaluatedWith: canvas)], timeout: 5)
        let pastedValue = try XCTUnwrap(canvas.value as? String)
        snapshot(app, "1-incollato")
        app.radioButtons["Taglia e ricuci"].click()
        snapshot(app, "2-forbici")
        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.40))
        let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
        start.click(forDuration: 0.2, thenDragTo: end)
        // Lo screenshot è l'immagine in fondo: la fascia sparisce e l'altezza cala, senza oggetti schiacciati.
        wait(for: [expectation(for: NSPredicate(format: "value != %@", pastedValue), evaluatedWith: canvas)], timeout: 5)
        func height(_ value: String) -> Int? { value.components(separatedBy: "\u{00D7}").last.flatMap { Int($0) } }
        let cutValue = try XCTUnwrap(canvas.value as? String)
        XCTAssertTrue(cutValue.hasPrefix("Annotazioni: 1"))
        XCTAssertLessThan(try XCTUnwrap(height(cutValue)), try XCTUnwrap(height(pastedValue)))
        snapshot(app, "3-tagliato")
        app.terminate()
    }

    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testPastingALargerScreenshotGrowsTheCanvas() throws {
        let image = NSImage(size: NSSize(width: 900, height: 700), flipped: false) { rect in
            NSColor.systemGreen.setFill()
            rect.fill()
            return true
        }
        let rep = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let app = launchWithSample()
        let canvas = app.images["pinxel.editor.canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        waitForValue(canvas, prefix: "Annotazioni: 1")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(png, forType: .png)
        canvas.click()
        app.typeKey("v", modifierFlags: .command)
        // Il campione è 200x200: lo screenshot incollato la porta alle sue dimensioni, a grandezza piena.
        let grown = NSPredicate(format: "value ENDSWITH %@", "immagine: \(rep.pixelsWide)\u{00D7}\(rep.pixelsHigh)")
        wait(for: [expectation(for: grown, evaluatedWith: canvas)], timeout: 5)
        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.lifetime = .keepAlways
        add(shot)
        app.typeKey("z", modifierFlags: .command)
        let restored = NSPredicate(format: "value ENDSWITH %@", "immagine: 200\u{00D7}200")
        wait(for: [expectation(for: restored, evaluatedWith: canvas)], timeout: 5)
        app.terminate()
    }
}
