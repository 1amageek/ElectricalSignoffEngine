import Foundation
import ToolQualification

public struct DefaultElectricalSignoffProcessQualificationEvaluator: ElectricalSignoffProcessQualificationEvaluating, Sendable {
    public init() {}

    public func evaluate(
        _ request: ElectricalSignoffProcessQualificationRequest
    ) throws -> ElectricalSignoffProcessQualificationResult {
        try request.validate()

        var checks: [ElectricalSignoffProcessQualificationCheck] = []
        var blockers: [String] = []

        func appendCheck(
            _ checkID: String,
            passed: Bool,
            observed: String,
            expected: String,
            failureCode: String
        ) {
            checks.append(ElectricalSignoffProcessQualificationCheck(
                checkID: checkID,
                passed: passed,
                observed: observed,
                expected: expected,
                failureCode: passed ? nil : failureCode
            ))
            if !passed {
                blockers.append(failureCode)
            }
        }

        let spec = request.qualificationSpec
        let report = request.qualificationReport
        let reportSchemaPassed: Bool
        do {
            try report.validate()
            reportSchemaPassed = true
        } catch {
            reportSchemaPassed = false
        }
        appendCheck(
            "qualification-report-schema",
            passed: reportSchemaPassed,
            observed: "schemaVersion=\(report.schemaVersion)",
            expected: "schemaVersion=\(ElectricalSignoffQualificationReport.currentSchemaVersion)",
            failureCode: "qualification-report-schema-unsupported"
        )
        let corpusIdentityPassed = report.corpusID == spec.corpusID
            && report.corpusVersion == spec.corpusVersion
            && report.pdkDigest.caseInsensitiveCompare(spec.pdkDigest) == .orderedSame
        appendCheck(
            "qualification-corpus-identity",
            passed: corpusIdentityPassed,
            observed: "\(report.corpusID):\(report.corpusVersion):\(report.pdkDigest)",
            expected: "\(spec.corpusID):\(spec.corpusVersion):\(spec.pdkDigest)",
            failureCode: "qualification-corpus-mismatch"
        )

        let expectedCaseIDs = Set(spec.cases.map(\.caseID))
        let reportCaseIDs = report.caseResults.map(\.caseID)
        let caseCoveragePassed = reportCaseIDs.count == Set(reportCaseIDs).count
            && Set(reportCaseIDs) == expectedCaseIDs
        appendCheck(
            "qualification-case-coverage",
            passed: caseCoveragePassed,
            observed: "reportCases=\(reportCaseIDs.count),expectedCases=\(expectedCaseIDs.count)",
            expected: "exact qualification case set",
            failureCode: "qualification-case-coverage-incomplete"
        )

        let reportCases = Dictionary(
            report.caseResults.map { ($0.caseID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let caseResultsPassed = spec.cases.allSatisfy { qualificationCase in
            guard let result = reportCases[qualificationCase.caseID] else { return false }
            return caseResultMatches(qualificationCase, result: result, requireOracle: true)
        }
        appendCheck(
            "qualification-case-results",
            passed: caseResultsPassed,
            observed: "passedCases=\(report.matchedCaseCount),oracleAgreement=\(report.oracleAgreementCount)",
            expected: "every declared case passes with an independent oracle agreement",
            failureCode: "qualification-case-result-incomplete"
        )

        let reportLevelPassed = report.completed
            && report.passed
            && report.qualificationLevel >= .oracleChecked
        appendCheck(
            "qualification-level",
            passed: reportLevelPassed,
            observed: "completed=\(report.completed),passed=\(report.passed),level=\(report.qualificationLevel.rawValue)",
            expected: "completed=true,passed=true,level>=oracleChecked",
            failureCode: "qualification-level-insufficient"
        )

        let implementationPassed = report.implementationID == request.scope.implementationID
            && request.toolID == report.implementationID
        appendCheck(
            "qualification-implementation",
            passed: implementationPassed,
            observed: "toolID=\(request.toolID),reportImplementation=\(report.implementationID),scopeImplementation=\(request.scope.implementationID)",
            expected: "all implementation identities match",
            failureCode: "qualification-implementation-mismatch"
        )

        let runID = report.runID
        let caseRunIdentityPassed = runID != nil
            && spec.cases.allSatisfy { $0.request.runID == runID }
        appendCheck(
            "qualification-run-identity",
            passed: caseRunIdentityPassed,
            observed: "reportRunID=\(runID ?? "<missing>")",
            expected: "report run ID matches every corpus case",
            failureCode: "qualification-run-identity-mismatch"
        )

        appendCheck(
            "independent-oracle-required",
            passed: spec.requireIndependentOracle,
            observed: "requireIndependentOracle=\(spec.requireIndependentOracle)",
            expected: "true",
            failureCode: "independent-oracle-not-required"
        )

        let processProfilePassed = !spec.cases.isEmpty
            && spec.cases.allSatisfy { $0.request.pdk.processID == request.scope.processProfileID }
        let pdkScopePassed = request.scope.pdkDigest?.caseInsensitiveCompare(spec.pdkDigest) == .orderedSame
            && processProfilePassed
            && report.pdkDigest.caseInsensitiveCompare(spec.pdkDigest) == .orderedSame
        appendCheck(
            "pdk-scope",
            passed: pdkScopePassed,
            observed: "scopePDK=\(request.scope.pdkDigest ?? "<missing>"),reportPDK=\(report.pdkDigest)",
            expected: spec.pdkDigest,
            failureCode: "pdk-scope-mismatch"
        )

        let freshnessPassed = request.qualifiedAt <= request.evaluatedAt
            && request.evaluatedAt < request.expiresAt
        appendCheck(
            "qualification-window",
            passed: freshnessPassed,
            observed: "qualifiedAt=\(request.qualifiedAt),expiresAt=\(request.expiresAt),evaluatedAt=\(request.evaluatedAt)",
            expected: "qualifiedAt<=evaluatedAt<expiresAt",
            failureCode: "qualification-window-invalid"
        )

        let promotedEvidence: ToolProcessQualificationEvidence?
        do {
            let built = try ToolProcessQualificationEvidenceBuilder().build(
                request.processEvidence,
                at: request.evaluatedAt
            )
            promotedEvidence = built
            appendCheck(
                "typed-process-evidence",
                passed: true,
                observed: "corpus=\(built.corpusEvidenceIDs.count),oracle=\(built.oracleEvidenceIDs.count),health=\(built.healthEvidenceIDs.count),approval=\(built.approvalEvidenceIDs.count),artifacts=\(built.evidenceArtifactIDs.count)",
                expected: "all typed evidence groups pass with exact artifact binding",
                failureCode: "typed-process-evidence-invalid"
            )
        } catch {
            promotedEvidence = nil
            appendCheck(
                "typed-process-evidence",
                passed: false,
                observed: error.localizedDescription,
                expected: "all typed evidence groups pass with exact artifact binding",
                failureCode: "typed-process-evidence-invalid"
            )
        }

        let qualified = blockers.isEmpty
        let evidence: ToolProcessQualificationEvidence
        if let promotedEvidence {
            if qualified {
                evidence = promotedEvidence
            } else {
                evidence = ToolProcessQualificationEvidence(
                    qualificationID: promotedEvidence.qualificationID,
                    toolID: promotedEvidence.toolID,
                    scope: promotedEvidence.scope,
                    status: .blocked,
                    corpusEvidenceIDs: promotedEvidence.corpusEvidenceIDs,
                    oracleEvidenceIDs: promotedEvidence.oracleEvidenceIDs,
                    healthEvidenceIDs: promotedEvidence.healthEvidenceIDs,
                    approvalEvidenceIDs: promotedEvidence.approvalEvidenceIDs,
                    evidenceArtifactIDs: promotedEvidence.evidenceArtifactIDs,
                    independenceVerified: promotedEvidence.independenceVerified,
                    blockers: blockers
                )
            }
        } else {
            evidence = blockedEvidence(for: request, blockers: blockers)
        }

        return ElectricalSignoffProcessQualificationResult(
            qualificationID: request.qualificationID,
            status: qualified ? .qualified : .blocked,
            evidence: evidence,
            checks: checks,
            blockers: blockers,
            evaluatedAt: request.evaluatedAt
        )
    }

    private func blockedEvidence(
        for request: ElectricalSignoffProcessQualificationRequest,
        blockers: [String]
    ) -> ToolProcessQualificationEvidence {
        let processEvidence = request.processEvidence
        return ToolProcessQualificationEvidence(
            qualificationID: request.qualificationID,
            toolID: request.toolID,
            scope: request.scope,
            status: .blocked,
            corpusEvidenceIDs: processEvidence.corpusEvidence.map(\.evidenceID),
            oracleEvidenceIDs: processEvidence.oracleEvidence.map(\.evidenceID),
            healthEvidenceIDs: processEvidence.healthEvidence.map(\.evidenceID),
            approvalEvidenceIDs: processEvidence.approvalEvidence.map(\.evidenceID),
            evidenceArtifactIDs: processEvidence.evidenceArtifacts.compactMap { $0.artifactID ?? $0.path },
            independenceVerified: false,
            blockers: blockers
        )
    }

    private func caseResultMatches(
        _ qualificationCase: ElectricalSignoffQualificationCase,
        result: ElectricalSignoffQualificationCaseResult,
        requireOracle: Bool
    ) -> Bool {
        let expectedCondition = qualificationCase.request.configuration.operatingCondition
        guard result.axis == qualificationCase.axis,
              result.cornerID == expectedCondition.id,
              result.pdkCornerID == expectedCondition.pdkCornerID,
              result.nativeStatus == qualificationCase.expected.status,
              result.nativeViolationCount == qualificationCase.expected.violationCount,
              result.nativeDiagnosticCodes == qualificationCase.expected.diagnosticCodes.sorted(),
              result.passed else {
            return false
        }

        let expectedMetrics = Dictionary(
            qualificationCase.expected.metrics.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let nativeMetrics = Dictionary(
            result.nativeMetrics.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let comparisons = Dictionary(
            result.metricComparisons.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        guard expectedMetrics.count == result.metricComparisons.count,
              expectedMetrics.keys.allSatisfy({ nativeMetrics[$0] != nil && comparisons[$0]?.passed == true }) else {
            return false
        }
        for (name, expectation) in expectedMetrics {
            guard let nativeMetric = nativeMetrics[name],
                  let comparison = comparisons[name],
                  nativeMetric.unit == expectation.unit,
                  expectation.matches(nativeMetric.value),
                  comparison.actualValue == nativeMetric.value,
                  comparison.expectedValue == expectation.expectedValue,
                  comparison.unit == expectation.unit else {
                return false
            }
        }

        if requireOracle {
            guard let oracle = result.oracle,
                  oracle.isIndependent,
                  result.oracleAgreementPassed == true,
                  oracle.pdkDigest.caseInsensitiveCompare(qualificationCase.request.pdk.digest) == .orderedSame,
                  oracle.status == result.nativeStatus,
                  oracle.violationCount == result.nativeViolationCount,
                  oracle.diagnosticCodes == result.nativeDiagnosticCodes else {
                return false
            }
            for expectation in qualificationCase.expected.metrics {
                guard let oracleMetric = oracle.metrics.first(where: { $0.name == expectation.name }),
                      oracleMetric.unit == expectation.unit,
                      expectation.matches(oracleMetric.value) else {
                    return false
                }
            }
        }
        return true
    }
}
