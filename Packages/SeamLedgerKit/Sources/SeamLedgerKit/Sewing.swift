public enum LedgerError: Error, Equatable {
    case invalidInput, overflow, invalidTransition, reconciliationRequired
}

/// Nonnegative, reduced rational micrometres. No floating point rounding.
public struct Allowance: Equatable, Sendable {
    public enum Unit: Int64, Sendable { case micrometre = 1, millimetre = 1_000, centimetre = 10_000, inch = 25_400 }
    public let numerator: Int64
    public let denominator: Int64

    public init(_ numerator: Int64, denominator: Int64 = 1, unit: Unit) throws {
        guard numerator >= 0, denominator > 0 else { throw LedgerError.invalidInput }
        func gcd(_ a: Int64, _ b: Int64) -> Int64 {
            var (a, b) = (a, b)
            while b != 0 { (a, b) = (b, a % b) }
            return a
        }
        let common = gcd(numerator, denominator)
        let n = numerator / common
        let d = denominator / common
        let scaleCommon = gcd(unit.rawValue, d)
        let product = n.multipliedReportingOverflow(by: unit.rawValue / scaleCommon)
        guard !product.overflow else { throw LedgerError.overflow }
        self.numerator = product.partialValue
        self.denominator = d / scaleCommon
    }
}

public enum AllowanceComparison: Equatable, Sendable {
    case unknown, equal, mismatch
    public static func compare(_ lhs: Allowance?, _ rhs: Allowance?) -> Self {
        guard let lhs, let rhs else { return .unknown }
        return lhs == rhs ? .equal : .mismatch
    }
}

public struct Piece: Equatable, Codable, Sendable {
    public let id: String
    /// Physical pieces, regardless of fold instruction. nil means unknown.
    public let requiredCount: Int?
    public let cutOnFold: Bool
    public init(id: String, requiredCount: Int?, cutOnFold: Bool = false) throws {
        guard !id.isEmpty, requiredCount.map({ $0 > 0 }) ?? true else { throw LedgerError.invalidInput }
        self.id = id; self.requiredCount = requiredCount; self.cutOnFold = cutOnFold
    }
    public static func mirroredPair(id: String, cutOnFold: Bool = false) throws -> Self {
        try Self(id: id, requiredCount: 2, cutOnFold: cutOnFold)
    }
}

/// Each edge belongs to one piece; a seam explicitly pairs two distinct edges.
public struct Edge: Equatable, Codable, Sendable {
    public let id: String
    public let pieceID: String
    public let allowanceNumerator: Int64?
    public let allowanceDenominator: Int64
    public init(id: String, pieceID: String, allowance: Allowance?) {
        self.id = id; self.pieceID = pieceID
        allowanceNumerator = allowance?.numerator
        allowanceDenominator = allowance?.denominator ?? 1
    }
    public var allowance: Allowance? {
        get throws {
            guard let n = allowanceNumerator else { return nil }
            return try Allowance(n, denominator: allowanceDenominator, unit: .micrometre)
        }
    }
}

public struct Seam: Equatable, Codable, Sendable {
    public let id: String
    public let firstEdgeID: String
    public let secondEdgeID: String
    public init(id: String, firstEdgeID: String, secondEdgeID: String) {
        self.id = id; self.firstEdgeID = firstEdgeID; self.secondEdgeID = secondEdgeID
    }
}

