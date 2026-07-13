import Foundation
import ElectricalSignoffCore
import ToolQualification
import XcircuitePackage

public struct ElectricalSignoffQualificationReport: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var corpusID: String
    public var corpusVersion: String
    public var pdkDigest: String
    public var runID: String?
    public var implementationID: String
    public var generatedAt: Date
    public var completed: Bool
    public var passed: Bool
    public var qualificationLevel: ToolQualificationLevel
    public var caseResults: [ElectricalSignoffQualificationCaseResult]
    public var failureCodes: [String]

    public init(
        corpusID: String,
        corpusVersion: String,
        pdkDigest: String,
        runID: String? = nil,
        implementationID: String,
        generatedAt: Date,
        completed: Bool,
        passed: Bool,
        qualificationLevel: ToolQualificationLevel,
        caseResults: [ElectricalSignoffQualificationCaseResult],
        failureCodes: [String] = [],
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.corpusID = corpusID
        self.corpusVersion = corpusVersion
        self.pdkDigest = pdkDigest
        self.runID = runID
        self.implementationID = implementationID
        self.generatedAt = generatedAt
        self.completed = completed
        self.passed = passed
        self.qualificationLevel = qualificationLevel
        self.caseResults = caseResults
        self.failureCodes = failureCodes.sorted()
    }

    public var caseCount: Int { caseResults.count }
    public var matchedCaseCount: Int { caseResults.filter(\.passed).count }
    public var oracleCaseCount: Int { caseResults.filter { $0.oracle != nil }.count }
    public var oracleAgreementCount: Int { caseResults.filter { $0.oracleAgreementPassed == true }.count }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ElectricalSignoffQualificationError.invalidSpec(
                "unsupported qualification report schema version \(schemaVersion)"
            )
        }
        guard !corpusID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !corpusVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !pdkDigest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !implementationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ElectricalSignoffQualificationError.invalidSpec("qualification report identity is incomplete")
        }
        guard Set(caseResults.map(\.caseID)).count == caseResults.count,
              caseResults.allSatisfy({
                  !$0.caseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && $0.axis != .aggregate
                      && $0.nativeViolationCount >= 0
                      && Set($0.nativeDiagnosticCodes).count == $0.nativeDiagnosticCodes.count
                      && Set($0.nativeMetrics.map(\.name)).count == $0.nativeMetrics.count
                      && $0.nativeMetrics.allSatisfy {
                          !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              && !$0.unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              && $0.value.isFinite
                      }
                      && Set($0.metricComparisons.map(\.name)).count == $0.metricComparisons.count
              }) else {
            throw ElectricalSignoffQualificationError.invalidSpec("qualification report case results are malformed")
        }
        guard Set(failureCodes).count == failureCodes.count else {
            throw ElectricalSignoffQualificationError.invalidSpec("qualification report failure codes must be unique")
        }
    }

    public func toolEvidence(
        reportPath: String,
        reportSHA256: String?,
        scope: ToolQualificationScope,
        checkedAt: Date
    ) -> ToolEvidence {
        let usesOracle = qualificationLevel >= .oracleChecked
        let kind: ToolEvidenceKind = usesOracle ? .oracle : .corpus
        let artifact = XcircuiteFileReference(
            artifactID: "electrical-signoff-qualification-report",
            path: reportPath,
            kind: .report,
            format: .json,
            sha256: reportSHA256
        )
        return ToolEvidence(
            evidenceID: "electrical-signoff:\(corpusID):\(corpusVersion)",
            kind: kind,
            artifact: artifact,
            qualification: ToolEvidenceQualificationSummary(
                qualified: passed && completed,
                policyID: usesOracle ? "electrical-signoff-independent-oracle" : "electrical-signoff-corpus",
                observedMetrics: [
                    "casePassRate": caseCount == 0 ? 0 : Double(matchedCaseCount) / Double(caseCount),
                    "oracleAgreementRate": oracleCaseCount == 0 ? 0 : Double(oracleAgreementCount) / Double(oracleCaseCount),
                ],
                observedCounts: [
                    "caseCount": caseCount,
                    "matchedCaseCount": matchedCaseCount,
                    "oracleCaseCount": oracleCaseCount,
                    "oracleAgreementCount": oracleAgreementCount,
                ],
                failureCodes: failureCodes,
                scope: scope
            ),
            checkedAt: checkedAt
        )
    }
}
