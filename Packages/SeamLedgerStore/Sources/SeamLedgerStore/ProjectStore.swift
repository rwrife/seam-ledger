import Foundation
import GRDB
import SeamLedgerKit

/// One SQLite queue per store. No singleton, network, or implicit definition updates.
public final class ProjectStore: Sendable {
    private let database: DatabaseQueue

    public init(path: String) throws {
        database = try DatabaseQueue(path: path)
        var migrator = DatabaseMigrator()
        // v1 is the original on-disk project format, represented by a real test fixture.
        migrator.registerMigration("v1-projects") { db in
            try db.execute(sql: "CREATE TABLE projects (id TEXT PRIMARY KEY NOT NULL, definition BLOB NOT NULL)")
        }
        migrator.registerMigration("v2-events") { db in
            try db.execute(sql: """
                CREATE TABLE events (
                    sequence INTEGER PRIMARY KEY AUTOINCREMENT,
                    projectID TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
                    eventID TEXT NOT NULL,
                    payload BLOB NOT NULL,
                    UNIQUE(projectID, eventID)
                )
                """)
        }
        migrator.registerMigration("v3-project-metadata") { db in
            try db.execute(sql: "ALTER TABLE projects ADD COLUMN name TEXT NOT NULL DEFAULT 'Untitled'")
            try db.execute(sql: "ALTER TABLE projects ADD COLUMN referenceFile TEXT")
        }
        try migrator.migrate(database)
    }

    public struct ProjectInfo: Equatable, Sendable, Identifiable {
        public let id: String
        public let name: String
        public let referenceFile: String?
    }

    public func projects() throws -> [ProjectInfo] {
        try database.read { db in
            try Row.fetchAll(db, sql: "SELECT id, name, referenceFile FROM projects ORDER BY name, id")
                .map { ProjectInfo(id: $0["id"], name: $0["name"], referenceFile: $0["referenceFile"]) }
        }
    }

    public func setReferenceFile(_ filename: String, projectID: String) throws {
        guard filename.hasSuffix(".pdf"),
              UUID(uuidString: String(filename.dropLast(4))) != nil else { throw LedgerError.invalidInput }
        try database.write { db in
            try db.execute(sql: "UPDATE projects SET referenceFile = ? WHERE id = ?", arguments: [filename, projectID])
            guard db.changesCount == 1 else { throw LedgerError.invalidInput }
        }
    }

    public func create(id: String, name: String, definition: ProjectDefinition) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LedgerError.invalidInput }
        guard !id.isEmpty else { throw LedgerError.invalidInput }
        try definition.validate()
        let data = try JSONEncoder().encode(definition)
        try database.write { db in
            try db.execute(sql: "INSERT INTO projects (id, definition, name) VALUES (?, ?, ?)", arguments: [id, data, name])
        }
    }

    public func create(id: String, definition: ProjectDefinition) throws {
        guard !id.isEmpty else { throw LedgerError.invalidInput }
        try definition.validate()
        let data = try JSONEncoder().encode(definition)
        try database.write { db in
            try db.execute(sql: "INSERT INTO projects (id, definition) VALUES (?, ?)", arguments: [id, data])
        }
    }

    private static func load(_ id: String, from db: Database) throws -> SewingProject {
        guard let data = try Data.fetchOne(db, sql: "SELECT definition FROM projects WHERE id = ?", arguments: [id]) else {
            throw LedgerError.invalidInput
        }
        var project = try SewingProject(definition: JSONDecoder().decode(ProjectDefinition.self, from: data))
        for payload in try Data.fetchAll(db, sql: "SELECT payload FROM events WHERE projectID = ? ORDER BY sequence", arguments: [id]) {
            try project.apply(JSONDecoder().decode(SewingEvent.self, from: payload))
        }
        return project
    }

    public func load(id: String) throws -> SewingProject {
        try database.read { try Self.load(id, from: $0) }
    }

    /// Every batch is atomic, including reducer validation and event insertion.
    /// A later invalid event rolls back earlier inserts in the same batch.
    public func append(projectID: String, events: [SewingEvent]) throws {
        try database.write { db in
            var project = try Self.load(projectID, from: db)
            for event in events {
                try project.apply(event)
                try db.execute(sql: "INSERT INTO events (projectID, eventID, payload) VALUES (?, ?, ?)",
                               arguments: [projectID, event.id, try JSONEncoder().encode(event)])
            }
        }
    }
}
