import XCTest

/// On an iPhone the window is one screen at a time, with the mode's commands in a bar along the bottom
/// (docs/specs/ipad-app R9). Each test keeps a screenshot in the test results.
final class PhoneLayoutUITests: PluckUITestCase {
    override func setUp() async throws {
        try await super.setUp()
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "Only an iPhone has one screen at a time.")
    }

    func testTheImagesShowFirstWithEveryCommandInReach() {
        launchWithSample(.portrait)
        XCTAssertTrue(images.element(boundBy: 0).isHittable, app.debugDescription)
        for action in ["Open", "Images", "Text", "Rotate and Flip", "Copy", "Quick Look", "Export", "More"] {
            XCTAssertTrue(app.buttons[action].isHittable, "No \(action) button in the bars")
        }
        keepScreenshot("iPhone images, portrait")
    }

    func testTheTextCommandsAreInReach() {
        launchWithSample(.portrait)
        app.buttons["Text"].tap()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        for action in ["Format", "Copy All", "Export"] {
            XCTAssertTrue(app.buttons[action].isHittable, "No \(action) button in the bars")
        }
        keepScreenshot("iPhone text, portrait")
    }

    func testChoosingPagesAndComingBack() {
        launchWithSample(.portrait)
        app.buttons["BackButton"].tap()
        let secondPage = app.buttons["Page 2, 1 image"]
        XCTAssertTrue(secondPage.waitForExistence(timeout: 10), app.debugDescription)
        secondPage.tap()
        keepScreenshot("iPhone pages")
        app.buttons["Done"].tap()
        XCTAssertTrue(status("1 images").waitForExistence(timeout: 5), app.debugDescription)
    }

    func testShowPageInSidebarGoesToThePages() {
        launchWithSample(.portrait)
        images.element(boundBy: 0).press(forDuration: 1)
        let showPage = app.buttons["Show Page in Sidebar"]
        XCTAssertTrue(showPage.waitForExistence(timeout: 5), app.debugDescription)
        showPage.tap()
        XCTAssertTrue(app.buttons["Page 1, 2 images"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["Done"].isHittable, app.debugDescription)
    }

    func testImagesInLandscape() {
        launchWithSample(.landscapeLeft)
        XCTAssertTrue(images.element(boundBy: 0).isHittable, app.debugDescription)
        XCTAssertTrue(app.buttons["Copy"].isHittable, "No Copy button in landscape")
        keepScreenshot("iPhone images, landscape")
    }
}
