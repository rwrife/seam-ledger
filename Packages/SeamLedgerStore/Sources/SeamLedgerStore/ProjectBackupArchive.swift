import Foundation
import Crypto
import SeamLedgerKit

/// A bounded, versioned JSON representation. Reference PDF bytes are supplied by the caller.
public struct ProjectBackupArchive: Codable, Equatable, Sendable {
    public static let currentVersion = 2
    public static let maximumArchiveBytes = 100_000_000
    public static let maximumReferenceBytes = 25_000_000

    public let formatVersion: Int
    public let projects: [ProjectStore.ProjectSnapshot]
    public let references: [ReferenceAttachment]

    private enum CodingKeys: String, CodingKey {
        case formatVersion
        case projects
        case references
        case referenceFiles
    }

    private init(projects: [ProjectStore.ProjectSnapshot], referenceFiles: [String: Data]) {
        formatVersion = Self.currentVersion
        self.projects = projects
        references = referenceFiles.map { filename, data in
            ReferenceAttachment(filename: filename, sha256: Self.digest(data), data: data)
        }.sorted { $0.filename < $1.filename }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        projects = try container.decode([ProjectStore.ProjectSnapshot].self, forKey: .projects)

        if container.contains(.references) {
            guard formatVersion == Self.currentVersion else { throw LedgerError.invalidInput }
            references = try container.decode([ReferenceAttachment].self, forKey: .references)
        } else {
            guard formatVersion == 1 else { throw LedgerError.invalidInput }
            let files = try container.decode([String: Data].self, forKey: .referenceFiles)
            references = files.map { filename, data in
                ReferenceAttachment(filename: filename, sha256: Self.digest(data), data: data)
            }.sorted { $0.filename < $1.filename }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encode(projects, forKey: .projects)
        if formatVersion == 1 {
            var files: [String: Data] = [:]
            for reference in references { files[reference.filename] = reference.data }
            try container.encode(files, forKey: .referenceFiles)
        } else {
            try container.encode(references, forKey: .references)
        }
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
        guard formatVersion == 1 || formatVersion == Self.currentVersion,
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

        guard Set(references.map(\.filename)).count == references.count,
              Set(references.map(\.filename)) == referencedFiles else { throw LedgerError.invalidInput }
        for attachment in references {
            guard Self.isValidReferenceFilename(attachment.filename),
                  !attachment.data.isEmpty, attachment.data.count <= Self.maximumReferenceBytes,
                  attachment.data.starts(with: Data("%PDF-".utf8)),
                  attachment.sha256 == Self.digest(attachment.data) else { throw LedgerError.invalidInput }
        }
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func isValidReferenceFilename(_ filename: String) -> Bool {
        guard filename.hasSuffix(".pdf") else { return false }
        let stem = String(filename.dropLast(4))
        guard let uuid = UUID(uuidString: stem) else { return false }
        return uuid.uuidString == stem
    }

    public struct ReferenceAttachment: Codable, Equatable, Sendable {
        public let filename: String
        public let sha256: String
        public let data: Data

        fileprivate init(filename: String, sha256: String, data: Data) {
            self.filename = filename
            self.sha256 = sha256
            self.data = data
        }
    }
}
