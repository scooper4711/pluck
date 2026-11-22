import XCTest

/// The App Store's pictures, from the app's demo content: tabletop-kit's `store-screenshots.sh`.
/// Skipped unless the script names the folder to save into.
final class StoreScreenshots: PluckUITestCase {
    private var folder: URL!

    override func setUp() async throws {
        try await super.setUp()
        let path = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] ?? ""
        try XCTSkipIf(path.isEmpty, "Set SCREENSHOT_DIR to make the store screenshots.")
        folder = URL(fileURLWithPath: path)
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testImages() throws {
        let pdf = ProcessInfo.processInfo.environment["STORE_PDF"] ?? ""
        try XCTSkipIf(pdf.isEmpty, "Set STORE_PDF to the PDF to show.")
        app.launchEnvironment["UITestSampleFile"] = pdf
        launch(.portrait)
        XCTAssertTrue(status("4 images").waitForExistence(timeout: 60), app.debugDescription)
        try save("1-images")
        images.element(boundBy: 0).tap()
        try save("2-selected")
    }

    private func save(_ name: String) throws {
        Thread.sleep(forTimeInterval: 1.5)
        let file = folder.appendingPathComponent("\(name).png")
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: file)
    }
}
