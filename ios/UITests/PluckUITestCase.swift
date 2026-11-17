import XCTest

/// What the UI tests share: launching the app, empty or with its sample PDF (`UITestSample` in PluckUI: two
/// pages, three pictures and a few lines of text), and keeping screenshots in the test results.
@MainActor
class PluckUITestCase: XCTestCase {
    let app = XCUIApplication()

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        XCUIDevice.shared.orientation = .portrait
    }

    func launch(_ orientation: UIDeviceOrientation = .landscapeLeft, withSample: Bool = false) {
        XCUIDevice.shared.orientation = orientation
        app.launchArguments = withSample ? ["-UITestSample"] : []
        app.launch()
    }

    /// Launches with the sample PDF and waits until its three pictures are in the grid.
    func launchWithSample(_ orientation: UIDeviceOrientation = .landscapeLeft) {
        launch(orientation, withSample: true)
        XCTAssertTrue(status("3 images").waitForExistence(timeout: 20), app.debugDescription)
    }

    var images: XCUIElementQuery {
        app.buttons.matching(identifier: "image")
    }

    /// A line of the status bar.
    func status(_ text: String) -> XCUIElement {
        app.staticTexts[text]
    }

    func chooseFromMoreMenu(_ item: String) {
        app.buttons["More"].tap()
        app.buttons[item].tap()
    }

    /// For a test that needs the pages beside the images, which an iPhone shows one at a time (PhoneLayoutUITests).
    func skipOnPhone() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .phone,
                      "The iPhone shows the pages on a screen of their own.")
    }

    func keepScreenshot(_ name: String) {
        // Let a rotation finish first. The screen's screenshot, unlike the app's, isn't cropped to portrait.
        Thread.sleep(forTimeInterval: 1)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
