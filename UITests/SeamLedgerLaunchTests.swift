import XCTest

final class SeamLedgerLaunchTests: XCTestCase {
    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let visible = app.frame.insetBy(dx: 0, dy: 100)
        var previousFrame: CGRect?
        for _ in 0..<20 {
            if element.exists {
                let frame = element.frame
                if element.isHittable && (visible.contains(frame) || frame == previousFrame) { return }
                previousFrame = frame
                if frame.midY < visible.midY { app.swipeDown() }
                else { app.swipeUp() }
            } else {
                app.swipeUp()
            }
        }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }

    @MainActor
    private func enter(_ value: String, id: String, in app: XCUIApplication) {
        let field = app.textFields[id]
        reveal(field, in: app)
        field.tap()
        field.typeText(value)
        app.keyboards.buttons["Done"].tap()
    }

    @MainActor
    private func choose(_ value: String, id: String, in app: XCUIApplication) throws {
        let picker = app.buttons[id]
        reveal(picker, in: app)
        picker.tap()
        let option = app.buttons[value]
        try XCTUnwrap(option.waitForExistence(timeout: 10) ? option : nil, app.debugDescription).tap()
    }

    @MainActor
    func testAllowancesUndoAndPersistedAlteration() throws {
        let app = XCUIApplication()
        app.launch()
        let name = "Seams-\(UUID().uuidString.prefix(8))"
        enter(name, id: "project.name", in: app)
        app.buttons["project.create"].tap()
        enter("Panel", id: "piece.name", in: app)
        let addPiece = app.buttons["piece.add"]
        reveal(addPiece, in: app)
        addPiece.tap()
        let sewing = app.buttons["workspace.sewing"]
        reveal(sewing, in: app)
        sewing.tap()
        try choose("Panel", id: "edge.piece", in: app)
        for (edge, value, unit) in [("A", "10", "mm"), ("B", "", "mm"),
                                    ("C", "1", "cm"), ("D", "5/8", "inch")] {
            enter(edge, id: "edge.name", in: app)
            if !value.isEmpty { enter(value, id: "edge.allowance", in: app) }
            let unitButton = app.segmentedControls["edge.unit"].buttons[unit]
            reveal(unitButton, in: app)
            unitButton.tap()
            let addEdge = app.buttons["edge.add"]
            reveal(addEdge, in: app)
            addEdge.tap()
        }
        for (seam, second, comparison) in [
            ("Missing", "B", "Allowance unspecified; comparison unavailable"),
            ("Equal", "C", "Recorded allowances equal"),
            ("Different", "D", "Warning: recorded allowances differ")
        ] {
            enter(seam, id: "seam.name", in: app)
            try choose("A", id: "seam.first", in: app)
            try choose(second, id: "seam.second", in: app)
            let link = app.buttons["seam.link"]
            reveal(link, in: app)
            link.tap()
            let result = app.staticTexts["seam.comparison.\(seam)"]
            reveal(result, in: app)
            XCTAssertEqual(result.label, comparison)
        }
        let pressed = app.buttons["seam.pressed.Equal"]
        reveal(pressed, in: app)
        pressed.tap()
        let sewn = app.buttons["seam.sewn.Equal"]
        XCTAssertEqual(sewn.label, "Mark sewn Equal")
        reveal(sewn, in: app)
        sewn.tap()
        sewn.tap()
        XCTAssertEqual(sewn.label, "Mark sewn Equal")
        XCTAssertEqual(pressed.label, "Undo pressed Equal")
        enter("Shortened hem by hand", id: "alteration.note", in: app)
        enter("20", id: "alteration.before", in: app)
        enter("15", id: "alteration.after", in: app)
        let save = app.buttons["alteration.save"]
        reveal(save, in: app)
        save.tap()
        XCTAssertFalse(app.staticTexts["sewing.error"].exists, app.debugDescription)
        app.terminate()
        app.launch()
        app.buttons[name].tap()
        app.buttons["workspace.sewing"].tap()
        let persisted = app.staticTexts["Shortened hem by hand"]
        reveal(persisted, in: app)
        XCTAssertTrue(persisted.exists)
        XCTAssertTrue(app.staticTexts["Before: 20000 micrometres"].exists)
        XCTAssertTrue(app.staticTexts["After: 15000 micrometres"].exists)
        reveal(pressed, in: app)
        XCTAssertEqual(pressed.label, "Undo pressed Equal")
        pressed.tap()
        XCTAssertEqual(pressed.label, "Mark pressed Equal")
        XCTAssertEqual(sewn.label, "Mark sewn Equal")
    }

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
        XCTAssertTrue(app.staticTexts["reference.page"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["reference.next"].tap()
        XCTAssertEqual(app.staticTexts["reference.page"].label, "Page 2 of 2")
        let pieceName = app.textFields["piece.name"]
        reveal(pieceName, in: app)
        XCTAssertTrue(pieceName.isHittable, app.debugDescription)
        pieceName.tap()
        pieceName.typeText("Sleeves")
        app.keyboards.buttons["Done"].tap()
        let mirrored = app.switches["piece.mirrored"]
        for _ in 0..<3 where !mirrored.isHittable { app.swipeUp() }
        mirrored.tap()
        XCTAssertTrue(String(describing: mirrored.value).contains("1"))
        let addPiece = app.buttons["piece.add"]
        reveal(addPiece, in: app)
        addPiece.tap()
        let first = app.buttons["cut.Sleeves.1"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        reveal(first, in: app)
        first.tap()
        XCTAssertTrue(app.staticTexts["1 cut of 2; 1 remaining"].waitForExistence(timeout: 10))
        let sewing = app.buttons["workspace.sewing"]
        reveal(sewing, in: app)
        sewing.tap()
        XCTAssertEqual(app.staticTexts["reference.page"].label, "Page 2 of 2")
        app.buttons["workspace.cutting"].tap()
        XCTAssertTrue(app.staticTexts["1 cut of 2; 1 remaining"].exists)
        XCTAssertEqual(app.staticTexts["reference.page"].label, "Page 2 of 2")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertEqual(app.staticTexts["reference.page"].label, "Page 2 of 2")
        XCUIDevice.shared.orientation = .portrait
        app.terminate()
        app.launch()
        app.buttons[uniqueName].tap()
        XCTAssertTrue(app.staticTexts["1 cut of 2; 1 remaining"].waitForExistence(timeout: 10))
        reveal(app.buttons["cut.Sleeves.1"], in: app)
        app.buttons["cut.Sleeves.1"].tap()
        XCTAssertTrue(app.staticTexts["0 cut of 2; 2 remaining"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testAccessibilitySizeWorkspaceReflows() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestPDF", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        enter("Large type", id: "project.name", in: app)
        app.buttons["project.create"].tap()
        app.buttons["reference.import"].tap()
        XCTAssertTrue(app.staticTexts["reference.page"].waitForExistence(timeout: 10))
        enter("Panel", id: "piece.name", in: app)
        let addPiece = app.buttons["piece.add"]
        reveal(addPiece, in: app)
        addPiece.tap()
        let sewing = app.buttons["workspace.sewing"]
        reveal(sewing, in: app)
        sewing.tap()
        XCTAssertTrue(app.staticTexts["reference.page"].exists)
        let note = app.textFields["alteration.note"]
        reveal(note, in: app)
        XCTAssertTrue(note.isHittable)
    }
}
