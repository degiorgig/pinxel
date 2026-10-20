import XCTest

/// L'app nelle quattro lingue: i menu e la barra seguono la lingua scelta all'avvio; una lingua non tradotta dà l'inglese.
final class LocalizationUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ language: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(\(language))",
                               "-PinxelUITestLibraryName", UUID().uuidString, "-PinxelUITestFakeCapture", "-PinxelUITestOpenSample"]
        app.launch()
        app.activate()
        XCTAssertTrue(app.images["pinxel.editor.canvas"].waitForExistence(timeout: 10))
        return app
    }

    private func assertMenus(_ language: String, arrange: String, tool: String, file: StaticString = #filePath, line: UInt = #line) {
        let app = launch(language)
        defer { app.terminate() }
        // La finestra in ogni lingua, per controllare a occhio etichette tagliate (tedesco e francese sono più lunghi).
        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.name = "editor-\(language)"
        shot.lifetime = .keepAlways
        add(shot)
        XCTAssertTrue(app.menuBars.menuBarItems[arrange].waitForExistence(timeout: 5), "menu \(arrange)", file: file, line: line)
        XCTAssertTrue(app.toolbars.descendants(matching: .any)[tool].exists || app.radioButtons[tool].exists, "tool \(tool)", file: file, line: line)
    }

    func testEnglish() { assertMenus("en", arrange: "Arrange", tool: "Cut Out") }
    func testGerman() { assertMenus("de", arrange: "Anordnen", tool: "Ausschneiden und schließen") }
    func testFrench() { assertMenus("fr", arrange: "Disposition", tool: "Couper et rapprocher") }
    func testItalian() { assertMenus("it", arrange: "Disponi", tool: "Taglia e ricuci") }
    func testUnsupportedLanguageFallsBackToEnglish() { assertMenus("es", arrange: "Arrange", tool: "Cut Out") }
}