public struct ProjectDefinition: Equatable, Codable, Sendable {
    public let pieces: [Piece]
    public let edges: [Edge]
    public let seams: [Seam]
    public init(pieces: [Piece], edges: [Edge] = [], seams: [Seam] = []) throws {
        self.pieces = pieces; self.edges = edges; self.seams = seams
        try validate()
    }
    public func validate() throws {
        guard Set(pieces.map(\.id)).count == pieces.count,
              Set(edges.map(\.id)).count == edges.count,
              Set(seams.map(\.id)).count == seams.count else { throw LedgerError.invalidInput }
        for p in pieces { _ = try Piece(id: p.id, requiredCount: p.requiredCount, cutOnFold: p.cutOnFold) }
        for e in edges {
            guard !e.id.isEmpty, pieces.contains(where: { $0.id == e.pieceID }),
                  e.allowanceDenominator > 0 else { throw LedgerError.invalidInput }
            _ = try e.allowance
        }
        for s in seams {
            guard !s.id.isEmpty, s.firstEdgeID != s.secondEdgeID,
                  edges.contains(where: { $0.id == s.firstEdgeID }),
                  edges.contains(where: { $0.id == s.secondEdgeID }) else { throw LedgerError.invalidInput }
        }
    }
    public func comparison(for seamID: String) throws -> AllowanceComparison {
        guard let s = seams.first(where: { $0.id == seamID }),
              let a = edges.first(where: { $0.id == s.firstEdgeID }),
              let b = edges.first(where: { $0.id == s.secondEdgeID }) else { throw LedgerError.invalidInput }
        return try .compare(a.allowance, b.allowance)
    }
}

public enum SewingAction: Equatable, Codable, Sendable {
    case cut(pieceID: String, physicalIndex: Int)
    case undoCut(pieceID: String, physicalIndex: Int)
    case sewn(seamID: String), undoSewn(seamID: String)
    case pressed(seamID: String), undoPressed(seamID: String)
    /// Explicit reconciliation resets all progress; the immutable history remains.
    case reconcile(ProjectDefinition)
}

public struct SewingEvent: Equatable, Codable, Sendable {
    public let id: String
    public let revision: Int
    public let action: SewingAction
    public init(id: String, revision: Int, action: SewingAction) {
        self.id = id; self.revision = revision; self.action = action
    }
}

public struct SewingProject: Sendable {
    public private(set) var definition: ProjectDefinition
    public private(set) var revision = 0
    public private(set) var history: [SewingEvent] = []
    private var cuts: [String: Set<Int>] = [:]
    public private(set) var sewn: Set<String> = []
    public private(set) var pressed: Set<String> = []
    public init(definition: ProjectDefinition) throws {
        try definition.validate(); self.definition = definition
    }
    public func remaining(pieceID: String) throws -> Int? {
        guard let piece = definition.pieces.first(where: { $0.id == pieceID }) else { throw LedgerError.invalidInput }
        return piece.requiredCount.map { $0 - (cuts[pieceID]?.count ?? 0) }
    }
    public mutating func apply(_ event: SewingEvent) throws {
        guard !event.id.isEmpty, !history.contains(where: { $0.id == event.id }) else { throw LedgerError.invalidTransition }
        guard event.revision == revision else { throw LedgerError.reconciliationRequired }
        switch event.action {
        case let .cut(id, index), let .undoCut(id, index):
            guard let p = definition.pieces.first(where: { $0.id == id }),
                  let count = p.requiredCount, index > 0, index <= count else { throw LedgerError.invalidInput }
            let undo: Bool
            if case .undoCut = event.action { undo = true } else { undo = false }
            let exists = cuts[id, default: []].contains(index)
            guard exists == undo else { throw LedgerError.invalidTransition }
            if undo { cuts[id, default: []].remove(index) } else { cuts[id, default: []].insert(index) }
        case let .sewn(id), let .undoSewn(id), let .pressed(id), let .undoPressed(id):
            guard definition.seams.contains(where: { $0.id == id }) else { throw LedgerError.invalidInput }
            switch event.action {
            case .sewn: guard sewn.insert(id).inserted else { throw LedgerError.invalidTransition }
            case .undoSewn: guard sewn.remove(id) != nil else { throw LedgerError.invalidTransition }
            case .pressed: guard pressed.insert(id).inserted else { throw LedgerError.invalidTransition }
            case .undoPressed: guard pressed.remove(id) != nil else { throw LedgerError.invalidTransition }
            default: break
            }
        case let .reconcile(definition):
            try definition.validate()
            guard self.definition != definition else { throw LedgerError.invalidTransition }
            let next = revision.addingReportingOverflow(1)
            guard !next.overflow else { throw LedgerError.overflow }
            self.definition = definition; revision = next.partialValue
            cuts = [:]; sewn = []; pressed = []
        }
        history.append(event)
    }
}
