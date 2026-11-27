import Testing
@testable import SeamLedgerKit

@Suite struct CSVReportTests {
    @Test func cutsQuoteNamesAndNeutralizeSpreadsheetFormulas() throws {
        let project = try SewingProject(definition: ProjectDefinition(pieces: [
            Piece(id: "Panel, \"front\"\nsecond", requiredCount: 2),
            Piece(id: "  =1+1", requiredCount: nil),
            Piece(id: "\t@command", requiredCount: 1)
        ]))
        let report = CSVReport.cuts(project)
        #expect(report.contains("\"Panel, \"\"front\"\"\nsecond\",\"outer\",\"2\",\"0\",\"2\""))
        #expect(report.contains("\"'  =1+1\",\"outer\",\"\",\"0\",\"\""))
        #expect(report.contains("\"'\t@command\""))
    }

    @Test func seamReportUsesExactValuesAndIndependentProgress() throws {
        let definition = try ProjectDefinition(pieces: [Piece(id: "p", requiredCount: 1)], edges: [
            Edge(id: "a", pieceID: "p", allowance: Allowance(10, unit: .millimetre)),
            Edge(id: "b", pieceID: "p", allowance: nil)
        ], seams: [Seam(id: "+seam", firstEdgeID: "a", secondEdgeID: "b")])
        var project = try SewingProject(definition: definition)
        try project.apply(.init(id: "press", revision: 0, action: .pressed(seamID: "+seam")))
        let report = try CSVReport.seams(project)
        #expect(report.contains("\"'+seam\",\"a\",\"10000 micrometres\",\"b\",\"unspecified\",\"unspecified\",\"no\",\"yes\""))
    }
}
