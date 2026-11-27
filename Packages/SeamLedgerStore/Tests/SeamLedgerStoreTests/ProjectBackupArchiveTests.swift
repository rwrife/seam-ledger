import Foundation
import Testing
import SeamLedgerKit
@testable import SeamLedgerStore

@Suite struct ProjectBackupArchiveTests {
    @Test func roundTripsVersionedProjectsReferencePDFAndPhotoHistory() throws {
        let definition = try ProjectDefinition(pieces: [Piece(id: "panel", requiredCount: 1)])
        var project = try SewingProject(definition: definition)
        let note = try AlterationNote(id: "note", text: "Hem", photo: Data([1, 2, 3]))
        let events = [SewingEvent(id: "note-event", revision: 0, action: .addAlteration(note))]
        try project.apply(events[0])
        let filename = UUID().uuidString + ".pdf"
        let snapshot = ProjectStore.ProjectSnapshot(id: "project", name: "Jacket", referenceFile: filename,
                                                    definition: definition, events: events)
        let pdf = Data("%PDF-1.7".utf8)

        let encoded = try ProjectBackupArchive.encode(projects: [snapshot], referenceFiles: [filename: pdf])
        let decoded = try ProjectBackupArchive.decode(encoded)

        #expect(decoded.formatVersion == ProjectBackupArchive.currentVersion)
        #expect(decoded.projects == [snapshot])
        #expect(decoded.references.map(\.filename) == [filename])
        #expect(decoded.references.first?.data == pdf)
        #expect(decoded.references.first?.sha256 == "86edbaa24831badfa0a8b04bb410141e2ee4182b6d0014493fe262a7a331c20b")
    }

    @Test func rejectsUnknownVersionsAndMissingOrUnsafeReferences() throws {
        let archive = try ProjectBackupArchive.encode(projects: [], referenceFiles: [:])
        var object = try #require(JSONSerialization.jsonObject(with: archive) as? [String: Any])
        object["formatVersion"] = 99
        let unknownVersion = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: LedgerError.invalidInput) { try ProjectBackupArchive.decode(unknownVersion) }

        let definition = try ProjectDefinition(pieces: [])
        let filename = UUID().uuidString + ".pdf"
        let snapshot = ProjectStore.ProjectSnapshot(id: "project", name: "Jacket", referenceFile: filename,
                                                    definition: definition, events: [])
        #expect(throws: LedgerError.invalidInput) {
            try ProjectBackupArchive.encode(projects: [snapshot], referenceFiles: [:])
        }
        #expect(throws: LedgerError.invalidInput) {
            try ProjectBackupArchive.encode(projects: [snapshot], referenceFiles: ["../escape.pdf": Data("%PDF-".utf8)])
        }
    }

    @Test func rejectsInvalidPDFContentAndOversizedArchives() throws {
        let definition = try ProjectDefinition(pieces: [])
        let filename = UUID().uuidString + ".pdf"
        let snapshot = ProjectStore.ProjectSnapshot(id: "project", name: "Jacket", referenceFile: filename,
                                                    definition: definition, events: [])
        #expect(throws: LedgerError.invalidInput) {
            try ProjectBackupArchive.encode(projects: [snapshot], referenceFiles: [filename: Data("not a PDF".utf8)])
        }
        #expect(throws: LedgerError.invalidInput) {
            try ProjectBackupArchive.decode(Data(repeating: 0, count: ProjectBackupArchive.maximumArchiveBytes + 1))
        }
    }

    @Test func rejectsTamperedAttachmentDigest() throws {
        let definition = try ProjectDefinition(pieces: [])
        let filename = UUID().uuidString + ".pdf"
        let snapshot = ProjectStore.ProjectSnapshot(id: "project", name: "Jacket", referenceFile: filename,
                                                    definition: definition, events: [])
        let encoded = try ProjectBackupArchive.encode(projects: [snapshot],
                                                      referenceFiles: [filename: Data("%PDF-1.7".utf8)])
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var attachments = try #require(object["references"] as? [[String: Any]])
        attachments[0]["sha256"] = String(repeating: "0", count: 64)
        object["references"] = attachments
        let tampered = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: LedgerError.invalidInput) { try ProjectBackupArchive.decode(tampered) }
    }

    @Test func decodesVersionOneArchives() throws {
        let definition = try ProjectDefinition(pieces: [])
        let filename = UUID().uuidString + ".pdf"
        let snapshot = ProjectStore.ProjectSnapshot(id: "project", name: "Jacket", referenceFile: filename,
                                                    definition: definition, events: [])
        let current = try ProjectBackupArchive.encode(projects: [snapshot],
                                                      referenceFiles: [filename: Data("%PDF-1.7".utf8)])
        let object = try #require(JSONSerialization.jsonObject(with: current) as? [String: Any])
        let attachments = try #require(object["references"] as? [[String: Any]])
        let legacy = ["formatVersion": 1,
                      "projects": try #require(object["projects"]),
                      "referenceFiles": [filename: try #require(attachments[0]["data"])]] as [String: Any]
        let legacyData = try JSONSerialization.data(withJSONObject: legacy)

        let decoded = try ProjectBackupArchive.decode(legacyData)
        #expect(decoded.formatVersion == 1)
        #expect(decoded.references.first?.data == Data("%PDF-1.7".utf8))
        #expect(decoded.references.first?.sha256 == "86edbaa24831badfa0a8b04bb410141e2ee4182b6d0014493fe262a7a331c20b")
        #expect(try ProjectBackupArchive.decode(JSONEncoder().encode(decoded)) == decoded)
    }
}
