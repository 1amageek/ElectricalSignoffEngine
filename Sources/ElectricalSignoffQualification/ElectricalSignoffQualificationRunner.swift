import Foundation
import ElectricalSignoffCore
import ElectricalSignoffEngine
import ToolQualification
import CircuiteFoundation

public struct ElectricalSignoffQualificationRunner: Sendable {
    public let engine: any ElectricalSignoffExecuting
    public let oracle: (any ElectricalSignoffQualificationOracle)?
    public let implementationID: String

    public init(
        engine: any ElectricalSignoffExecuting,
        oracle: (any ElectricalSignoffQualificationOracle)? = nil,
        implementationID: String = "ElectricalSignoffEngine"
    ) {
        self.engine = engine
        self.oracle = oracle
        self.implementationID = implementationID
    }

    public func run(
        spec: ElectricalSignoffQualificationSpec,
        generatedAt: Date = Date()
    ) async throws -> ElectricalSignoffQualificationReport {
        try spec.validate()
        var results: [ElectricalSignoffQualificationCaseResult] = []
        for testCase in spec.cases {
            results.append(await evaluate(testCase, spec: spec))
        }

        let passed = results.allSatisfy(\.passed)
        let runIDs = Set(spec.cases.map(\.request.runID))
        let reportRunID = runIDs.count == 1 ? runIDs.first : nil
        let hasIndependentOracle = results.allSatisfy { result in
            result.oracle?.isIndependent == true && result.oracleAgreementPassed == true
        }
        let level: ToolQualificationLevel
        if !passed {
            level = .unknown
        } else if hasIndependentOracle {
            level = .oracleChecked
        } else {
            level = .corpusChecked
        }
        var failureCodes = Array(Set(results.flatMap(\.failureCodes))).sorted()
        if spec.requireIndependentOracle && !hasIndependentOracle {
            failureCodes.append("independent-oracle-required")
        }
        return ElectricalSignoffQualificationReport(
            corpusID: spec.corpusID,
            corpusVersion: spec.corpusVersion,
            pdkDigest: spec.pdkDigest,
            runID: reportRunID,
            implementationID: implementationID,
            generatedAt: generatedAt,
            completed: true,
            passed: passed && (!spec.requireIndependentOracle || hasIndependentOracle),
            qualificationLevel: spec.requireIndependentOracle && !hasIndependentOracle ? .unknown : level,
            caseResults: results,
            failureCodes: Array(Set(failureCodes)).sorted()
        )
    }

    private func evaluate(
        _ testCase: ElectricalSignoffQualificationCase,
        spec: ElectricalSignoffQualificationSpec
    ) async -> ElectricalSignoffQualificationCaseResult {
        var nativeStatus: ElectricalSignoffExecutionStatus = .failed
        var nativeViolationCount = 0
        var nativeDiagnosticCodes: [String] = []
        var nativeMetrics: [ElectricalSignoffPayload.Metric] = []
        var nativeArtifacts: [ArtifactReference] = []
        var failureCodes: [String] = []

        do {
            let runResult = try await engine.execute(testCase.request, axes: [testCase.axis])
            guard let envelope = runResult.axisResults[testCase.axis] else {
                throw ElectricalSignoffQualificationError.missingAxisResult(testCase.axis.rawValue)
            }
            nativeStatus = envelope.status
            nativeViolationCount = envelope.payload.violationCount
            nativeDiagnosticCodes = envelope.diagnostics.map { $0.code.rawValue }.sorted()
            nativeMetrics = envelope.payload.metrics
            nativeArtifacts = envelope.artifacts
        } catch {
            failureCodes.append("native-execution-error")
            nativeDiagnosticCodes.append("qualification.native-execution-error")
        }

        let metricComparisons = testCase.expected.metrics.map { expectation in
            let actual = nativeMetrics.first { $0.name == expectation.name }
            let passed = actual.map { metric in
                metric.unit == expectation.unit && expectation.matches(metric.value)
            } ?? false
            if !passed {
                failureCodes.append("metric-mismatch:\(expectation.name)")
            }
            return ElectricalSignoffMetricComparison(
                name: expectation.name,
                expectedValue: expectation.expectedValue,
                actualValue: actual?.value,
                unit: expectation.unit,
                absoluteTolerance: expectation.absoluteTolerance,
                relativeTolerance: expectation.relativeTolerance,
                passed: passed
            )
        }
        if nativeStatus != testCase.expected.status {
            failureCodes.append("status-mismatch")
        }
        if nativeViolationCount != testCase.expected.violationCount {
            failureCodes.append("violation-count-mismatch")
        }
        if nativeDiagnosticCodes != testCase.expected.diagnosticCodes.sorted() {
            failureCodes.append("diagnostic-codes-mismatch")
        }

        let oracleObservation: ElectricalSignoffOracleObservation?
        if let oracle {
            do {
                oracleObservation = try await oracle.evaluate(testCase)
                if oracleObservation?.isIndependent != true {
                    failureCodes.append("independent-oracle-invalid")
                }
                if oracleObservation?.pdkDigest != spec.pdkDigest {
                    failureCodes.append("oracle-pdk-digest-mismatch")
                }
            } catch {
                oracleObservation = nil
                failureCodes.append("oracle-execution-error")
            }
        } else {
            oracleObservation = nil
            if spec.requireIndependentOracle {
                failureCodes.append("independent-oracle-missing")
            }
        }

        let oracleAgreementPassed = oracleObservation.map { observation in
            let agrees = observation.isIndependent
                && observation.pdkDigest == spec.pdkDigest
                && observation.status == nativeStatus
                && observation.violationCount == nativeViolationCount
                && observation.diagnosticCodes == nativeDiagnosticCodes
                && testCase.expected.metrics.allSatisfy { expectation in
                    guard let nativeMetric = nativeMetrics.first(where: { $0.name == expectation.name }),
                          let oracleMetric = observation.metrics.first(where: { $0.name == expectation.name }) else {
                        return false
                    }
                    return nativeMetric.unit == oracleMetric.unit && expectation.matches(oracleMetric.value)
                }
            if !agrees {
                failureCodes.append("oracle-disagreement")
            }
            return agrees
        }

        return ElectricalSignoffQualificationCaseResult(
            caseID: testCase.caseID,
            axis: testCase.axis,
            cornerID: testCase.request.configuration.operatingCondition.id,
            pdkCornerID: testCase.request.configuration.operatingCondition.pdkCornerID,
            nativeStatus: nativeStatus,
            nativeViolationCount: nativeViolationCount,
            nativeDiagnosticCodes: nativeDiagnosticCodes,
            nativeMetrics: nativeMetrics,
            nativeArtifacts: nativeArtifacts,
            metricComparisons: metricComparisons,
            oracle: oracleObservation,
            oracleAgreementPassed: oracleAgreementPassed,
            passed: failureCodes.isEmpty,
            failureCodes: Array(Set(failureCodes)).sorted()
        )
    }
}
