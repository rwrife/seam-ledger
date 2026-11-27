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
        let pdf = Data("%PDF-1.7\nminimal fixture".utf8)

        let encoded = try ProjectBackupArchive.encode(projects: [snapshot], referenceFiles: [filename: pdf])
        let decoded = try ProjectBackupArchive.decode(encoded)

        #expect(decoded.formatVersion == ProjectBackupArchive.currentVersion)
        #expect(decoded.projects == [snapshot])
        #expect(decoded.referenceFiles == [filename: pdf])
    }

    @Test func rejectsUnknownVersionsAndMissingOrUnsafeReferences() throws {
        let archive = try ProjectBackupArchive.encode(projects: [], referenceFiles: [:])
        let unknownVersion = Data(String(decoding: archive, as: UTF8.self)
            .replacingOccurrences(of: "\"formatVersion\":1", with: "\"formatVersion\":2").utf8)
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
}
