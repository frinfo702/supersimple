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
    func testCreateNoteViaSidebarButton() throws {
        let app = XCUIApplication()
        app.launch()

        let newNoteButton = app.buttons["new-note-button"]
        XCTAssertTrue(newNoteButton.waitForExistence(timeout: 5))
        XCTAssertTrue(newNoteButton.isEnabled)
        newNoteButton.click()

        XCTAssertTrue(app.descendants(matching: .any)["editor-surface"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.descendants(matching: .any)["notes-list"].exists)
    }

    @MainActor
    func testAppLaunches() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
    }
}
