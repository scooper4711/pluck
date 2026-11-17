import XCTest

/// Working with an open PDF by touch: selecting pages and images, editing, copying and reading the text
/// (docs/specs/ipad-app R2 to R4).
final class DocumentUITests: PluckUITestCase {
    func testTappingImagesSelectsAndDeselectsThem() {
        launchWithSample()
        images.element(boundBy: 0).tap()
        images.element(boundBy: 1).tap()
        XCTAssertTrue(status("3 images · 2 selected").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(images.element(boundBy: 0).isSelected)
        images.element(boundBy: 0).tap()
        XCTAssertTrue(status("3 images · 1 selected").waitForExistence(timeout: 5), app.debugDescription)
    }

    func testSelectAllAndDeselectAll() {
        launchWithSample()
        chooseFromMoreMenu("Select All")
        XCTAssertTrue(status("3 images · 3 selected").waitForExistence(timeout: 5), app.debugDescription)
        chooseFromMoreMenu("Deselect All")
        XCTAssertTrue(status("3 images").waitForExistence(timeout: 5), app.debugDescription)
    }

    func testCommandASelectsEveryImageButNotFromTheText() {
        launchWithSample()
        // The simulator drops the first key after a launch, so one that does nothing goes first.
        app.typeKey("l", modifierFlags: .command)
        app.typeKey("a", modifierFlags: .command)
        XCTAssertTrue(status("3 images · 3 selected").waitForExistence(timeout: 5), app.debugDescription)
        chooseFromMoreMenu("Deselect All")
        app.buttons["Text"].tap()
        let text = app.textViews.firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 10), app.debugDescription)
        text.tap()
        app.typeKey("a", modifierFlags: .command)
        // Over the text ⌘A is the text view's own; the images stay as they were.
        app.buttons["Images"].tap()
        XCTAssertTrue(status("3 images").waitForExistence(timeout: 5), app.debugDescription)
    }

    func testAnOpenedPDFJoinsOpenRecent() {
        launchWithSample()
        app.buttons["Open"].tap()
        app.buttons["Open Recent"].tap()
        XCTAssertTrue(app.buttons["UI Test Sample.pdf"].waitForExistence(timeout: 5), app.debugDescription)
        keepScreenshot("Open Recent")
        app.buttons["UI Test Sample.pdf"].tap()
        XCTAssertTrue(status("3 images").waitForExistence(timeout: 20), app.debugDescription)
    }

    func testClosingThePDFEmptiesTheWindow() {
        launchWithSample()
        app.buttons["Open"].tap()
        app.buttons["Close"].tap()
        XCTAssertTrue(app.staticTexts["Open a PDF"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(images.firstMatch.exists, "Images are still shown")
        app.buttons["Open"].tap()
        XCTAssertFalse(app.buttons["Close"].isEnabled, "Close is offered with no PDF open")
    }

    func testCopyingARotatedImage() {
        launchWithSample()
        XCTAssertFalse(app.buttons["Copy"].isEnabled, "Copy is offered with nothing selected")
        images.element(boundBy: 0).tap()
        app.buttons["Rotate and Flip"].tap()
        app.buttons["Rotate Left"].tap()
        keepScreenshot("First image rotated")
        app.buttons["Copy"].tap()
        XCTAssertTrue(status("Copied 1 image").waitForExistence(timeout: 10), app.debugDescription)
    }

    func testAnImagesMenuActsOnThatImage() {
        launchWithSample()
        images.element(boundBy: 0).tap()
        images.element(boundBy: 2).press(forDuration: 1)
        XCTAssertTrue(app.buttons["Show Page in Sidebar"].waitForExistence(timeout: 5), app.debugDescription)
        keepScreenshot("Image menu")
        app.buttons["Show Page in Sidebar"].tap()
        // The third picture is on page 2, and is now the only one selected.
        XCTAssertTrue(status("Page 2").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(status("3 images · 1 selected").exists, app.debugDescription)
    }

    func testTappingPagesNarrowsTheImages() {
        launchWithSample()
        let secondPage = app.buttons["Page 2, 1 image"]
        XCTAssertTrue(secondPage.waitForExistence(timeout: 10), app.debugDescription)
        secondPage.tap()
        XCTAssertTrue(status("1 images").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(secondPage.isSelected)
        keepScreenshot("Page 2 selected")
        app.buttons["Show All Pages"].tap()
        XCTAssertTrue(status("3 images").waitForExistence(timeout: 5), app.debugDescription)
    }

    func testReadingAndCopyingTheText() {
        launchWithSample()
        app.buttons["Text"].tap()
        let text = app.textViews.firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 10), app.debugDescription)
        let hasHeading = NSPredicate(format: "value CONTAINS %@", "The Clockwork Cellar")
        wait(for: [expectation(for: hasHeading, evaluatedWith: text)], timeout: 20)
        keepScreenshot("Text")
        app.buttons["Copy All"].tap()
        XCTAssertTrue(status("Copied text of 2 pages").waitForExistence(timeout: 5), app.debugDescription)
    }
}
