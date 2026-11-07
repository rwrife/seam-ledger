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
            Text(info?.name ?? "Project").font(.title2.bold())
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
    private func perform(_ work: () throws -> Void) {
        do { try work(); error = nil } catch { self.error = error.localizedDescription }
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
