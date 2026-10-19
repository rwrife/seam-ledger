import Foundation
import Testing
import GRDB
import SeamLedgerKit
@testable import SeamLedgerStore

@Suite struct ProjectStoreTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func definition() throws -> ProjectDefinition {
        try ProjectDefinition(pieces: [.mirroredPair(id: "pair", cutOnFold: true)], edges: [
            Edge(id: "a", pieceID: "pair", allowance: Allowance(10, unit: .millimetre)),
            Edge(id: "b", pieceID: "pair", allowance: nil),
            Edge(id: "c", pieceID: "pair", allowance: Allowance(1, unit: .centimetre)),
            Edge(id: "d", pieceID: "pair", allowance: Allowance(5, denominator: 8, unit: .inch))
        ], seams: [Seam(id: "s", firstEdgeID: "a", secondEdgeID: "b"),
                   Seam(id: "equal", firstEdgeID: "a", secondEdgeID: "c"),
                   Seam(id: "mismatch", firstEdgeID: "a", secondEdgeID: "d")])
    }

    @Test func atomicRollbackAndDurability() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("store.sqlite").path
        let store = try ProjectStore(path: path)
        try store.create(id: "p", definition: definition())
        let cut = SewingEvent(id: "cut", revision: 0, action: .cut(pieceID: "pair", physicalIndex: 1))
        #expect(throws: LedgerError.invalidTransition) {
            try store.append(projectID: "p", events: [cut, .init(id: "duplicate", revision: 0, action: cut.action)])
        }
        // First INSERT ran before the second event failed: prove SQL rollback directly.
        let inspection = try DatabaseQueue(path: path)
        #expect(try inspection.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM events") } == 0)
        #expect(try store.load(id: "p").remaining(pieceID: "pair") == 2)
        // Force a database failure after one successful INSERT, independently of validation.
        try inspection.write { db in
            try db.execute(sql: "CREATE TRIGGER reject_test_event BEFORE INSERT ON events WHEN NEW.eventID = 'reject' BEGIN SELECT RAISE(ABORT, 'forced rollback'); END")
        }
        #expect(throws: DatabaseError.self) {
            try store.append(projectID: "p", events: [cut, .init(id: "reject", revision: 0, action: .pressed(seamID: "s"))])
        }
        #expect(try inspection.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM events") } == 0)
        try inspection.write { try $0.execute(sql: "DROP TRIGGER reject_test_event") }
        try store.append(projectID: "p", events: [cut, .init(id: "press", revision: 0, action: .pressed(seamID: "s")), .init(id: "sew", revision: 0, action: .sewn(seamID: "s"))])
        let reopened = try ProjectStore(path: path)
        #expect(try reopened.load(id: "p").history.count == 3)
        #expect(try reopened.load(id: "p").pressed == ["s"])
        #expect(try reopened.load(id: "p").definition.comparison(for: "s") == .unknown)
        #expect(try reopened.load(id: "p").definition.comparison(for: "equal") == .equal)
        #expect(try reopened.load(id: "p").definition.comparison(for: "mismatch") == .mismatch)
        try reopened.append(projectID: "p", events: [.init(id: "undo", revision: 0, action: .undoCut(pieceID: "pair", physicalIndex: 1))])
        #expect(try reopened.load(id: "p").remaining(pieceID: "pair") == 2)
        let changed = try ProjectDefinition(pieces: [Piece(id: "pair", requiredCount: nil)])
        try reopened.append(projectID: "p", events: [.init(id: "reconcile", revision: 0, action: .reconcile(changed))])
        #expect(throws: LedgerError.reconciliationRequired) { try reopened.append(projectID: "p", events: [.init(id: "stale", revision: 0, action: cut.action)]) }
        let final = try ProjectStore(path: path).load(id: "p")
        #expect(final.revision == 1)
        #expect(final.sewn.isEmpty && final.pressed.isEmpty)
        #expect(try final.remaining(pieceID: "pair") == nil)
        #expect(final.history.count == 5)
        let isolated = try ProjectStore(path: dir.appendingPathComponent("isolated.sqlite").path)
        #expect(throws: LedgerError.invalidInput) { try isolated.load(id: "p") }
    }

    @Test func migratesRealV1Fixture() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("upgrade.sqlite").path
        let fixture = try #require(Bundle.module.url(forResource: "v1", withExtension: "sqlite", subdirectory: "Fixtures"))
        try FileManager.default.copyItem(atPath: fixture.path, toPath: path)
        let before = try DatabaseQueue(path: path)
        #expect(try before.read { try String.fetchAll($0, sql: "SELECT identifier FROM grdb_migrations") } == ["v1-projects"])
        #expect(try before.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM sqlite_master WHERE name='events'") } == 0)
        let store = try ProjectStore(path: path)
        #expect(try store.load(id: "legacy").remaining(pieceID: "pair") == 2)
        try store.append(projectID: "legacy", events: [.init(id: "cut", revision: 0, action: .cut(pieceID: "pair", physicalIndex: 2))])
        #expect(try ProjectStore(path: path).load(id: "legacy").remaining(pieceID: "pair") == 1)
        #expect(try before.read { try String.fetchAll($0, sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier") } == ["v1-projects", "v2-events"])
    }
}
