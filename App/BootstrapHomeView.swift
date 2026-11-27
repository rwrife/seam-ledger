import Foundation
import PDFKit
import SeamLedgerKit
import SeamLedgerStore
import SwiftUI
import UniformTypeIdentifiers

// ponytail: One local workspace; project sharing and multiwindow edits need a separate sync design.
struct BootstrapHomeView: View {
    @State private var store: ProjectStore?
    @State private var projects: [ProjectStore.ProjectInfo] = []
    @State private var selectedID: String?
    @State private var project: SewingProject?
    @State private var name = ""
    @FocusState private var projectNameFocused: Bool
    @State private var pieceName = ""
    @State private var requiredCount = ""
    @State private var material: PieceMaterial = .outer
    @State private var mirrored = false
    @State private var fold = false
    @State private var importing = false
    @State private var showingReference = false
    @State private var showingSewing = false
    @State private var showingBackupManager = false
    @State private var reportDocument: ProjectPDFReportDocument?
    @State private var exportingReport = false
    @State private var showingReportPreview = false
    @State private var reportPreviewMessage = ""
    @State private var didInjectRestoreFailure = false
    @State private var reportTestMessage: String?
    @FocusState private var pieceNameFocused: Bool
    @State private var error: String?
    @State private var pendingDefinition: ProjectDefinition?

    private var referenceDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "SeamLedger/References", directoryHint: .isDirectory)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let error {
                        Text(error).foregroundStyle(.red).accessibilityIdentifier("workspace.error")
                    }
                    if let project, let selectedID {
                        projectPanel(project, id: selectedID)
                    } else {
                        projectList
                    }
                }
                .padding(20)
            }
            .navigationTitle("Seam Ledger")
            .toolbar {
                if selectedID != nil {
                    Button("Projects") { selectedID = nil; project = nil }
                        .accessibilityIdentifier("workspace.projects")
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf]) { result in
                importReference(result)
            }
            .confirmationDialog("Replace piece definitions? All old cut and seam progress will reset; history stays available.",
                                isPresented: Binding(get: { pendingDefinition != nil }, set: { if !$0 { pendingDefinition = nil } }),
                                titleVisibility: .visible) {
                Button("Reset progress and change pieces", role: .destructive) {
                    if let definition = pendingDefinition {
                        perform { try append(.reconcile(definition)) }
                    }
                    pendingDefinition = nil
                }
                Button("Keep existing pieces", role: .cancel) { pendingDefinition = nil }
            }
        }
        .onAppear(perform: openStore)
        .fileExporter(isPresented: $exportingReport, document: reportDocument,
                      contentType: .pdf, defaultFilename: "seam-ledger-report") { result in
            switch result {
            case .success: error = nil
            case let .failure(exportError): error = "PDF report export failed: \(exportError.localizedDescription)"
            }
        }
        .confirmationDialog("PDF report preview", isPresented: $showingReportPreview,
                            titleVisibility: .visible) {
            Button("Export PDF report") { exportingReport = true }
                .accessibilityIdentifier("report.export.confirm")
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(reportPreviewMessage)
        }
    }

    private var projectList: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Offline cutting table").font(.title2.bold())
            ForEach(projects) { info in
                Button(info.name) { load(info.id) }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("project.\(info.id)")
            }
            TextField("Project name", text: $name)
                .textContentType(.none)
                .focused($projectNameFocused)
                .submitLabel(.done)
                .accessibilityIdentifier("project.name")
            Button("Create project") {
                projectNameFocused = false
                perform {
                    guard let store else { throw LedgerError.invalidInput }
                    let id = UUID().uuidString
                    try store.create(id: id, name: name, definition: try ProjectDefinition(pieces: []))
                    name = ""
                    refreshProjects()
                    load(id)
                }
            }
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("project.create")
        }
    }

    private func projectPanel(_ current: SewingProject, id: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            let info = projects.first(where: { $0.id == id })
            let hasReferencePDF = info?.referenceFile.map {
                FileManager.default.fileExists(atPath: referenceDirectory.appending(path: $0).path)
            } ?? false
            Text(info?.name ?? "Project").font(.title2.bold())
            Button("Backup, restore, or delete local data") { showingBackupManager = true }
                .frame(minHeight: 44)
                .accessibilityIdentifier("backup.open")
                .sheet(isPresented: $showingBackupManager) {
                    NavigationStack {
                        BackupManagerView(makeBackup: makeBackup,
                                          restore: restoreBackup,
                                          deleteAll: deleteAllOwnedData)
                    }
                }
            Button("Preview project report (PDF)") {
                prepareReportPreview(project: current, name: info?.name ?? "Project",
                                     hasReferencePDF: hasReferencePDF)
            }
            .frame(minHeight: 44)
            .accessibilityIdentifier("report.exportPDF")
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-UITestReport") {
                Button("Validate local PDF report") {
                    validateReport(project: current, name: info?.name ?? "Project",
                                   hasReferencePDF: hasReferencePDF)
                }
                .accessibilityIdentifier("report.test")
                Button("Add backup test photo") { addBackupUITestPhoto() }
                    .accessibilityIdentifier("backup.test.addPhoto")
                if let reportTestMessage {
                    Text(reportTestMessage).accessibilityIdentifier("report.test.message")
                }
            }
