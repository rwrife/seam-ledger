import PhotosUI
import SeamLedgerKit
import struct SeamLedgerKit.Edge
import SwiftUI

struct SewingRecordView: View {
    @Binding var project: SewingProject?
    let append: (SewingAction) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var edgeName = ""
    @State private var pieceID = ""
    @State private var allowance = ""
    @State private var unit: Allowance.Unit = .millimetre
    @State private var seamName = ""
    @State private var firstEdge = ""
    @State private var secondEdge = ""
    @State private var note = ""
    @State private var before = ""
    @State private var after = ""
    @State private var measurementUnit: Allowance.Unit = .millimetre
    @State private var photoItem: PhotosPickerItem?
    @State private var photo: Data?
    @State private var loadingPhoto = false
    @FocusState private var editing: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let error {
                        Text(error).foregroundStyle(.red).accessibilityIdentifier("sewing.error")
                    }
                    Text("Compares your entries only; not a fit or construction safety certification.")
                    if let project {
                        edgeEditor(project)
                        Divider()
                        seamEditor(project)
                        Divider()
                        alterationEditor(project)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Seams and alterations")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Hide keyboard") { editing = false }
                }
            }
        }
        .task(id: photoItem) {
            guard let item = photoItem else { return }
            photo = nil
            loadingPhoto = true
            defer { if photoItem == item { loadingPhoto = false } }
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      !data.isEmpty, data.count <= 10_000_000, UIImage(data: data) != nil else {
                    throw LedgerError.invalidInput
                }
                try Task.checkCancellation()
                photo = data
                error = nil
            } catch is CancellationError {
                // A newly picked item replaces this request.
            } catch {
                if photoItem == item {
                    photo = nil
                    self.error = "Photo could not be loaded. Pick an image up to 10 MB. \(error.localizedDescription)"
                }
            }
        }
    }

    private func unitPicker(_ title: String, selection: Binding<Allowance.Unit>) -> some View {
        Picker(title, selection: selection) {
            Text("mm").tag(Allowance.Unit.millimetre)
            Text("cm").tag(Allowance.Unit.centimetre)
            Text("inch").tag(Allowance.Unit.inch)
        }
        .pickerStyle(.segmented)
    }

    private func entry(_ title: String, text: Binding<String>, id: String) -> some View {
        TextField(title, text: text)
            .focused($editing)
            .submitLabel(.done)
            .onSubmit { editing = false }
            .accessibilityIdentifier(id)
    }

    private func edgeEditor(_ current: SewingProject) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Named edges").font(.headline)
            ForEach(current.definition.edges, id: \.id) { edge in
                VStack(alignment: .leading) {
                    Text("\(edge.id) (\(edge.pieceID))")
                    allowanceText(edge)
                    Button("Remove edge \(edge.id) and its seams", role: .destructive) {
                        perform {
                            try append(.removeEdge(edgeID: edge.id))
                            if firstEdge == edge.id { firstEdge = "" }
                            if secondEdge == edge.id { secondEdge = "" }
                        }
                    }
                    .frame(minHeight: 44)
                }
            }
            if current.definition.pieces.isEmpty {
                Text("Add a piece in the cutting table before naming its edges.")
            } else {
                Picker("Piece", selection: $pieceID) {
                    Text("Choose piece").tag("")
                    ForEach(current.definition.pieces, id: \.id) { Text($0.id).tag($0.id) }
                }
                .accessibilityIdentifier("edge.piece")
                entry("Edge name (unique in project)", text: $edgeName, id: "edge.name")
                entry("Allowance (blank, 10, 1.5 or 5/8)", text: $allowance, id: "edge.allowance")
                unitPicker("Allowance unit", selection: $unit).accessibilityIdentifier("edge.unit")
                Button("Add edge") {
                    perform {
                        let edge = Edge(id: edgeName.trimmingCharacters(in: .whitespacesAndNewlines),
                                        pieceID: pieceID, allowance: try Allowance.parse(allowance, unit: unit))
                        try append(.addEdge(edge))
                        edgeName = ""; allowance = ""; editing = false
                    }
                }
                .disabled(pieceID.isEmpty || edgeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .frame(minHeight: 44)
                .accessibilityIdentifier("edge.add")
            }
        }
    }

    @ViewBuilder private func allowanceText(_ edge: Edge) -> some View {
        switch Result(catching: { try edge.allowance }) {
        case let .success(value): Text("Allowance: \(value?.recordedDescription ?? "unspecified")")
        case .failure: Text("Invalid recorded allowance").foregroundStyle(.red)
        }
    }

    private func seamEditor(_ current: SewingProject) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Seam pairs").font(.headline)
            ForEach(current.definition.seams, id: \.id) { seam in
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(seam.id): \(seam.firstEdgeID) + \(seam.secondEdgeID)")
                    ForEach(current.definition.edges.filter {
                        $0.id == seam.firstEdgeID || $0.id == seam.secondEdgeID
                    }, id: \.id) { edge in
                        Text(edge.id)
                        allowanceText(edge)
                    }
                    comparisonText(current, seam: seam)
                        .accessibilityIdentifier("seam.comparison.\(seam.id)")
                    let sewn = current.sewn.contains(seam.id)
                    let pressed = current.pressed.contains(seam.id)
                    Button(sewn ? "Undo sewn \(seam.id)" : "Mark sewn \(seam.id)") {
                        perform { try append(sewn ? .undoSewn(seamID: seam.id) : .sewn(seamID: seam.id)) }
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("seam.sewn.\(seam.id)")
                    Button(pressed ? "Undo pressed \(seam.id)" : "Mark pressed \(seam.id)") {
                        perform { try append(pressed ? .undoPressed(seamID: seam.id) : .pressed(seamID: seam.id)) }
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("seam.pressed.\(seam.id)")
                    Button("Remove seam \(seam.id)", role: .destructive) {
                        perform { try append(.removeSeam(seamID: seam.id)) }
                    }
                    .frame(minHeight: 44)
                }
            }
            entry("Seam name (unique in project)", text: $seamName, id: "seam.name")
            edgePicker("First edge", selection: $firstEdge, edges: current.definition.edges)
                .accessibilityIdentifier("seam.first")
            edgePicker("Second edge", selection: $secondEdge, edges: current.definition.edges)
                .accessibilityIdentifier("seam.second")
            Button("Link edges") {
                perform {
                    try append(.linkSeam(Seam(id: seamName.trimmingCharacters(in: .whitespacesAndNewlines),
                                              firstEdgeID: firstEdge, secondEdgeID: secondEdge)))
                    seamName = ""; firstEdge = ""; secondEdge = ""; editing = false
                }
            }
            .disabled(seamName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                      firstEdge == secondEdge || !current.definition.edges.contains(where: { $0.id == firstEdge }) ||
                      !current.definition.edges.contains(where: { $0.id == secondEdge }))
            .frame(minHeight: 44)
            .accessibilityIdentifier("seam.link")
        }
    }

    private func edgePicker(_ title: String, selection: Binding<String>, edges: [Edge]) -> some View {
        Picker(title, selection: selection) {
            Text("Choose edge").tag("")
            ForEach(edges, id: \.id) { Text($0.id).tag($0.id) }
        }
    }

    @ViewBuilder private func comparisonText(_ current: SewingProject, seam: Seam) -> some View {
        switch Result(catching: { try current.definition.comparison(for: seam.id) }) {
        case .success(.unknown): Text("Allowance unspecified; comparison unavailable")
        case .success(.equal): Text("Recorded allowances equal")
        case .success(.mismatch): Text("Warning: recorded allowances differ").foregroundStyle(.orange)
        case .failure: Text("Invalid seam record").foregroundStyle(.red)
        }
    }

    private func alterationEditor(_ current: SewingProject) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Alteration record").font(.headline)
            Text("Manually entered dimensions only. Notes and selected photos stay on this device.")
            ForEach(current.alterations, id: \.id) { alteration in
                VStack(alignment: .leading, spacing: 8) {
                    Text(alteration.text)
                    Text("Before: \(alteration.before?.recordedDescription ?? "unspecified")")
                    Text("After: \(alteration.after?.recordedDescription ?? "unspecified")")
                    if let data = alteration.photo, let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 180)
                            .accessibilityLabel("User-picked alteration photo")
                    }
                }
            }
            entry("Alteration note", text: $note, id: "alteration.note")
            entry("Before (optional)", text: $before, id: "alteration.before")
            entry("After (optional)", text: $after, id: "alteration.after")
            unitPicker("Measurement unit", selection: $measurementUnit)
            PhotosPicker("Pick optional photo (up to 10 MB)", selection: $photoItem, matching: .images)
                .disabled(loadingPhoto)
            if loadingPhoto { ProgressView("Loading selected photo") }
            if photo != nil {
                Text("Selected photo ready; saved only with the note")
                Button("Remove selected photo") { photoItem = nil; photo = nil }
            }
            Button("Save alteration") {
                perform {
                    let alteration = try AlterationNote(id: UUID().uuidString, text: note,
                                                         before: Allowance.parse(before, unit: measurementUnit),
                                                         after: Allowance.parse(after, unit: measurementUnit), photo: photo)
                    try append(.addAlteration(alteration))
                    note = ""; before = ""; after = ""; photoItem = nil; photo = nil; editing = false
                }
            }
            .disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || loadingPhoto)
            .frame(minHeight: 44)
            .accessibilityIdentifier("alteration.save")
        }
    }

    private func perform(_ work: () throws -> Void) {
        do { try work(); error = nil }
        catch { self.error = "Could not save this entry. Check names and positive denominators; use integers, decimals or fractions. \(error.localizedDescription)" }
    }
}
