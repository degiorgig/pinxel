import XCTest

final class LaunchUITests: XCTestCase {
    func testAppLaunchesAsMenuBarAgent() {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(it)", "-PinxelUITestFakeCapture"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10) || app.wait(for: .runningBackground, timeout: 10))
        // Agent: no window at launch.
        XCTAssertEqual(app.windows.count, 0)
        app.terminate()
    }

    func testFirstLaunchAsksToOpenAtLogin() {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(en)", "-PinxelUITestFakeCapture", "-PinxelUITestAskLoginItem"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Open Pinxel at login?"].waitForExistence(timeout: 10))
        app.buttons["Not Now"].click()
        XCTAssertTrue(app.staticTexts["Open Pinxel at login?"].waitForNonExistence(timeout: 5))
        app.terminate()
    }

    func testSampleDocumentOpensEditorWindow() {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(it)", "-PinxelUITestFakeCapture", "-PinxelUITestOpenSample"]
        app.launch()
        XCTAssertTrue(app.images["pinxel.editor.canvas"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.windows.count, 1)
        app.terminate()
    }
}
