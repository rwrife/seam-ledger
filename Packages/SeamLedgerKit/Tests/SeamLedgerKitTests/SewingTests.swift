import Testing
@testable import SeamLedgerKit

@Suite struct SewingTests {
    @Test func exactAllowances() throws {
        let mm = try Allowance(10, unit: .millimetre)
        #expect(try mm == Allowance(1, unit: .centimetre))
        #expect(try AllowanceComparison.compare(mm, Allowance(5, denominator: 8, unit: .inch)) == .mismatch)
        #expect(try AllowanceComparison.compare(mm, Allowance(1, unit: .centimetre)) == .equal)
        #expect(AllowanceComparison.compare(nil, mm) == .unknown)
        #expect(AllowanceComparison.compare(nil, nil) == .unknown)
        #expect(try Allowance(0, denominator: .max, unit: .inch).denominator == 1)
        #expect(try Allowance(.max, denominator: .max, unit: .inch).numerator == 25_400)
        #expect(try Allowance(1, denominator: 3, unit: .micrometre).denominator == 3)
        #expect(throws: LedgerError.overflow) { try Allowance(.max, unit: .inch) }
        #expect(throws: LedgerError.invalidInput) { try Allowance(-1, unit: .inch) }
        #expect(throws: LedgerError.invalidInput) { try Allowance(.min, unit: .inch) }
        #expect(throws: LedgerError.invalidInput) { try Allowance(1, denominator: 0, unit: .inch) }
        #expect(throws: LedgerError.invalidInput) { try Allowance(1, denominator: -1, unit: .inch) }
    }

    @Test func physicalPiecesAndReconciliation() throws {
        let definition = try ProjectDefinition(pieces: [.mirroredPair(id: "pair", cutOnFold: true), Piece(id: "unknown", requiredCount: nil)])
        var project = try SewingProject(definition: definition)
        #expect(try project.remaining(pieceID: "pair") == 2)
        #expect(try project.remaining(pieceID: "unknown") == nil)
        let cut = SewingEvent(id: "cut", revision: 0, action: .cut(pieceID: "pair", physicalIndex: 1))
        try project.apply(cut)
        #expect(try project.remaining(pieceID: "pair") == 1)
        #expect(throws: LedgerError.invalidTransition) { try project.apply(cut) }
        #expect(throws: LedgerError.invalidTransition) { try project.apply(.init(id: "duplicate", revision: 0, action: cut.action)) }
        #expect(throws: LedgerError.invalidInput) { try project.apply(.init(id: "bad", revision: 0, action: .cut(pieceID: "pair", physicalIndex: 3))) }
        #expect(throws: LedgerError.invalidInput) { try project.apply(.init(id: "unknown", revision: 0, action: .cut(pieceID: "unknown", physicalIndex: 1))) }
        try project.apply(.init(id: "undo", revision: 0, action: .undoCut(pieceID: "pair", physicalIndex: 1)))
        #expect(throws: LedgerError.invalidTransition) { try project.apply(.init(id: "undo-again", revision: 0, action: .undoCut(pieceID: "pair", physicalIndex: 1))) }
        try project.apply(.init(id: "recut", revision: 0, action: cut.action))
        let changed = try ProjectDefinition(pieces: [Piece(id: "pair", requiredCount: 1)])
        try project.apply(.init(id: "reconcile", revision: 0, action: .reconcile(changed)))
        #expect(project.revision == 1)
        #expect(try project.remaining(pieceID: "pair") == 1)
        #expect(project.history.count == 4)
        #expect(throws: LedgerError.reconciliationRequired) { try project.apply(.init(id: "stale", revision: 0, action: cut.action)) }
        try project.apply(.init(id: "new", revision: 1, action: cut.action))
        #expect(try project.remaining(pieceID: "pair") == 0)
        #expect(throws: LedgerError.invalidInput) { try Piece(id: "x", requiredCount: 0) }
        #expect(throws: LedgerError.invalidInput) { try ProjectDefinition(pieces: [definition.pieces[0], definition.pieces[0]]) }
    }

    @Test func independentSeamEventsAndPairing() throws {
        let mm = try Allowance(10, unit: .millimetre)
        let definition = try ProjectDefinition(pieces: [Piece(id: "p", requiredCount: 1)], edges: [
            Edge(id: "a", pieceID: "p", allowance: mm),
            Edge(id: "b", pieceID: "p", allowance: nil),
            Edge(id: "c", pieceID: "p", allowance: Allowance(1, unit: .centimetre)),
            Edge(id: "d", pieceID: "p", allowance: Allowance(5, denominator: 8, unit: .inch)),
        ], seams: [Seam(id: "unknown", firstEdgeID: "a", secondEdgeID: "b"),
                   Seam(id: "equal", firstEdgeID: "a", secondEdgeID: "c"),
                   Seam(id: "mismatch", firstEdgeID: "a", secondEdgeID: "d")])
        #expect(try definition.comparison(for: "unknown") == .unknown)
        #expect(try definition.comparison(for: "equal") == .equal)
        #expect(try definition.comparison(for: "mismatch") == .mismatch)
        var p = try SewingProject(definition: definition)
        try p.apply(.init(id: "press", revision: 0, action: .pressed(seamID: "unknown")))
        #expect(p.sewn.isEmpty)
        try p.apply(.init(id: "sew", revision: 0, action: .sewn(seamID: "unknown")))
        #expect(throws: LedgerError.invalidTransition) { try p.apply(.init(id: "press2", revision: 0, action: .pressed(seamID: "unknown"))) }
        #expect(throws: LedgerError.invalidTransition) { try p.apply(.init(id: "sew2", revision: 0, action: .sewn(seamID: "unknown"))) }
        try p.apply(.init(id: "unsew", revision: 0, action: .undoSewn(seamID: "unknown")))
        #expect(p.pressed == ["unknown"])
        try p.apply(.init(id: "unpress", revision: 0, action: .undoPressed(seamID: "unknown")))
        #expect(throws: LedgerError.invalidTransition) { try p.apply(.init(id: "unpress2", revision: 0, action: .undoPressed(seamID: "unknown"))) }
        #expect(throws: LedgerError.invalidInput) { try p.apply(.init(id: "missing", revision: 0, action: .sewn(seamID: "absent"))) }
        #expect(p.history.count == 4)
    }
}
