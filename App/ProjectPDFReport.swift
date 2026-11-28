import Foundation
import SeamLedgerKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ProjectPDFReportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }

    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

enum ProjectPDFReport {
    static func make(projectName: String, project: SewingProject, hasReferencePDF: Bool) throws -> Data {
        var lines: [(text: String, size: CGFloat, bold: Bool)] = [
            (projectName, 20, true)
        ]
        let summary = project.summary
        lines.append(("Cut progress: \(summary.completedPieces) of \(summary.totalPieces) pieces complete\(summary.hasUnknownCounts ? "; some required counts are unknown" : "")", 12, false))
        lines.append(("Owned reference PDF: \(hasReferencePDF ? "present locally; contents are not included in this report" : "none")", 12, false))
        lines.append(("Alteration photos are excluded from this report. Use a full backup to include private photos.", 10, false))
        lines.append(("Cut list", 16, true))
        for item in project.pieceProgressList {
            let quantity: String
            if let required = item.piece.requiredCount {
                quantity = "\(item.cutCount) of \(required) cut; \(item.remainingCount ?? 0) remaining"
            } else {
                quantity = "\(item.cutCount) cut; required count unknown"
            }
            lines.append(("\(item.piece.id) (\(item.piece.material.rawValue)): \(quantity)\(item.piece.mirrored ? "; mirrored pair" : "")\(item.piece.cutOnFold ? "; cut on fold" : "")", 12, false))
        }

        lines.append(("Seams", 16, true))
        for seam in project.definition.seams {
            guard let first = project.definition.edges.first(where: { $0.id == seam.firstEdgeID }),
                  let second = project.definition.edges.first(where: { $0.id == seam.secondEdgeID }) else {
                throw LedgerError.invalidInput
            }
            let comparison: String
            switch try project.definition.comparison(for: seam.id) {
            case .unknown: comparison = "unspecified"
            case .equal: comparison = "equal"
            case .mismatch: comparison = "mismatch"
            }
            let firstAllowance = try first.allowance?.recordedDescription ?? "unspecified"
            let secondAllowance = try second.allowance?.recordedDescription ?? "unspecified"
            lines.append(("\(seam.id): \(first.id) \(firstAllowance); \(second.id) \(secondAllowance); \(comparison); sewn \(project.sewn.contains(seam.id) ? "yes" : "no"); pressed \(project.pressed.contains(seam.id) ? "yes" : "no")", 12, false))
        }

        lines.append(("Alterations", 16, true))
        for note in project.alterations {
            lines.append((note.text, 12, true))
            if let before = note.before { lines.append(("Before: \(before.recordedDescription)", 12, false)) }
            if let after = note.after { lines.append(("After: \(after.recordedDescription)", 12, false)) }
        }

        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        return renderer.pdfData { context in
            context.beginPage()
            var y: CGFloat = 40

            func draw(_ line: (text: String, size: CGFloat, bold: Bool)) {
                let font = line.bold ? UIFont.boldSystemFont(ofSize: line.size) : UIFont.systemFont(ofSize: line.size)
                let attributes: [NSAttributedString.Key: Any] = [.font: font]
                let options: NSStringDrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
                let width = bounds.width - 80
                let measured = (line.text as NSString).boundingRect(
                    with: CGSize(width: width, height: 10_000), options: options,
                    attributes: attributes, context: nil
                )
                let height = max(ceil(measured.height), line.size) + 8
                if y + height > bounds.height - 40 {
                    context.beginPage()
                    y = 40
                }
                (line.text as NSString).draw(
                    with: CGRect(x: 40, y: y, width: width, height: height),
                    options: options, attributes: attributes, context: nil
                )
                y += height
            }
            for line in lines { draw(line) }
        }
    }
}
