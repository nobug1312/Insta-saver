import XCTest

final class IGSaveUITests: XCTestCase {
    @MainActor
    func testHomePreviewSelectionAndClear() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.staticTexts["homeTitle"].waitForExistence(timeout: 10))
        capture("home", app)

        let link = app.textFields["linkField"]
        link.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        app.staticTexts["homeTitle"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        link.tap()
        link.typeText("https://www.instagram.com/p/IGSaveDemo/\n")
        XCTAssertTrue(app.buttons["preview-0"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        capture("gallery", app)

        app.buttons["preview-0"].tap()
        XCTAssertTrue(app.buttons["closePreview"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["previewCounter"].label.contains("1 of 3"))
        let photo = app.scrollViews["fullSizePhoto"]
        XCTAssertTrue(photo.waitForExistence(timeout: 10))
        capture("preview", app)
        photo.doubleTap()
        let zoomed = NSPredicate(format: "value == %@", "250%")
        expectation(for: zoomed, evaluatedWith: photo)
        waitForExpectations(timeout: 3)
        capture("zoom", app)
        photo.swipeDown()
        XCTAssertTrue(app.buttons["closePreview"].exists, "Panning a zoomed photo must not dismiss the viewer")
        photo.doubleTap()
        let resetZoom = NSPredicate(format: "value == %@", "100%")
        expectation(for: resetZoom, evaluatedWith: photo)
        waitForExpectations(timeout: 3)
        app.buttons["previewSelection"].tap()
        XCTAssertEqual(app.buttons["previewSelection"].label, "[ ] Select for saving")
        app.swipeLeft()
        XCTAssertTrue(app.staticTexts["previewCounter"].label.contains("2 of 3"))
        XCTAssertTrue(app.scrollViews["fullSizePhoto"].waitForExistence(timeout: 5))
        app.swipeRight()
        XCTAssertEqual(app.staticTexts["previewCounter"].label, "1 of 3")
        XCTAssertTrue(app.scrollViews["fullSizePhoto"].waitForExistence(timeout: 5))
        app.buttons["closePreview"].tap()
        XCTAssertEqual(app.buttons["selectAll"].value as? String, "2 of 3 selected")
        capture("selection", app)
        app.buttons["preview-0"].tap()
        XCTAssertTrue(app.scrollViews["fullSizePhoto"].waitForExistence(timeout: 5))
        app.scrollViews["fullSizePhoto"].swipeDown()
        XCTAssertTrue(app.buttons["closePreview"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["selectAll"].exists)
        app.buttons["selectAll"].tap()
        XCTAssertEqual(app.buttons["selectAll"].value as? String, "3 of 3 selected")
        app.buttons["selectAll"].tap()
        XCTAssertFalse(app.buttons["saveMedia"].isEnabled)
        app.buttons["clearLink"].tap()
        XCTAssertTrue(app.staticTexts["homeTitle"].exists)
        XCTAssertFalse(app.buttons["preview-0"].exists)
        XCTAssertFalse(app.buttons["clearLink"].exists)
    }

    @MainActor
    func testLongAlbumScrollingKeepsSelection() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--long-album"]
        app.launch()
        let link = app.textFields["linkField"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.tap()
        link.typeText("https://www.instagram.com/p/IGSaveDemo/\n")
        XCTAssertTrue(app.buttons["select-0"].waitForExistence(timeout: 10))
        app.buttons["select-0"].tap()
        XCTAssertEqual(app.buttons["selectAll"].value as? String, "29 of 30 selected")
        for _ in 0..<18 {
            if app.buttons["select-29"].isHittable { break }
            app.swipeUp(velocity: .fast)
        }
        XCTAssertTrue(app.buttons["select-29"].isHittable)
        app.buttons["select-29"].tap()
        XCTAssertEqual(app.buttons["selectAll"].value as? String, "28 of 30 selected")
        for _ in 0..<18 {
            if app.buttons["select-0"].isHittable { break }
            app.swipeDown(velocity: .fast)
        }
        XCTAssertTrue(app.buttons["select-0"].isHittable)
        XCTAssertEqual(app.buttons["select-0"].value as? String, "Not selected")
        app.buttons["preview-0"].tap()
        XCTAssertTrue(app.buttons["closePreview"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["previewCounter"].label, "1 of 30")
    }

    @MainActor
    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
