import XCTest

final class LaunchUITests: XCTestCase {
    func testAppLaunchesAsMenuBarAgent() {
        let app = XCUIApplication()
        app.launchArguments = ["-PinxelUITestFakeCapture"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10) || app.wait(for: .runningBackground, timeout: 10))
        // Agente: nessuna finestra all'avvio.
        XCTAssertEqual(app.windows.count, 0)
        app.terminate()
    }
}
