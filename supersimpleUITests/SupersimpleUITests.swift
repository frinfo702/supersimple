import XCTest

/// UI tests for supersimple: structural layout verification + window screenshot capture.
///
/// Screenshots are written to `Tests/Snapshots/actual/`. A separate script
/// (`Scripts/compare_snapshots.sh`) diffs them against the committed fixtures in
/// `Tests/Snapshots/` with a 0.1% pixel threshold and writes a diff image on failure.
final class SupersimpleUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // supersimpleUITests
            .deletingLastPathComponent()  // repo root
    }

    private var actualDir: URL {
        repoRoot.appendingPathComponent("Tests/Snapshots/actual", isDirectory: true)
    }

    // MARK: - Structural layout

    @MainActor
    func testAppLaunches() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testSidebarAndEditorHaveExpectedFrames() throws {
        let app = XCUIApplication()
        app.launch()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))

        // Create a note so the sidebar has content regardless of real data.
        let newNoteButton = app.buttons["new-note-button"]
        XCTAssertTrue(newNoteButton.waitForExistence(timeout: 5))
        newNoteButton.click()

        let editor = app.descendants(matching: .any)["editor-surface"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))

        // Editor fills the right side and is meaningfully sized.
        let editorFrame = editor.frame
        XCTAssertGreaterThan(editorFrame.width, 400, "editor should be wide, got \(editorFrame.width)")
        XCTAssertGreaterThan(editorFrame.height, 300, "editor should be tall")
        // Sidebar can sit at its 200pt minimum in a small CI window.
        XCTAssertGreaterThanOrEqual(editorFrame.minX, 200)
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
    }

    @MainActor
    func testSidebarToggleButtonExists() throws {
        let app = XCUIApplication()
        app.launch()
        let toggle = app.buttons["toggle-sidebar-button"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertTrue(toggle.isEnabled)
    }

    @MainActor
    func testToolbarActionsExist() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["toggle-sidebar-button"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["new-note-button"].exists)
        XCTAssertTrue(app.buttons["sidebar-search-button"].exists)
        XCTAssertTrue(app.buttons["current-theme-icon"].exists)
        XCTAssertFalse(app.buttons["sidebar-appearance-button"].exists)
        XCTAssertFalse(app.buttons["theme-light-button"].exists)
        XCTAssertFalse(app.buttons["toggle-bottom-bar-button"].exists)
        XCTAssertFalse(app.buttons["export-note-button"].exists)
    }

    @MainActor
    func testSearchButtonRevealsSearchField() throws {
        let app = XCUIApplication()
        app.launch()
        let searchButton = app.buttons["sidebar-search-button"]
        XCTAssertTrue(searchButton.waitForExistence(timeout: 5))
        searchButton.click()
        let field = app.descendants(matching: .any)["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
    }

    @MainActor
    func testChromeSearchAppearsWhenSidebarHidden() throws {
        let app = XCUIApplication()
        app.launch()
        let toggle = app.buttons["toggle-sidebar-button"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.click()
        XCTAssertTrue(app.buttons["sidebar-search-button"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["new-note-button"].exists)
    }

    // MARK: - Screenshot capture

    @MainActor
    func testCaptureWindowScreenshot() throws {
        let app = XCUIApplication()
        app.launch()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1.5)

        let png = window.screenshot().pngRepresentation
        try FileManager.default.createDirectory(at: actualDir, withIntermediateDirectories: true)
        let out = actualDir.appendingPathComponent("window.png")
        try png.write(to: out)
        XCTAssertGreaterThan(png.count, 10_000, "window screenshot unexpectedly small/blank")
        print("wrote actual window screenshot to \(out.path)")
    }
}
