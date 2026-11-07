import XCTest

final class SeamLedgerLaunchTests: XCTestCase {
    @MainActor
    func testCreateMirroredCutUndoAfterRelaunch() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Offline cutting table"].waitForExistence(timeout: 10))
        let projectName = app.textFields["project.name"]
        projectName.tap()
        projectName.typeText("Linen jacket")
        app.buttons["project.create"].tap()
        XCTAssertTrue(app.buttons["reference.import"].waitForExistence(timeout: 10))
        let pieceName = app.textFields["piece.name"]
        pieceName.tap()
        pieceName.typeText("Sleeves")
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
        app.buttons["Linen jacket"].tap()
        XCTAssertTrue(app.staticTexts["1 cut of 2; 1 remaining"].waitForExistence(timeout: 10))
        app.buttons["cut.Sleeves.1"].tap()
        XCTAssertTrue(app.staticTexts["0 cut of 2; 2 remaining"].waitForExistence(timeout: 10))
    }
}
