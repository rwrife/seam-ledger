import Foundation
import Testing
import GRDB
import SeamLedgerKit
@testable import SeamLedgerStore

@Suite struct ProjectStoreTests {
    @Test func replaceAllIsAtomicAndDeleteAllRemovesOwnedDatabaseRecords() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("replace.sqlite").path
        let store = try ProjectStore(path: path)
        let originalDefinition = try ProjectDefinition(pieces: [Piece(id: "old", requiredCount: 2)])
        try store.create(id: "old-project", name: "Original", definition: originalDefinition)
        try store.append(projectID: "old-project", events: [
            .init(id: "old-cut", revision: 0, action: .cut(pieceID: "old", physicalIndex: 1))
        ])
        let original = try store.snapshot()

        let replacementDefinition = try ProjectDefinition(pieces: [Piece(id: "new", requiredCount: 1)])
        let replacementEvents = [SewingEvent(id: "reject", revision: 0,
                                             action: .cut(pieceID: "new", physicalIndex: 1))]
        let rejected = ProjectStore.ProjectSnapshot(id: "new-project", name: "Replacement", referenceFile: nil,
                                                    definition: replacementDefinition, events: replacementEvents)
        let inspection = try DatabaseQueue(path: path)
        try inspection.write { db in
            try db.execute(sql: "CREATE TRIGGER reject_restore BEFORE INSERT ON events WHEN NEW.eventID = 'reject' BEGIN SELECT RAISE(ABORT, 'forced restore failure'); END")
        }
        #expect(throws: DatabaseError.self) { try store.replaceAll(with: [rejected]) }
        #expect(try store.snapshot() == original)

