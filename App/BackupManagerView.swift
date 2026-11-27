import Foundation
import PDFKit
import SeamLedgerKit
import SeamLedgerStore
import SwiftUI
import UniformTypeIdentifiers

struct BackupManagerView: View {
    @Environment(\.dismiss) private var dismiss
    let makeBackup: () throws -> Data
    let restore: (ProjectBackupArchive) throws -> String?
    let deleteAll: () throws -> String?

    @State private var document: BackupArchiveDocument?
    @State private var importing = false
    @State private var exporting = false
    @State private var showingReplaceConfirmation = false
    @State private var showingDeleteConfirmation = false
    @State private var archive: ProjectBackupArchive?
    @State private var message: String?

    var body: some View {
        Group {
            if let archive {
                restorePreview(archive)
            } else {
                options
            }
        }
        .padding(24)
        .navigationTitle(archive == nil ? "Backup and restore" : "Restore preview")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .fileExporter(isPresented: $exporting, document: document,
                      contentType: .json, defaultFilename: "seam-ledger-backup") { result in
            switch result {
            case .success: message = "Backup saved. It contains private project history, photos and PDFs."
            case let .failure(error): message = "Backup export failed: \(error.localizedDescription)"
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            importArchive(result)
        }
        .confirmationDialog("Replace every local project and attachment with this backup?",
                            isPresented: $showingReplaceConfirmation, titleVisibility: .visible) {
            Button("Replace all local data", role: .destructive) { commitRestore() }
                .accessibilityIdentifier("backup.restore.confirm")
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The current local projects and attachments will be replaced. Keep a separate backup if you may need them.")
        }
        .confirmationDialog("Delete all local projects and attachments?",
                            isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete all local data", role: .destructive) { commitDelete() }
                .accessibilityIdentifier("backup.delete.confirm")
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Files you already exported remain outside the app and are not deleted.")
        }
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("A full backup contains project history, alteration photos and owned reference PDFs.")
            Text("The exported file contains private measurements and photos. Store and share it carefully.")
            Button("Export full backup (JSON)") { beginExport() }
                .frame(minHeight: 44)
                .accessibilityIdentifier("backup.export")
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-UITestBackup") {
                Button("Save local backup test fixture") { saveUITestBackup() }
                    .accessibilityIdentifier("backup.test.save")
                Button("Load local backup test fixture") { loadUITestBackup() }
                    .accessibilityIdentifier("backup.test.load")
            }
#endif
            Button("Preview backup to restore") { importing = true }
                .frame(minHeight: 44)
                .accessibilityIdentifier("backup.import")
            Divider()
            Button("Delete all local data", role: .destructive) { showingDeleteConfirmation = true }
                .frame(minHeight: 44)
                .accessibilityIdentifier("backup.deleteAll")
            Text("Delete-all removes this app's local projects and owned reference PDFs. Previously exported files remain outside the app.")
                .font(.footnote)
            if let message { Text(message).accessibilityIdentifier("backup.message") }
            Spacer()
        }
    }

    private func restorePreview(_ archive: ProjectBackupArchive) -> some View {
        let photoCount = archive.projects.reduce(into: 0) { count, project in
            for event in project.events {
                if case let .addAlteration(note) = event.action, note.photo != nil { count += 1 }
            }
        }
        return VStack(alignment: .leading, spacing: 16) {
            Text("This file contains \(archive.projects.count) project(s), \(archive.references.count) reference PDF(s), and \(photoCount) alteration photo(s).")
                .accessibilityIdentifier("backup.preview.summary")
            ForEach(archive.projects, id: \.id) { project in
                Text("\(project.name) (\(project.events.count) history entries)")
            }
            Text("The backup passed format, size, event-history and PDF checks. Restore replaces all local project data.")
            Button("Replace all local data", role: .destructive) { showingReplaceConfirmation = true }
                .frame(minHeight: 44)
                .accessibilityIdentifier("backup.restore")
            Button("Choose another file") { self.archive = nil; importing = true }
                .frame(minHeight: 44)
            if let message { Text(message).accessibilityIdentifier("backup.message") }
            Spacer()
        }
    }

    private func beginExport() {
        do {
            document = BackupArchiveDocument(data: try makeBackup())
            exporting = true
            message = nil
        } catch { message = "Backup could not be created: \(error.localizedDescription)" }
    }

#if DEBUG
    private var uiTestBackupURL: URL {
        FileManager.default.temporaryDirectory.appending(path: "seam-ledger-uitest-backup.json")
    }

    private func saveUITestBackup() {
        do {
            try makeBackup().write(to: uiTestBackupURL, options: .atomic)
            message = "Local backup test fixture saved."
        } catch { message = "Test backup failed: \(error.localizedDescription)" }
    }

    private func loadUITestBackup() {
        do {
            let data = try Data(contentsOf: uiTestBackupURL)
            archive = try ProjectBackupArchive.decode(data)
            try FileManager.default.removeItem(at: uiTestBackupURL)
            message = nil
        } catch { message = "Test backup could not be loaded: \(error.localizedDescription)" }
    }
#endif

    private func importArchive(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true, let size = values.fileSize,
                  size > 0, size <= ProjectBackupArchive.maximumArchiveBytes else { throw LedgerError.invalidInput }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: ProjectBackupArchive.maximumArchiveBytes + 1) ?? Data()
            guard data.count == size else { throw LedgerError.invalidInput }
            let decoded = try ProjectBackupArchive.decode(data)
            for reference in decoded.references {
                guard let pdf = PDFDocument(data: reference.data), pdf.pageCount > 0 else { throw LedgerError.invalidInput }
            }
            archive = decoded
            message = nil
        } catch { message = "Backup could not be previewed: \(error.localizedDescription)" }
    }

    private func commitRestore() {
        guard let archive else { return }
        do {
            message = try restore(archive) ?? "Restore completed."
            self.archive = nil
        } catch { message = "Restore did not complete: \(error.localizedDescription)" }
    }

    private func commitDelete() {
        do { message = try deleteAll() ?? "All local data was deleted. Previously exported files remain outside the app." }
        catch { message = "Delete-all did not complete: \(error.localizedDescription)" }
    }
}
