import Foundation
import Testing
@testable import SeamLedgerKit

@Suite struct SewingTests {
    @Test func exactUserEnteredMeasurements() throws {
        #expect(try Allowance.parse("  ", unit: .inch) == nil)
        #expect(try Allowance.parse("5/8", unit: .inch) == Allowance.parse("15.875", unit: .millimetre))
        #expect(try Allowance.parse("1.0", unit: .centimetre) == Allowance.parse("10", unit: .millimetre))
        #expect(try Allowance.parse("0", unit: .inch) == Allowance(0, unit: .millimetre))
        for invalid in ["1/0", "-1", "1.2.3", "1//2", "1e2", ".5", "1.", "NaN"] {
            #expect(throws: LedgerError.invalidInput) { try Allowance.parse(invalid, unit: .inch) }
        }
        #expect(throws: LedgerError.overflow) { try Allowance.parse("1.0000000000000000000", unit: .inch) }
        let value = try Allowance(5, denominator: 8, unit: .inch)
        #expect(try JSONDecoder().decode(Allowance.self, from: JSONEncoder().encode(value)) == value)
        #expect(throws: LedgerError.invalidInput) {
            try JSONDecoder().decode(Allowance.self, from: Data(#"{"numerator":1,"denominator":0}"#.utf8))
        }
    }

    @Test func edgeRemovalCleansOnlyRelatedProgressAndPreservesCutsAndNotes() throws {
        var project = try SewingProject(definition: ProjectDefinition(pieces: [Piece(id: "p", requiredCount: 1)]))
        func event(_ id: String, _ action: SewingAction) -> SewingEvent {
            SewingEvent(id: id, revision: 0, action: action)
        }
        try project.apply(event("cut", .cut(pieceID: "p", physicalIndex: 1)))
        for id in ["a", "b", "c"] {
            try project.apply(event(id, .addEdge(Edge(id: id, pieceID: "p", allowance: nil))))
        }
        try project.apply(event("s", .linkSeam(Seam(id: "s", firstEdgeID: "a", secondEdgeID: "b"))))
        try project.apply(event("t", .linkSeam(Seam(id: "t", firstEdgeID: "b", secondEdgeID: "c"))))
        try project.apply(event("sew", .sewn(seamID: "s")))
        try project.apply(event("press", .pressed(seamID: "s")))
        try project.apply(event("other", .pressed(seamID: "t")))
        let note = try AlterationNote(id: "note", text: "Shorten hem", before: Allowance(3, unit: .centimetre),
                                      after: Allowance(2, unit: .centimetre))
        try project.apply(event("note", .addAlteration(note)))
        let historyCount = project.history.count
        #expect(throws: LedgerError.invalidInput) {
            try project.apply(event("invalid", .linkSeam(Seam(id: "bad", firstEdgeID: "a", secondEdgeID: "missing"))))
        }
        #expect(project.history.count == historyCount)
        #expect(throws: LedgerError.invalidInput) {
            try project.apply(event("duplicate", .addEdge(Edge(id: "a", pieceID: "p", allowance: nil))))
        }
        try project.apply(event("remove", .removeEdge(edgeID: "a")))
        #expect(project.definition.seams.map(\.id) == ["t"])
        #expect(project.sewn.isEmpty)
        #expect(project.pressed == ["t"])
        #expect(project.completedCuts(pieceID: "p") == [1])
        #expect(project.alterations == [note])
        try project.apply(event("relink", .linkSeam(Seam(id: "s", firstEdgeID: "b", secondEdgeID: "c"))))
        #expect(!project.pressed.contains("s") && !project.sewn.contains("s"))
        try project.apply(event("unlink", .removeSeam(seamID: "t")))
        #expect(project.pressed.isEmpty)
        #expect(throws: LedgerError.invalidInput) { try project.apply(event("gone", .pressed(seamID: "t"))) }
        #expect(throws: LedgerError.invalidTransition) { try project.apply(event("dup-note", .addAlteration(note))) }
        try project.apply(event("reconcile", .reconcile(ProjectDefinition(pieces: []))))
        #expect(project.alterations == [note])
        #expect(throws: LedgerError.invalidInput) { try AlterationNote(id: "empty", text: "  ") }
        #expect(throws: LedgerError.invalidInput) { try AlterationNote(id: "photo", text: "Hem", photo: Data()) }
    }

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

    @Test func rejectedEventLeavesStateUnchanged() throws {
        var project = try SewingProject(definition: ProjectDefinition(pieces: [Piece(id: "p", requiredCount: 2)]))
        try project.apply(.init(id: "cut", revision: 0, action: .cut(pieceID: "p", physicalIndex: 1)))
        #expect(throws: LedgerError.invalidTransition) {
            try project.apply(.init(id: "dup", revision: 0, action: .cut(pieceID: "p", physicalIndex: 1)))
        }
        #expect(project.history.count == 1)
        #expect(try project.remaining(pieceID: "p") == 1)
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
