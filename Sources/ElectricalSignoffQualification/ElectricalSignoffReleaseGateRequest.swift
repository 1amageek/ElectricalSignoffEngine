import Foundation
import ElectricalSignoffEngine
import ToolQualification
import XcircuitePackage

public struct ElectricalSignoffReleaseGateRequest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var runID: String
    public var runResult: ElectricalSignoffRunResult
    public var qualificationSpec: ElectricalSignoffQualificationSpec?
    public var qualificationReport: ElectricalSignoffQualificationReport
    public var processQualificationEvidence: ToolProcessQualificationEvidence?
    public var policy: ElectricalSignoffReleaseGatePolicy
    public var artifactIntegrity: [XcircuiteFileReferenceIntegrity]
    public var evaluatedAt: Date

    public init(
        runID: String,
        runResult: ElectricalSignoffRunResult,
        qualificationSpec: ElectricalSignoffQualificationSpec? = nil,
        qualificationReport: ElectricalSignoffQualificationReport,
        processQualificationEvidence: ToolProcessQualificationEvidence? = nil,
        policy: ElectricalSignoffReleaseGatePolicy,
        artifactIntegrity: [XcircuiteFileReferenceIntegrity] = [],
        evaluatedAt: Date = Date(),
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.runResult = runResult
        self.qualificationSpec = qualificationSpec
        self.qualificationReport = qualificationReport
        self.processQualificationEvidence = processQualificationEvidence
        self.policy = policy
        self.artifactIntegrity = artifactIntegrity
        self.evaluatedAt = evaluatedAt
    }
}
