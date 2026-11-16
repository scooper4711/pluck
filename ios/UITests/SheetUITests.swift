import XCTest

/// The sheets behind the toolbar's More menu (docs/specs/ipad-app R6).
final class SheetUITests: PluckUITestCase {
    /// About shows Paizo's Community Use Policy notice (tabletop-kit R6.1).
    func testAboutShowsTheCommunityUseNotice() {
        launch()
        XCTAssertTrue(app.buttons["More"].waitForExistence(timeout: 15), app.debugDescription)
        chooseFromMoreMenu("About Pluck")
        let notice = app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH %@", "Pluck uses trademarks and/or copyrights owned by Paizo"))
        XCTAssertTrue(notice.firstMatch.waitForExistence(timeout: 5), "No Community Use Policy notice")
        keepScreenshot("About")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Open a PDF"].waitForExistence(timeout: 5))
    }

    func testSettingsShowTheExportAndTextOptions() {
        launch()
        XCTAssertTrue(app.buttons["More"].waitForExistence(timeout: 15), app.debugDescription)
        chooseFromMoreMenu("Settings…")
        XCTAssertTrue(app.switches["Lossless"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.switches["Write Markdown info boxes as Obsidian callouts"].exists, app.debugDescription)
        keepScreenshot("Settings")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Open a PDF"].waitForExistence(timeout: 5))
    }
}
