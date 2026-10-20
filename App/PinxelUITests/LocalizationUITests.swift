import XCTest

/// The app in four languages: menus and bar follow the language chosen at launch; an untranslated language gives English.
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
        // The window in every language, to check by eye for truncated labels (German and French are longer).
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
