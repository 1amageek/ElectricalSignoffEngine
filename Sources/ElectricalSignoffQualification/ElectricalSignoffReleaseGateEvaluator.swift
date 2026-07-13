import Foundation
import ElectricalSignoffCore
import ElectricalSignoffEngine
import XcircuitePackage

public protocol ElectricalSignoffReleaseGateEvaluating: Sendable {
    func evaluate(_ request: ElectricalSignoffReleaseGateRequest) throws -> ElectricalSignoffReleaseGateResult
}

public struct DefaultElectricalSignoffReleaseGateEvaluator: ElectricalSignoffReleaseGateEvaluating, Sendable {
    public init() {}

    public func evaluate(_ request: ElectricalSignoffReleaseGateRequest) throws -> ElectricalSignoffReleaseGateResult {
        guard request.schemaVersion == ElectricalSignoffReleaseGateRequest.currentSchemaVersion else {
            throw ElectricalSignoffReleaseGateError.invalidRequest(
                "unsupported release gate request schema version \(request.schemaVersion)"
            )
        }
        try request.policy.validate()
        guard !request.runID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ElectricalSignoffReleaseGateError.invalidRequest("run ID is required")
        }

        var checks: [ElectricalSignoffReleaseGateResult.Check] = []
        var blockedCodes: [String] = []
        var failedCodes: [String] = []

        let reportSchemaPassed: Bool
        do {
            try request.qualificationReport.validate()
            reportSchemaPassed = true
        } catch {
            reportSchemaPassed = false
        }
        appendCheck(
            &checks,
            passed: reportSchemaPassed,
            checkID: "qualification-report-schema",
            observed: "schemaVersion=\(request.qualificationReport.schemaVersion)",
            expected: "schemaVersion=\(ElectricalSignoffQualificationReport.currentSchemaVersion)",
            failureCode: "qualification-report-schema-unsupported",
            to: &blockedCodes
        )

