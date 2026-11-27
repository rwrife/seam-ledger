import Foundation
import SeamLedgerKit

/// A bounded, versioned JSON representation. Reference PDF bytes are supplied by the caller.
public struct ProjectBackupArchive: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public static let maximumArchiveBytes = 100_000_000
    public static let maximumReferenceBytes = 25_000_000

    public let formatVersion: Int
    public let projects: [ProjectStore.ProjectSnapshot]
    public let referenceFiles: [String: Data]

    private init(projects: [ProjectStore.ProjectSnapshot], referenceFiles: [String: Data]) {
        formatVersion = Self.currentVersion
        self.projects = projects
        self.referenceFiles = referenceFiles
    }

    public static func encode(projects: [ProjectStore.ProjectSnapshot],
                              referenceFiles: [String: Data]) throws -> Data {
        let archive = Self(projects: projects, referenceFiles: referenceFiles)
        try archive.validate()
        let data = try JSONEncoder().encode(archive)
        guard !data.isEmpty, data.count <= maximumArchiveBytes else { throw LedgerError.invalidInput }
        return data
    }

    public static func decode(_ data: Data) throws -> Self {
        guard !data.isEmpty, data.count <= maximumArchiveBytes else { throw LedgerError.invalidInput }
        let archive = try JSONDecoder().decode(Self.self, from: data)
        try archive.validate()
        return archive
    }

    private func validate() throws {
        guard formatVersion == Self.currentVersion,
              Set(projects.map(\.id)).count == projects.count else { throw LedgerError.invalidInput }

        var referencedFiles = Set<String>()
        for project in projects {
            guard !project.id.isEmpty,
                  !project.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LedgerError.invalidInput
            }
            try project.definition.validate()
            var replay = try SewingProject(definition: project.definition)
            for event in project.events { try replay.apply(event) }
            if let filename = project.referenceFile {
                guard Self.isValidReferenceFilename(filename), referencedFiles.insert(filename).inserted else {
                    throw LedgerError.invalidInput
                }
            }
        }

        guard Set(referenceFiles.keys) == referencedFiles else { throw LedgerError.invalidInput }
        for (filename, data) in referenceFiles {
            guard Self.isValidReferenceFilename(filename),
                  !data.isEmpty, data.count <= Self.maximumReferenceBytes,
                  data.starts(with: Data("%PDF-".utf8)) else { throw LedgerError.invalidInput }
        }
    }

    private static func isValidReferenceFilename(_ filename: String) -> Bool {
        guard filename.hasSuffix(".pdf") else { return false }
        let stem = String(filename.dropLast(4))
        guard let uuid = UUID(uuidString: stem) else { return false }
        return uuid.uuidString == stem
    }
}