#endif
            Button("Seams and alterations") { showingSewing = true }
                .frame(minHeight: 44)
                .accessibilityIdentifier("workspace.sewing")
                .sheet(isPresented: $showingSewing) {
                    SewingRecordView(project: $project, append: append)
                }
            Button("Import owned PDF") {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-UITestPDF") {
                    let url = FileManager.default.temporaryDirectory.appending(path: "seam-ledger-fixture.pdf")
                    let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 200, height: 200))
                    do {
                        try renderer.pdfData { context in
                            context.beginPage()
                            "Owned reference".draw(at: CGPoint(x: 20, y: 20), withAttributes: nil)
                        }.write(to: url, options: .atomic)
                        importReference(.success(url))
                    } catch { self.error = error.localizedDescription }
                } else {
                    importing = true
                }
                #else
                importing = true
                #endif
            }
                .frame(minHeight: 44)
                .accessibilityIdentifier("reference.import")
            let summary = current.summary
            Text("\(summary.completedPieces) of \(summary.totalPieces) pieces complete\(summary.hasUnknownCounts ? "; some counts unknown" : "")")
                .accessibilityIdentifier("cut.summary")
            ForEach(current.pieceProgressList, id: \.piece.id) { item in
                VStack(alignment: .leading, spacing: 8) {
                    let piece = item.piece
                    Text("\(piece.id) · \(piece.material.rawValue)\(piece.mirrored ? " · mirrored pair" : "")\(piece.cutOnFold ? " · cut on fold" : "")")
                        .font(.headline)
                    if let required = piece.requiredCount {
                        Text("\(item.cutCount) cut of \(required); \(item.remainingCount ?? 0) remaining")
                        ForEach(1...required, id: \.self) { index in
                            let cut = current.completedCuts(pieceID: piece.id).contains(index)
                            Button("\(cut ? "Undo cut" : "Cut") \(piece.id) \(index)") {
                                perform { try append(cut ? .undoCut(pieceID: piece.id, physicalIndex: index)
                                                         : .cut(pieceID: piece.id, physicalIndex: index)) }
                            }
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("cut.\(piece.id).\(index)")
                        }
                    } else {
                        Text("Physical cut count unknown; set count before checking cuts")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            Text(current.definition.pieces.isEmpty ? "Add first piece" : "Change pieces (resets progress after confirmation)")
                .font(.headline)
            TextField("Named piece", text: $pieceName)
                .focused($pieceNameFocused)
                .submitLabel(.done)
                .accessibilityIdentifier("piece.name")
            Picker("Material", selection: $material) {
                Text("Outer").tag(PieceMaterial.outer)
                Text("Lining").tag(PieceMaterial.lining)
            }
            Toggle("Mirrored pair (two physical cuts)", isOn: $mirrored)
                .accessibilityIdentifier("piece.mirrored")
            Toggle("Cut on fold (instruction only)", isOn: $fold)
                .accessibilityIdentifier("piece.fold")
            if !mirrored {
                TextField("Physical cut count (blank means unknown)", text: $requiredCount)
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier("piece.count")
            }
            Button(current.definition.pieces.isEmpty ? "Add piece" : "Review definition change") {
                perform {
                    let count = mirrored ? 2 : (requiredCount.isEmpty ? nil : Int(requiredCount))
                    guard mirrored || requiredCount.isEmpty || count.map({ (1...1_000).contains($0) }) == true else {
                        throw LedgerError.invalidInput
                    }
                    let piece = try Piece(id: pieceName, requiredCount: count,
                                          cutOnFold: fold, material: material, mirrored: mirrored)
                    let definition = try ProjectDefinition(pieces: current.definition.pieces + [piece],
                                                           edges: current.definition.edges,
                                                           seams: current.definition.seams)
                    if current.definition.pieces.isEmpty {
                        try append(.reconcile(definition))
                    } else {
                        pendingDefinition = definition
                    }
                    pieceName = ""; requiredCount = ""
                }
            }
            .disabled(pieceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("piece.add")
            if let file = info?.referenceFile {
                let url = referenceDirectory.appending(path: file)
                if FileManager.default.fileExists(atPath: url.path) {
                    Button("Open owned reference PDF") { pieceNameFocused = false; showingReference = true }
                        .accessibilityIdentifier("reference.open")
                        .sheet(isPresented: $showingReference) {
                            NavigationStack {
                                PDFKitView(url: url)
                                    .accessibilityIdentifier("reference.document")
                                    .navigationTitle("Owned reference")
                                    .toolbar { Button("Done") { showingReference = false } }
                            }
                        }
                } else {
                    Text("Reference PDF missing").foregroundStyle(.red)
                }
            }
        }
    }

    private func openStore() {
        perform {
            try FileManager.default.createDirectory(at: referenceDirectory, withIntermediateDirectories: true)
            store = try ProjectStore(path: URL.applicationSupportDirectory.appending(path: "SeamLedger/projects.sqlite").path)
            refreshProjects()
        }
    }
    private func refreshProjects() { perform { projects = try store?.projects() ?? [] } }
    private func load(_ id: String) {
        perform {
            project = try store?.load(id: id)
            selectedID = id
            refreshProjects()
        }
    }
    private func append(_ action: SewingAction) throws {
        guard let store, let selectedID, let project else { throw LedgerError.invalidInput }
        try store.append(projectID: selectedID,
                         events: [SewingEvent(id: UUID().uuidString, revision: project.revision, action: action)])
        self.project = try store.load(id: selectedID)
    }
    private func makeBackup() throws -> Data {
        guard let store else { throw LedgerError.invalidInput }
        let snapshots = try store.snapshot()
        var references: [String: Data] = [:]
        for snapshot in snapshots {
            guard let filename = snapshot.referenceFile else { continue }
            let url = referenceDirectory.appending(path: filename)
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true, let size = values.fileSize,
                  size > 0, size <= ProjectBackupArchive.maximumReferenceBytes else { throw LedgerError.invalidInput }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: ProjectBackupArchive.maximumReferenceBytes + 1) ?? Data()
            guard data.count == size, let pdf = PDFDocument(data: data), pdf.pageCount > 0 else {
                throw LedgerError.invalidInput
            }
            references[filename] = data
        }
        return try ProjectBackupArchive.encode(projects: snapshots, referenceFiles: references)
    }
    private func prepareReportPreview(project: SewingProject, name: String, hasReferencePDF: Bool) {
        do {
            let data = try ProjectPDFReport.make(projectName: name, project: project,
                                                 hasReferencePDF: hasReferencePDF)
            guard let document = PDFDocument(data: data), document.pageCount > 0 else {
                throw LedgerError.invalidInput
            }
            reportDocument = ProjectPDFReportDocument(data: data)
            reportPreviewMessage = "\(name): \(project.pieceProgressList.count) cut-list item(s), \(project.definition.seams.count) seam(s), and \(project.alterations.count) alteration note(s). Photos and reference PDF contents are excluded."
            showingReportPreview = true
            error = nil
        } catch { self.error = "PDF report could not be created: \(error.localizedDescription)" }
    }
#if DEBUG
    private func validateReport(project: SewingProject, name: String, hasReferencePDF: Bool) {
        do {
            var fixture = project
            let photo = Data("PRIVATE-PHOTO-SECRET".utf8)
            let note = try AlterationNote(id: "report-fixture", text: "Report test alteration", photo: photo)
            try fixture.apply(SewingEvent(id: UUID().uuidString, revision: fixture.revision,
                                          action: .addAlteration(note)))
            let data = try ProjectPDFReport.make(projectName: name, project: fixture,
                                                 hasReferencePDF: hasReferencePDF)
            guard let document = PDFDocument(data: data), document.pageCount > 0,
                  let text = document.string, text.contains("Report test alteration"),
                  text.contains("Alteration photos are excluded"), !text.contains("PRIVATE-PHOTO-SECRET") else {
                throw LedgerError.invalidInput
            }
            reportTestMessage = "PDF report generated; photo data is excluded."
        } catch { reportTestMessage = "PDF report validation failed: \(error.localizedDescription)" }
    }

    private func addBackupUITestPhoto() {
        do {
            let note = try AlterationNote(id: UUID().uuidString, text: "Backup-only photo entry",
                                          photo: Data([1, 2, 3]))
            try append(.addAlteration(note))
        } catch let captureError { self.error = captureError.localizedDescription }
    }
#endif
    private func restoreBackup(_ archive: ProjectBackupArchive) throws -> String? {
        guard let store else { throw LedgerError.invalidInput }
        let manager = FileManager.default
        let parent = referenceDirectory.deletingLastPathComponent()
        try manager.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appending(path: "References-restore-\(UUID().uuidString)", directoryHint: .isDirectory)
        let previous = parent.appending(path: "References-previous-\(UUID().uuidString)", directoryHint: .isDirectory)
        try manager.createDirectory(at: staging, withIntermediateDirectories: false)
        do {
            for attachment in archive.references {
                guard let pdf = PDFDocument(data: attachment.data), pdf.pageCount > 0 else { throw LedgerError.invalidInput }
                try attachment.data.write(to: staging.appending(path: attachment.filename), options: .atomic)
            }
            let hadReferences = manager.fileExists(atPath: referenceDirectory.path)
            if hadReferences { try manager.moveItem(at: referenceDirectory, to: previous) }
            do {
                try manager.moveItem(at: staging, to: referenceDirectory)
            } catch {
                if hadReferences {
                    do { try manager.moveItem(at: previous, to: referenceDirectory) }
                    catch let rollbackError {
                        throw BackupRollbackError(operation: error.localizedDescription,
                                                  rollback: rollbackError.localizedDescription)
                    }
                }
                throw error
            }
            do {
#if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-UITestRestoreFailure"), !didInjectRestoreFailure {
                    didInjectRestoreFailure = true
                    throw LedgerError.invalidInput
                }
#endif
                try store.replaceAll(with: archive.projects)
            } catch {
                do {
                    try manager.removeItem(at: referenceDirectory)
                    if hadReferences { try manager.moveItem(at: previous, to: referenceDirectory) }
                } catch let rollbackError {
                    throw BackupRollbackError(operation: error.localizedDescription,
                                              rollback: rollbackError.localizedDescription)
                }
                throw error
            }
            selectedID = nil
            project = nil
            var warnings: [String] = []
            do { projects = try store.projects() }
            catch {
                projects = []
                warnings.append("The project list could not be refreshed: \(error.localizedDescription)")
            }
            if hadReferences {
                do { try manager.removeItem(at: previous) }
                catch {
                    warnings.append("Previous attachments remain in app storage because cleanup failed: \(error.localizedDescription)")
                }
            }
            return warnings.isEmpty ? nil : "Restore completed. " + warnings.joined(separator: " ")
        } catch {
            if manager.fileExists(atPath: staging.path) { try manager.removeItem(at: staging) }
            throw error
        }
    }
    private func deleteAllOwnedData() throws -> String? {
        guard let store else { throw LedgerError.invalidInput }
        let manager = FileManager.default
        let previous = referenceDirectory.deletingLastPathComponent()
            .appending(path: "References-deleted-\(UUID().uuidString)", directoryHint: .isDirectory)
        let hadReferences = manager.fileExists(atPath: referenceDirectory.path)
        if hadReferences { try manager.moveItem(at: referenceDirectory, to: previous) }
        do {
            try store.deleteAll()
        } catch {
            if hadReferences {
                do { try manager.moveItem(at: previous, to: referenceDirectory) }
                catch let rollbackError {
                    throw BackupRollbackError(operation: error.localizedDescription,
                                              rollback: rollbackError.localizedDescription)
                }
            }
            throw error
        }
        projects = []
        selectedID = nil
        project = nil
        if hadReferences {
            do { try manager.removeItem(at: previous) }
            catch {
                return "Local projects were deleted. Some owned attachments remain in app storage because cleanup failed: \(error.localizedDescription). Files already exported remain outside the app."
            }
        }
        return "All local projects and attachments were deleted. Files you already exported remain outside the app."
    }
    private func perform(_ work: () throws -> Void) {
        do { try work(); error = nil } catch { self.error = error.localizedDescription }
    }

    private struct BackupRollbackError: LocalizedError {
        let operation: String
        let rollback: String
        var errorDescription: String? {
            "Restore failed (\(operation)); restoring previous attachments also failed (\(rollback)). The previous files remain in local storage."
        }
    }
    private func importReference(_ result: Result<URL, Error>) {
        perform {
            guard let store, let selectedID else { throw LedgerError.invalidInput }
            let source = try result.get()
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            let values = try source.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true,
                  let size = values.fileSize, size > 0, size <= 25_000_000 else { throw LedgerError.invalidInput }
            let handle = try FileHandle(forReadingFrom: source)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: 25_000_001) ?? Data()
            guard !data.isEmpty, data.count <= 25_000_000, data.starts(with: Data("%PDF-".utf8)),
                  let document = PDFDocument(data: data), document.pageCount > 0 else { throw LedgerError.invalidInput }
            let filename = UUID().uuidString + ".pdf"
            let target = referenceDirectory.appending(path: filename)
            try data.write(to: target, options: .atomic)
            do { try store.setReferenceFile(filename, projectID: selectedID) }
            catch { try? FileManager.default.removeItem(at: target); throw error }
            refreshProjects()
        }
    }
}

private struct PDFKitView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(url: url)
        return view
    }
    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document?.documentURL != url { uiView.document = PDFDocument(url: url) }
    }
}