        try inspection.write { try $0.execute(sql: "DROP TRIGGER reject_restore") }
        let accepted = ProjectStore.ProjectSnapshot(id: "new-project", name: "Replacement", referenceFile: nil,
                                                    definition: replacementDefinition, events: [
                                                        .init(id: "new-cut", revision: 0,
                                                              action: .cut(pieceID: "new", physicalIndex: 1))
                                                    ])
        try store.replaceAll(with: [accepted])
        #expect(try ProjectStore(path: path).snapshot() == [accepted])
        try store.deleteAll()
        #expect(try ProjectStore(path: path).snapshot().isEmpty)
        #expect(try ProjectStore(path: path).projects().isEmpty)
    }

    @Test func snapshotPreservesOriginalDefinitionAndOrderedPhotoHistory() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try ProjectStore(path: dir.appendingPathComponent("snapshot.sqlite").path)
        let original = try definition()
        try store.create(id: "p", name: "Project", definition: original)
        let reference = UUID().uuidString + ".pdf"
        try store.setReferenceFile(reference, projectID: "p")
        let note = try AlterationNote(id: "note", text: "Fitting", photo: Data([1, 2, 3]))
        let changed = try ProjectDefinition(pieces: [Piece(id: "new", requiredCount: 1)])
        let events: [SewingEvent] = [
            .init(id: "note", revision: 0, action: .addAlteration(note)),
            .init(id: "reconcile", revision: 0, action: .reconcile(changed)),
            .init(id: "cut", revision: 1, action: .cut(pieceID: "new", physicalIndex: 1))
        ]
        try store.append(projectID: "p", events: events)
        let snapshot = try #require(store.snapshot().first)
        #expect(snapshot.id == "p" && snapshot.name == "Project")
        #expect(snapshot.referenceFile == reference)
        #expect(snapshot.definition == original)
        #expect(snapshot.events == events)
    }

    @Test func snapshotRejectsInconsistentEventIdentity() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("corrupt.sqlite").path
        let store = try ProjectStore(path: path)
        try store.create(id: "p", definition: definition())
        try store.append(projectID: "p", events: [.init(id: "cut", revision: 0, action: .cut(pieceID: "pair", physicalIndex: 1))])
        let inspection = try DatabaseQueue(path: path)
        try inspection.write { try $0.execute(sql: "UPDATE events SET eventID = 'different'") }
        #expect(throws: LedgerError.invalidInput) { try store.snapshot() }
    }

    @Test func alterationAndEdgeChangesReplayAcrossReopens() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("alterations.sqlite").path
        let store = try ProjectStore(path: path)
        try store.create(id: "p", definition: definition())
        let note = try AlterationNote(id: "hem", text: "Shortened by hand after fitting",
                                      before: Allowance(2, unit: .inch), after: Allowance(45, unit: .millimetre),
                                      photo: Data([137, 80, 78, 71]))
        try store.append(projectID: "p", events: [
            .init(id: "cut", revision: 0, action: .cut(pieceID: "pair", physicalIndex: 1)),
            .init(id: "note", revision: 0, action: .addAlteration(note)),
            .init(id: "edge", revision: 0, action: .addEdge(Edge(id: "new", pieceID: "pair",
                                                            allowance: Allowance(10, unit: .millimetre)))),
            .init(id: "link", revision: 0, action: .linkSeam(Seam(id: "new-seam", firstEdgeID: "a", secondEdgeID: "new"))),
            .init(id: "sew", revision: 0, action: .sewn(seamID: "new-seam")),
            .init(id: "press", revision: 0, action: .pressed(seamID: "new-seam")),
            .init(id: "undo", revision: 0, action: .undoSewn(seamID: "new-seam"))
        ])
        let reopened = try ProjectStore(path: path)
        let loaded = try reopened.load(id: "p")
        #expect(loaded.alterations == [note])
        #expect(loaded.sewn.isEmpty && loaded.pressed == ["new-seam"])
        #expect(try loaded.definition.comparison(for: "new-seam") == .equal)
        try reopened.append(projectID: "p", events: [
            .init(id: "remove", revision: 0, action: .removeEdge(edgeID: "new"))
        ])
        let final = try ProjectStore(path: path).load(id: "p")
        #expect(!final.definition.seams.contains(where: { $0.id == "new-seam" }))
        #expect(final.pressed.isEmpty)
        #expect(final.completedCuts(pieceID: "pair") == [1])
        #expect(final.alterations == [note])
    }

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

    @Test func reconcileThenFailingEventRollsBackWholeBatch() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("batch.sqlite").path
        let store = try ProjectStore(path: path)
        try store.create(id: "p", definition: definition())
        let changed = try ProjectDefinition(pieces: [Piece(id: "pair", requiredCount: 1)])
        #expect(throws: LedgerError.reconciliationRequired) {
            try store.append(projectID: "p", events: [
                .init(id: "reconcile", revision: 0, action: .reconcile(changed)),
                .init(id: "stale", revision: 0, action: .cut(pieceID: "pair", physicalIndex: 1)),
            ])
        }
        let loaded = try ProjectStore(path: path).load(id: "p")
        #expect(loaded.revision == 0)
        #expect(loaded.history.isEmpty)
        #expect(try loaded.remaining(pieceID: "pair") == 2)
    }

    @Test func namedProjectsReferenceAndProgressSurviveRelaunch() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("workspace.sqlite").path
        let store = try ProjectStore(path: path)
        let empty = try ProjectDefinition(pieces: [])
        try store.create(id: "jacket", name: "Linen jacket", definition: empty)
        #expect(try store.projects().map(\.name) == ["Linen jacket"])
        #expect(throws: LedgerError.invalidInput) { try store.setReferenceFile("../bad.pdf", projectID: "jacket") }
        let file = UUID().uuidString + ".pdf"
        try store.setReferenceFile(file, projectID: "jacket")
        let pair = try Piece(id: "sleeve", requiredCount: 2, cutOnFold: true, material: .lining, mirrored: true)
        let unknown = try Piece(id: "collar", requiredCount: nil)
        let changed = try ProjectDefinition(pieces: [pair, unknown])
        try store.append(projectID: "jacket", events: [.init(id: "define", revision: 0, action: .reconcile(changed))])
        try store.append(projectID: "jacket", events: [.init(id: "cut", revision: 1, action: .cut(pieceID: "sleeve", physicalIndex: 1))])
        let reopened = try ProjectStore(path: path)
        #expect(try reopened.projects().first?.referenceFile == file)
        let progress = try reopened.load(id: "jacket")
        #expect(progress.completedCuts(pieceID: "sleeve") == [1])
        #expect(progress.summary.hasUnknownCounts)
        #expect(progress.pieceProgressList[0].remainingCount == 1)
        #expect(progress.pieceProgressList[1].remainingCount == nil)
        try reopened.append(projectID: "jacket", events: [.init(id: "undo", revision: 1, action: .undoCut(pieceID: "sleeve", physicalIndex: 1))])
        #expect(try ProjectStore(path: path).load(id: "jacket").completedCuts(pieceID: "sleeve").isEmpty)
        let encoded = try JSONEncoder().encode(pair)
        #expect(try JSONDecoder().decode(Piece.self, from: encoded) == pair)
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
        #expect(try before.read { try String.fetchAll($0, sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier") } == ["v1-projects", "v2-events", "v3-project-metadata"])
    }
}
