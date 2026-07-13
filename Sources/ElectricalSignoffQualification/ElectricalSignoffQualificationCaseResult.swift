import Foundation
import ElectricalSignoffCore
import XcircuitePackage

public struct ElectricalSignoffQualificationCaseResult: Sendable, Hashable, Codable {
    public var caseID: String
    public var axis: ElectricalSignoffAnalysisAxis
    public var cornerID: String?
    public var pdkCornerID: String?
    public var nativeStatus: XcircuiteEngineExecutionStatus
    public var nativeViolationCount: Int
    public var nativeDiagnosticCodes: [String]
    public var nativeMetrics: [ElectricalSignoffPayload.Metric]
    public var nativeArtifacts: [XcircuiteFileReference]
    public var metricComparisons: [ElectricalSignoffMetricComparison]
    public var oracle: ElectricalSignoffOracleObservation?
    public var oracleAgreementPassed: Bool?
    public var passed: Bool
    public var failureCodes: [String]

    public init(
        caseID: String,
        axis: ElectricalSignoffAnalysisAxis,
        cornerID: String? = nil,
        pdkCornerID: String? = nil,
        nativeStatus: XcircuiteEngineExecutionStatus,
        nativeViolationCount: Int,
        nativeDiagnosticCodes: [String],
        nativeMetrics: [ElectricalSignoffPayload.Metric],
        nativeArtifacts: [XcircuiteFileReference],
        metricComparisons: [ElectricalSignoffMetricComparison],
        oracle: ElectricalSignoffOracleObservation?,
        oracleAgreementPassed: Bool?,
        passed: Bool,
        failureCodes: [String]
    ) {
        self.caseID = caseID
        self.axis = axis
        self.cornerID = cornerID
        self.pdkCornerID = pdkCornerID
        self.nativeStatus = nativeStatus
        self.nativeViolationCount = nativeViolationCount
        self.nativeDiagnosticCodes = nativeDiagnosticCodes.sorted()
        self.nativeMetrics = nativeMetrics
        self.nativeArtifacts = nativeArtifacts
        self.metricComparisons = metricComparisons
        self.oracle = oracle
        self.oracleAgreementPassed = oracleAgreementPassed
        self.passed = passed
        self.failureCodes = failureCodes.sorted()
    }
}
