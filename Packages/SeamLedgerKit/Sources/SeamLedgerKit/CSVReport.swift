import Foundation

public enum CSVReport {
    private static func cell(_ text: String) -> String {
        let trimmed = text.drop(while: { $0 == " " || $0 == "\t" || $0 == "\r" || $0 == "\n" })
        let unsafe = text.first == "\t" || text.first == "\r" || text.first == "\n" ||
            trimmed.first.map { "=+-@".contains($0) } == true
        let safe = (unsafe ? "'" : "") + text
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func row(_ fields: [String]) -> String {
        fields.map(cell).joined(separator: ",") + "\r\n"
    }

    public static func cuts(_ project: SewingProject) -> String {
        var result = row(["Piece", "Material", "Required", "Cut", "Remaining", "Mirrored", "Cut on fold"])
        for item in project.pieceProgressList {
            result += row([item.piece.id, item.piece.material.rawValue,
                           item.piece.requiredCount.map(String.init) ?? "", String(item.cutCount),
                           item.remainingCount.map(String.init) ?? "", item.piece.mirrored ? "yes" : "no",
                           item.piece.cutOnFold ? "yes" : "no"])
        }
        return result
    }

    public static func seams(_ project: SewingProject) throws -> String {
        var result = row(["Seam", "First edge", "First allowance", "Second edge", "Second allowance",
                          "Comparison", "Sewn", "Pressed"])
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
            result += row([seam.id, first.id, try first.allowance?.recordedDescription ?? "unspecified",
                           second.id, try second.allowance?.recordedDescription ?? "unspecified", comparison,
                           project.sewn.contains(seam.id) ? "yes" : "no",
                           project.pressed.contains(seam.id) ? "yes" : "no"])
        }
        return result
    }
}
