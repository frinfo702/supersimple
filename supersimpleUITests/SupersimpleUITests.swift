import XCTest

final class SupersimpleUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCreateNoteViaMenu() throws {
        let app = XCUIApplication()
        app.launch()

        // New Note via keyboard shortcut.
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(app.windows.firstMatch.exists)

        // The window should exist and the app be responsive.
        XCTAssertTrue(app.windows.count >= 1)
    }

    @MainActor
    func testAppLaunches() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
    }
}
