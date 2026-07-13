import Foundation
import ToolQualification
import XcircuitePackage

public struct ElectricalSignoffProcessQualificationRequest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 2
    public static let requiredApprovalStageID = "electrical-signoff.process-qualification"

    public var schemaVersion: Int
    public var qualificationID: String
    public var toolID: String
    public var qualificationSpec: ElectricalSignoffQualificationSpec
    public var qualificationReport: ElectricalSignoffQualificationReport
    public var scope: ToolQualificationScope
    public var processEvidence: ToolProcessQualificationEvidenceBuildRequest
    public var qualifiedAt: Date
    public var expiresAt: Date
    public var evaluatedAt: Date

    public init(
        qualificationID: String,
        toolID: String,
        qualificationSpec: ElectricalSignoffQualificationSpec,
        qualificationReport: ElectricalSignoffQualificationReport,
        scope: ToolQualificationScope,
        processEvidence: ToolProcessQualificationEvidenceBuildRequest,
        qualifiedAt: Date,
        expiresAt: Date,
        evaluatedAt: Date = Date(),
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.qualificationID = qualificationID
        self.toolID = toolID
        self.qualificationSpec = qualificationSpec
        self.qualificationReport = qualificationReport
        self.scope = scope
        self.processEvidence = processEvidence
        self.qualifiedAt = qualifiedAt
        self.expiresAt = expiresAt
        self.evaluatedAt = evaluatedAt
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ElectricalSignoffProcessQualificationError.unsupportedSchemaVersion(schemaVersion)
        }
        guard !qualificationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ElectricalSignoffProcessQualificationError.invalidRequest("qualificationID is required")
        }
        guard !toolID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ElectricalSignoffProcessQualificationError.invalidRequest("toolID is required")
        }
        guard scope.isCompleteForPDK else {
            throw ElectricalSignoffProcessQualificationError.invalidRequest(
                "process qualification requires a complete PDK-scoped ToolQualificationScope"
            )
        }
        guard processEvidence.qualificationID == qualificationID,
              processEvidence.toolID == toolID,
              processEvidence.scope == scope,
              processEvidence.requirePDKScope,
              processEvidence.independenceVerified,
              processEvidence.qualifiedAt == qualifiedAt,
              processEvidence.expiresAt == expiresAt else {
            throw ElectricalSignoffProcessQualificationError.invalidRequest(
                "typed process evidence must bind exactly to the request identity, scope, independence and validity window"
            )
        }
        guard qualifiedAt < expiresAt else {
            throw ElectricalSignoffProcessQualificationError.invalidRequest(
                "qualifiedAt must be earlier than expiresAt"
            )
        }
        try qualificationSpec.validate()
        try qualificationReport.validate()
    }
}
