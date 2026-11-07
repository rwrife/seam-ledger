import XCTest

final class SeamLedgerLaunchTests: XCTestCase {
    @MainActor
    func testCreateMirroredCutUndoAfterRelaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestPDF"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Offline cutting table"].waitForExistence(timeout: 10))
        let uniqueName = "Linen-\(UUID().uuidString.prefix(8))"
        let projectName = app.textFields["project.name"]
        projectName.tap()
        projectName.typeText(uniqueName)
        app.keyboards.buttons["Done"].tap()
        app.buttons["project.create"].tap()
        let importButton = app.buttons["reference.import"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 10))
        importButton.tap()
        XCTAssertFalse(app.staticTexts["Reference PDF missing"].exists)
        let pieceName = app.textFields["piece.name"]
        for _ in 0..<4 where !pieceName.isHittable { app.swipeUp() }
        pieceName.tap()
        pieceName.typeText("Sleeves")
        if app.keyboards.buttons["return"].exists { app.keyboards.buttons["return"].tap() }
        let mirrored = app.switches["piece.mirrored"]
        mirrored.tap()
        XCTAssertTrue(String(describing: mirrored.value).contains("1"))
        app.buttons["piece.add"].tap()
        let first = app.buttons["cut.Sleeves.1"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        first.tap()
        XCTAssertTrue(app.staticTexts["1 cut of 2; 1 remaining"].waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        app.buttons[uniqueName].tap()
        XCTAssertTrue(app.staticTexts["1 cut of 2; 1 remaining"].waitForExistence(timeout: 10))
        app.buttons["cut.Sleeves.1"].tap()
        XCTAssertTrue(app.staticTexts["0 cut of 2; 2 remaining"].waitForExistence(timeout: 10))
    }
}
