import Foundation
import ToolQualification

public struct ElectricalSignoffProcessQualificationResult: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var qualificationID: String
    public var status: ToolProcessQualificationStatus
    public var evidence: ToolProcessQualificationEvidence
    public var checks: [ElectricalSignoffProcessQualificationCheck]
    public var blockers: [String]
    public var evaluatedAt: Date

    public init(
        qualificationID: String,
        status: ToolProcessQualificationStatus,
        evidence: ToolProcessQualificationEvidence,
        checks: [ElectricalSignoffProcessQualificationCheck],
        blockers: [String],
        evaluatedAt: Date,
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.qualificationID = qualificationID
        self.status = status
        self.evidence = evidence
        self.checks = checks
        self.blockers = Array(Set(blockers)).sorted()
        self.evaluatedAt = evaluatedAt
    }

    public var qualified: Bool {
        status == .qualified && blockers.isEmpty && evidence.isQualified(at: evaluatedAt, requirePDKScope: true)
    }
}
