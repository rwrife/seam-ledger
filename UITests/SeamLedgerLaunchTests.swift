import XCTest

final class SeamLedgerLaunchTests: XCTestCase {
    @MainActor
    func testBootstrapHomeLaunches() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Seam Ledger"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Pieces, cut counts, seam allowances and fitting notes are planned, not available yet."].exists)
    }
}
