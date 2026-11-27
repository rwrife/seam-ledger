import SwiftUI

struct ReportExportPreview: View {
    @Environment(\.dismiss) private var dismiss
    let projectName: String
    let onExportCuts: () -> Void
    let onExportSeams: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(projectName).font(.headline)
            Text("CSV reports include your cut list or seam details and progress.")
            Text("Photos are excluded from both reports.")
                .accessibilityIdentifier("report.photosExcluded")
            Button("Export cut report (CSV)", action: onExportCuts)
                .frame(minHeight: 44)
                .accessibilityIdentifier("report.export.cuts")
            Button("Export seam report (CSV)", action: onExportSeams)
                .frame(minHeight: 44)
                .accessibilityIdentifier("report.export.seams")
            Spacer()
        }
        .padding(24)
        .navigationTitle("Report preview")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}