        let qualificationCoveragePassed: Bool
        if let qualificationSpec = request.qualificationSpec {
            do {
                try qualificationSpec.validate()
            } catch {
                throw ElectricalSignoffReleaseGateError.invalidRequest(
                    "qualification spec is invalid: \(error.localizedDescription)"
                )
            }

            let reportCaseIDs = request.qualificationReport.caseResults.map(\.caseID)
            let expectedCaseIDs = qualificationSpec.cases.map(\.caseID)
            var coveragePassed = reportCaseIDs.count == Set(reportCaseIDs).count
                && Set(reportCaseIDs) == Set(expectedCaseIDs)
            if !coveragePassed {
                blockedCodes.append("qualification-case-set-mismatch")
            }
            let caseRunIDsPassed = qualificationSpec.cases.allSatisfy {
                $0.request.runID == request.runID
            }
            if !caseRunIDsPassed {
                coveragePassed = false
                blockedCodes.append("qualification-case-run-id-mismatch")
            }

            let reportCases = Dictionary(
                request.qualificationReport.caseResults.map { ($0.caseID, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            for qualificationCase in qualificationSpec.cases {
                guard let result = reportCases[qualificationCase.caseID] else {
                    coveragePassed = false
                    blockedCodes.append("missing-qualification-case:\(qualificationCase.caseID)")
                    continue
                }
                let expectedCondition = qualificationCase.request.configuration.operatingCondition
                let identityPassed = result.axis == qualificationCase.axis
                    && result.cornerID == expectedCondition.id
                    && result.pdkCornerID == expectedCondition.pdkCornerID
                    && result.nativeStatus == qualificationCase.expected.status
                    && result.nativeViolationCount == qualificationCase.expected.violationCount
                    && result.nativeDiagnosticCodes == qualificationCase.expected.diagnosticCodes.sorted()
                    && result.passed
                if !identityPassed {
                    coveragePassed = false
                    blockedCodes.append("qualification-case-identity-mismatch:\(qualificationCase.caseID)")
                }
            }

            let corpusIdentityPassed = request.qualificationReport.corpusID == qualificationSpec.corpusID
                && request.qualificationReport.corpusVersion == qualificationSpec.corpusVersion
                && request.qualificationReport.pdkDigest.caseInsensitiveCompare(qualificationSpec.pdkDigest) == .orderedSame
            appendCheck(
                &checks,
                passed: corpusIdentityPassed,
                checkID: "qualification-corpus-identity",
                observed: "\(request.qualificationReport.corpusID):\(request.qualificationReport.corpusVersion):\(request.qualificationReport.pdkDigest)",
                expected: "\(qualificationSpec.corpusID):\(qualificationSpec.corpusVersion):\(qualificationSpec.pdkDigest)",
                failureCode: "qualification-corpus-mismatch",
                to: &blockedCodes
            )
            appendCheck(
                &checks,
                passed: coveragePassed,
                checkID: "qualification-case-coverage",
                observed: "reportCases=\(reportCaseIDs.count),expectedCases=\(expectedCaseIDs.count)",
                expected: "exact qualification case set with axis and corner provenance",
                failureCode: "qualification-case-coverage-incomplete",
                to: &blockedCodes
            )
            qualificationCoveragePassed = coveragePassed && corpusIdentityPassed
        } else {
            appendCheck(
                &checks,
                passed: false,
                checkID: "qualification-spec",
                observed: "missing",
                expected: "qualification spec is retained with the release request",
                failureCode: "qualification-spec-missing",
                to: &blockedCodes
            )
            qualificationCoveragePassed = false
        }

        appendCheck(
            &checks,
            passed: request.runResult.runID == request.runID,
            checkID: "run-id",
            observed: request.runResult.runID,
            expected: request.runID,
            failureCode: "run-id-mismatch",
            to: &blockedCodes
        )

        let reportRunID = request.qualificationReport.runID ?? "<missing>"
        appendCheck(
            &checks,
            passed: request.qualificationReport.runID == request.runID,
            checkID: "qualification-run-id",
            observed: reportRunID,
            expected: request.runID,
            failureCode: "qualification-run-id-mismatch",
            to: &blockedCodes
        )

        let pdkDigests = Set(
            request.runResult.cornerResults.values
                .flatMap { $0.values }
                .compactMap { $0.payload.provenance?.pdkDigest }
        )
        let pdkScopePassed = request.qualificationReport.pdkDigest.caseInsensitiveCompare(request.policy.pdkDigest) == .orderedSame
            && pdkDigests.allSatisfy { $0.caseInsensitiveCompare(request.policy.pdkDigest) == .orderedSame }
            && !pdkDigests.isEmpty
        appendCheck(
            &checks,
            passed: pdkScopePassed,
            checkID: "pdk-scope",
            observed: ([request.qualificationReport.pdkDigest] + pdkDigests.sorted()).joined(separator: ","),
            expected: request.policy.pdkDigest,
            failureCode: "pdk-scope-mismatch",
            to: &blockedCodes
        )

        let qualificationPassed = request.qualificationReport.completed
            && request.qualificationReport.passed
            && request.qualificationReport.qualificationLevel >= request.policy.minimumQualificationLevel
            && qualificationCoveragePassed
        appendCheck(
            &checks,
            passed: qualificationPassed,
            checkID: "qualification-level",
            observed: "completed=\(request.qualificationReport.completed),passed=\(request.qualificationReport.passed),level=\(request.qualificationReport.qualificationLevel.rawValue)",
            expected: "completed=true,passed=true,level>=\(request.policy.minimumQualificationLevel.rawValue)",
            failureCode: "qualification-level-insufficient",
            to: &failedCodes
        )

        let qualificationAge = request.evaluatedAt.timeIntervalSince(request.qualificationReport.generatedAt)
        let qualificationFresh = qualificationAge >= 0
            && qualificationAge <= request.policy.maximumQualificationAgeSeconds
        appendCheck(
            &checks,
            passed: qualificationFresh,
            checkID: "qualification-freshness",
            observed: "ageSeconds=\(qualificationAge)",
            expected: "0<=ageSeconds<=\(request.policy.maximumQualificationAgeSeconds)",
            failureCode: "qualification-stale",
            to: &failedCodes
        )

        let runSchemaPassed = request.runResult.schemaVersion == ElectricalSignoffRunResult.currentSchemaVersion
        appendCheck(
            &checks,
            passed: runSchemaPassed,
            checkID: "run-result-schema",
            observed: "schemaVersion=\(request.runResult.schemaVersion)",
            expected: "schemaVersion=\(ElectricalSignoffRunResult.currentSchemaVersion)",
            failureCode: "run-result-schema-unsupported",
            to: &blockedCodes
        )
        let runResultContractPassed: Bool
        do {
            try request.runResult.validate()
            runResultContractPassed = true
        } catch {
            runResultContractPassed = false
        }
        appendCheck(
            &checks,
            passed: runResultContractPassed,
            checkID: "run-result-contract",
            observed: runResultContractPassed ? "valid" : "invalid",
            expected: "validated run-result envelope contract",
            failureCode: "run-result-contract-invalid",
            to: &blockedCodes
        )

        if request.policy.requireProcessQualificationEvidence
            || request.policy.minimumQualificationLevel >= .productionEligible
        {
            let processEvidence = request.processQualificationEvidence
            let processEvidencePassed = processEvidence?.isQualified(
                at: request.evaluatedAt,
                requirePDKScope: true
            ) == true
                && processEvidence?.scope.pdkDigest == request.policy.pdkDigest
            appendCheck(
                &checks,
                passed: processEvidencePassed,
                checkID: "process-qualification-evidence",
                observed: processEvidence.map {
                    "status=\($0.status.rawValue),independent=\($0.independenceVerified),scopePDK=\($0.scope.pdkDigest ?? "<missing>"),blockers=\($0.blockers.sorted().joined(separator: ","))"
                } ?? "missing",
                expected: "qualified, fresh, independent, complete PDK-scoped process evidence",
                failureCode: "process-qualification-evidence-missing-or-invalid",
                to: &blockedCodes
            )
        }

        let integrityEvaluation = evaluateArtifactIntegrity(request)
        let integrityPassed = !request.policy.requireArtifactIntegrityVerification
            || integrityEvaluation.isPassed
        appendCheck(
            &checks,
            passed: integrityPassed,
            checkID: "artifact-integrity",
            observed: integrityEvaluation.observed,
            expected: "every run-result artifact has a matching verified integrity observation",
            failureCode: "artifact-integrity-failed",
            to: &blockedCodes
        )
        if request.policy.requireArtifactIntegrityVerification {
            blockedCodes.append(contentsOf: integrityEvaluation.failureCodes)
        }

        if request.policy.requireArtifactIntegrityVerification,
           request.artifactIntegrity.isEmpty {
            appendCheck(
                &checks,
                passed: false,
                checkID: "artifact-integrity-presence",
                observed: "no verification observations",
                expected: "at least one verified artifact observation",
                failureCode: "artifact-integrity-failed",
                to: &blockedCodes
            )
        }

        /*
         Keep the gate decision independent from the order in which the
         executor collected corner artifacts. Duplicate paths are rejected by
         the evaluator instead of being silently collapsed.
         */
        if request.policy.requireArtifactIntegrityVerification,
           integrityEvaluation.hasDuplicateObservations {
            blockedCodes.append("artifact-integrity-duplicate-observation")
        }

        if request.policy.requireIndependentOracle || request.qualificationSpec?.requireIndependentOracle == true {
            let oraclePassed = request.qualificationReport.qualificationLevel >= .oracleChecked
                && request.qualificationReport.caseResults.allSatisfy {
                    $0.oracle?.isIndependent == true && $0.oracleAgreementPassed == true
                }
            appendCheck(
                &checks,
                passed: oraclePassed,
                checkID: "independent-oracle",
                observed: "oracleAgreementCount=\(request.qualificationReport.oracleAgreementCount)/\(request.qualificationReport.caseCount)",
                expected: "all qualification cases independently correlated",
                failureCode: "independent-oracle-incomplete",
                to: &failedCodes
            )
        }

        var observedCorners = Set(request.runResult.cornerResults.keys)
        var coveragePassed = true
        var resultIdentityPassed = true
        for (cornerID, cornerResults) in request.runResult.cornerResults {
            guard !cornerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                resultIdentityPassed = false
                blockedCodes.append("empty-corner-id")
                continue
            }
            for (axis, envelope) in cornerResults {
                let identity = envelope.schemaVersion == ElectricalSignoffRequest.currentSchemaVersion
                    && envelope.runID == request.runID
                    && envelope.payload.axis == axis
                    && envelope.payload.cornerID == cornerID
                if !identity {
                    resultIdentityPassed = false
                    blockedCodes.append("run-result-identity-mismatch:\(cornerID):\(axis.rawValue)")
                }
            }
        }
        appendCheck(
            &checks,
            passed: resultIdentityPassed,
            checkID: "run-result-identity",
            observed: "validatedCornerResults=\(request.runResult.cornerResults.count)",
            expected: "every envelope binds to the requested run, corner, axis and schema",
            failureCode: "run-result-identity-mismatch",
            to: &blockedCodes
        )
        for cornerID in request.policy.requiredCornerIDs {
            guard let cornerResults = request.runResult.cornerResults[cornerID] else {
                coveragePassed = false
                blockedCodes.append("missing-corner:\(cornerID)")
                checks.append(.init(
                    checkID: "corner-\(cornerID)",
                    passed: false,
                    observed: "missing",
                    expected: "corner result present",
                    failureCode: "missing-corner:\(cornerID)"
                ))
                continue
            }
            observedCorners.insert(cornerID)
            for axis in request.policy.requiredAxes {
                guard let envelope = cornerResults[axis] else {
                    coveragePassed = false
                    blockedCodes.append("missing-axis:\(cornerID):\(axis.rawValue)")
                    checks.append(.init(
                        checkID: "coverage-\(cornerID)-\(axis.rawValue)",
                        passed: false,
                        observed: "missing",
                        expected: "axis result present",
                        failureCode: "missing-axis:\(cornerID):\(axis.rawValue)"
                    ))
                    continue
                }

                let payloadIdentityPassed = envelope.payload.axis == axis
                    && envelope.payload.cornerID == cornerID
                if !payloadIdentityPassed {
                    coveragePassed = false
                    blockedCodes.append("payload-identity-mismatch:\(cornerID):\(axis.rawValue)")
                }
                checks.append(.init(
                    checkID: "coverage-\(cornerID)-\(axis.rawValue)",
                    passed: payloadIdentityPassed,
                    observed: "axis=\(envelope.payload.axis.rawValue),corner=\(envelope.payload.cornerID ?? "<missing>")",
                    expected: "axis=\(axis.rawValue),corner=\(cornerID)",
                    failureCode: payloadIdentityPassed ? nil : "payload-identity-mismatch:\(cornerID):\(axis.rawValue)"
                ))

                if envelope.status != .completed {
                    failedCodes.append("execution-incomplete:\(cornerID):\(axis.rawValue)")
                }
                if envelope.payload.violationCount != 0 {
                    failedCodes.append("violations:\(cornerID):\(axis.rawValue)")
                }
                let provenancePassed = envelope.payload.provenance?.pdkDigest == request.policy.pdkDigest
                if !provenancePassed {
                    blockedCodes.append("provenance-pdk-mismatch:\(cornerID):\(axis.rawValue)")
                }
                let artifactHashesPassed = !request.policy.requireArtifactHashes
                    || !envelope.artifacts.isEmpty && envelope.artifacts.allSatisfy {
                        guard let sha256 = $0.sha256 else { return false }
                        return isSHA256(sha256)
                    }
                if !artifactHashesPassed {
                    blockedCodes.append("artifact-hash-missing:\(cornerID):\(axis.rawValue)")
                }
            }
        }

        appendCheck(
            &checks,
            passed: coveragePassed,
            checkID: "corner-axis-coverage",
            observed: observedCorners.sorted().joined(separator: ","),
            expected: request.policy.requiredCornerIDs.sorted().joined(separator: ","),
            failureCode: "corner-axis-coverage-incomplete",
            to: &blockedCodes
        )

        let aggregateStatusPassed = request.runResult.status == aggregateStatus(
            request.runResult.cornerResults.values.flatMap { $0.values }.map(\.status)
        )
        appendCheck(
            &checks,
            passed: aggregateStatusPassed,
            checkID: "run-result-status",
            observed: request.runResult.status.rawValue,
            expected: "status matches the aggregate corner/axis status",
            failureCode: "run-result-status-mismatch",
            to: &blockedCodes
        )

        let status: ElectricalSignoffReleaseGateResult.Status
        if !blockedCodes.isEmpty {
            status = .blocked
        } else if !failedCodes.isEmpty {
            status = .failed
        } else {
            status = .passed
        }
        return ElectricalSignoffReleaseGateResult(
            runID: request.runID,
            policyID: request.policy.policyID,
            pdkDigest: request.policy.pdkDigest,
            evaluatedAt: request.evaluatedAt,
            status: status,
            checks: checks,
            failureCodes: Array(Set(blockedCodes + failedCodes)).sorted()
        )
    }

    private func appendCheck(
        _ checks: inout [ElectricalSignoffReleaseGateResult.Check],
        passed: Bool,
        checkID: String,
        observed: String,
        expected: String,
        failureCode: String,
        to failureCodes: inout [String]
    ) {
        checks.append(.init(
            checkID: checkID,
            passed: passed,
            observed: observed,
            expected: expected,
            failureCode: passed ? nil : failureCode
        ))
        if !passed {
            failureCodes.append(failureCode)
        }
    }

    private func evaluateArtifactIntegrity(
        _ request: ElectricalSignoffReleaseGateRequest
    ) -> ArtifactIntegrityEvaluation {
        let expectedReferences = request.runResult.cornerResults.values
            .flatMap { $0.values }
            .flatMap(\.artifacts)
        var expectedByPath: [String: XcircuiteFileReference] = [:]
        var duplicateExpectedPaths = Set<String>()
        for reference in expectedReferences {
            if let existing = expectedByPath[reference.path], existing != reference {
                duplicateExpectedPaths.insert(reference.path)
            } else {
                expectedByPath[reference.path] = reference
            }
        }
        let observationsByPath = Dictionary(
            request.artifactIntegrity.map { ($0.path, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var failureCodes: [String] = []
        for path in expectedByPath.keys.sorted() {
            guard let reference = expectedByPath[path],
                  let observation = observationsByPath[path] else {
                failureCodes.append("artifact-integrity-missing:\(path)")
                continue
            }
            guard observation.status == .verified,
                  equalDigest(observation.expectedSHA256, reference.sha256),
                  observation.expectedByteCount == reference.byteCount,
                  equalDigest(observation.actualSHA256, reference.sha256),
                  observation.actualByteCount == reference.byteCount else {
                failureCodes.append("artifact-integrity-reference-mismatch:\(path)")
                continue
            }
        }
        failureCodes.append(contentsOf: duplicateExpectedPaths.sorted().map {
            "artifact-integrity-duplicate-expected-reference:\($0)"
        })
        let duplicateObservations = request.artifactIntegrity.count != observationsByPath.count
        let isPassed = !expectedByPath.isEmpty
            && failureCodes.isEmpty
            && duplicateExpectedPaths.isEmpty
            && !duplicateObservations
        let observed = request.artifactIntegrity.isEmpty
            ? "no verification observations"
            : request.artifactIntegrity
                .map { "\($0.path):\($0.status.rawValue)" }
                .sorted()
                .joined(separator: ",")
        return ArtifactIntegrityEvaluation(
            isPassed: isPassed,
            observed: observed,
            failureCodes: failureCodes,
            hasDuplicateObservations: duplicateObservations
        )
    }

    private struct ArtifactIntegrityEvaluation: Sendable {
        let isPassed: Bool
        let observed: String
        let failureCodes: [String]
        let hasDuplicateObservations: Bool
    }

    private func isSHA256(_ value: String) -> Bool {
        value.count == 64
            && value.unicodeScalars.allSatisfy { scalar in
                (scalar.value >= 48 && scalar.value <= 57)
                    || (scalar.value >= 65 && scalar.value <= 70)
                    || (scalar.value >= 97 && scalar.value <= 102)
            }
    }

    private func equalDigest(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs, let rhs else { return lhs == nil && rhs == nil }
        return lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }

    private func aggregateStatus(
        _ statuses: some Sequence<XcircuiteEngineExecutionStatus>
    ) -> XcircuiteEngineExecutionStatus {
        let statuses = Array(statuses)
        if statuses.contains(.failed) { return .failed }
        if statuses.contains(.blocked) { return .blocked }
        if statuses.contains(.cancelled) { return .cancelled }
        return .completed
    }
}
