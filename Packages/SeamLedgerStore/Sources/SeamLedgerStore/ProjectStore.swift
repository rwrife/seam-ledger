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
        try migrator.migrate(database)
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
