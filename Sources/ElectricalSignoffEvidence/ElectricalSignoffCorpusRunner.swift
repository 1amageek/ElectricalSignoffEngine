import Foundation
import ElectricalSignoffCore
import ElectricalSignoffEngine
import CircuiteFoundation

public struct ElectricalSignoffCorpusRunner: Sendable {
    public let engine: any ElectricalSignoffExecuting
    public let oracle: (any ElectricalSignoffOracle)?
    public let implementationID: String

    public init(
        engine: any ElectricalSignoffExecuting,
        oracle: (any ElectricalSignoffOracle)? = nil,
        implementationID: String = "ElectricalSignoffEngine"
    ) {
        self.engine = engine
        self.oracle = oracle
        self.implementationID = implementationID
    }

    public func run(
        spec: ElectricalSignoffCorpusSpec,
        generatedAt: Date = Date()
    ) async throws -> ElectricalSignoffCorpusReport {
        try spec.validate()
        var results: [ElectricalSignoffCorpusCaseResult] = []
        for testCase in spec.cases {
            results.append(await evaluate(testCase, spec: spec))
        }

        let passed = results.allSatisfy(\.passed)
        let runIDs = Set(spec.cases.map(\.request.runID))
        let reportRunID = runIDs.count == 1 ? runIDs.first : nil
        let hasExternalOracleEvidence = results.allSatisfy { result in
            result.oracle?.hasEvidenceBinding == true
        }
        let hasExternalOracleAgreement = results.allSatisfy { result in
            result.oracleAgreementPassed == true
        }
        let maturity: ElectricalSignoffObservationMaturity = hasExternalOracleEvidence
            ? .oracleCorrelated
            : .corpusObserved
        var failureCodes = Array(Set(results.flatMap(\.failureCodes))).sorted()
        if spec.requireExternalOracleEvidence && !hasExternalOracleEvidence {
            failureCodes.append("external-oracle-evidence-required")
        }
        return ElectricalSignoffCorpusReport(
            corpusID: spec.corpusID,
            corpusVersion: spec.corpusVersion,
            pdkDigest: spec.pdkDigest,
            runID: reportRunID,
            implementationID: implementationID,
            generatedAt: generatedAt,
            completed: true,
            passed: passed && (!spec.requireExternalOracleEvidence || hasExternalOracleAgreement),
            observationMaturity: maturity,
            caseResults: results,
            failureCodes: Array(Set(failureCodes)).sorted()
        )
    }

    private func evaluate(
        _ testCase: ElectricalSignoffCorpusCase,
        spec: ElectricalSignoffCorpusSpec
    ) async -> ElectricalSignoffCorpusCaseResult {
        var nativeStatus: ElectricalSignoffExecutionStatus = .failed
        var nativeViolationCount = 0
        var nativeDiagnosticCodes: [String] = []
        var nativeMetrics: [ElectricalSignoffPayload.Metric] = []
        var nativeArtifacts: [ArtifactReference] = []
        var failureCodes: [String] = []

        do {
            let runResult = try await engine.execute(testCase.request, axes: [testCase.axis])
            guard let envelope = runResult.axisResults[testCase.axis] else {
                throw ElectricalSignoffCorpusError.missingAxisResult(testCase.axis.rawValue)
            }
            nativeStatus = envelope.status
            nativeViolationCount = envelope.payload.violationCount
            nativeDiagnosticCodes = envelope.diagnostics.map { $0.code.rawValue }.sorted()
            nativeMetrics = envelope.payload.metrics
            nativeArtifacts = envelope.artifacts
        } catch {
            failureCodes.append("native-execution-error")
            nativeDiagnosticCodes.append("corpus.native-execution-error")
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
                if oracleObservation?.hasEvidenceBinding != true {
                    failureCodes.append("oracle-evidence-binding-invalid")
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
            if spec.requireExternalOracleEvidence {
                failureCodes.append("external-oracle-evidence-missing")
            }
        }

        let oracleAgreementPassed = oracleObservation.map { observation in
            let agrees = observation.hasEvidenceBinding
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

        return ElectricalSignoffCorpusCaseResult(
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
