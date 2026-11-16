import XCTest

/// The window in both orientations, empty and with a PDF (docs/specs/ipad-app R1.1, R8.1). Each test keeps a
/// screenshot in the test results.
final class LayoutUITests: PluckUITestCase {
    func testEmptyWindowInLandscape() {
        showEmptyWindow(.landscapeLeft)
    }

    func testEmptyWindowInPortrait() {
        showEmptyWindow(.portrait)
    }

    func testImagesInLandscape() {
        showImages(.landscapeLeft)
    }

    func testImagesInPortrait() {
        showImages(.portrait)
    }

    func testOpenFromScrollkeeperSaysWhereTheTitlesComeFrom() {
        launch()
        app.buttons["Open from Scrollkeeper…"].tap()
        // Unsigned in the simulator, the app has no App Group, so there is no library to show. What it says depends
        // on whether the simulator has Scrollkeeper installed.
        let notice = app.staticTexts.matching(NSPredicate(
            format: "label IN %@", ["Scrollkeeper Isn't Installed", "Scrollkeeper Hasn't Shared Your Library"]))
        XCTAssertTrue(notice.firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        keepScreenshot("Open from Scrollkeeper")
    }

    private func showEmptyWindow(_ orientation: UIDeviceOrientation) {
        launch(orientation)
        XCTAssertTrue(app.buttons["Open…"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["Open…"].isHittable)
        XCTAssertTrue(app.buttons["Open from Scrollkeeper…"].isHittable)
        keepScreenshot("Empty window, \(orientation == .portrait ? "portrait" : "landscape")")
    }

    private func showImages(_ orientation: UIDeviceOrientation) {
        launchWithSample(orientation)
        XCTAssertEqual(images.count, 3)
        XCTAssertTrue(images.element(boundBy: 2).isHittable, "The last image is off screen")
        for action in ["Open", "Rotate and Flip", "Copy", "Quick Look", "Export", "More"] {
            XCTAssertTrue(app.buttons[action].isHittable, "No \(action) button in the toolbar")
        }
        keepScreenshot("Images, \(orientation == .portrait ? "portrait" : "landscape")")
    }
}
