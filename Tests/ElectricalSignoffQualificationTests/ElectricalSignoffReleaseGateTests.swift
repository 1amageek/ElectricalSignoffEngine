import Foundation
import Testing
import ElectricalSignoffCore
import ElectricalSignoffEngine
import ElectricalSignoffQualification
import LogicIR
import PDKCore
import PhysicalDesignCore
import ToolQualification
import XcircuitePackage

@Suite("Electrical signoff release gate")
struct ElectricalSignoffReleaseGateTests {
    @Test("release gate requires every axis and corner to carry hashed evidence", .timeLimit(.minutes(1)))
    func passesWithCompleteEvidence() throws {
        let request = makeRequest()
        let specification = makeQualificationSpec(request: request)
        let result = try DefaultElectricalSignoffReleaseGateEvaluator().evaluate(
            ElectricalSignoffReleaseGateRequest(
                runID: request.runID,
                runResult: makeRunResult(request: request),
                qualificationSpec: specification,
                qualificationReport: makeQualificationReport(runID: request.runID),
                policy: makePolicy(),
                evaluatedAt: Date(timeIntervalSince1970: 3)
            )
        )

        #expect(result.status == .passed)
        #expect(result.isReleaseReady)
        #expect(result.failureCodes.isEmpty)
    }

    @Test("process-qualified policies require independent PDK-scoped evidence", .timeLimit(.minutes(1)))
    func blocksMissingProcessQualificationEvidence() throws {
        let request = makeRequest()
        let specification = makeQualificationSpec(request: request)
        var policy = makePolicy()
        policy.requireProcessQualificationEvidence = true
        let result = try DefaultElectricalSignoffReleaseGateEvaluator().evaluate(
            ElectricalSignoffReleaseGateRequest(
                runID: request.runID,
                runResult: makeRunResult(request: request),
                qualificationSpec: specification,
                qualificationReport: makeQualificationReport(runID: request.runID),
                policy: policy,
                evaluatedAt: Date(timeIntervalSince1970: 3)
            )
        )

        #expect(result.status == .blocked)
        #expect(result.failureCodes.contains("process-qualification-evidence-missing-or-invalid"))
    }

    @Test("process-qualified policies accept fresh independent PDK-scoped evidence", .timeLimit(.minutes(1)))
    func acceptsProcessQualificationEvidence() throws {
        let request = makeRequest()
        let specification = makeQualificationSpec(request: request)
        var policy = makePolicy()
        policy.requireProcessQualificationEvidence = true
        let evidence = ToolProcessQualificationEvidence(
            qualificationID: "electrical-process-qualification-v1",
            toolID: "native-electrical-signoff",
            scope: ToolQualificationScope(
                implementationID: "native-electrical-signoff",
                binaryDigest: "binary-digest",
                algorithmVersion: "1",
                processProfileID: "fixture",
                deckDigest: "deck-digest",
                pdkID: "fixture-pdk",
                pdkDigest: request.pdk.digest
            ),
            status: .qualified,
            corpusEvidenceIDs: ["electrical-corpus-evidence"],
            oracleEvidenceIDs: ["electrical-oracle-evidence"],
            healthEvidenceIDs: ["electrical-health-evidence"],
            approvalEvidenceIDs: ["electrical-approval-evidence"],
            evidenceArtifactIDs: ["electrical-process-qualification-record"],
            independenceVerified: true,
            qualifiedAt: Date(timeIntervalSince1970: 2),
            expiresAt: Date(timeIntervalSince1970: 100)
        )
        let result = try DefaultElectricalSignoffReleaseGateEvaluator().evaluate(
            ElectricalSignoffReleaseGateRequest(
                runID: request.runID,
                runResult: makeRunResult(request: request),
                qualificationSpec: specification,
                qualificationReport: makeQualificationReport(runID: request.runID),
                processQualificationEvidence: evidence,
                policy: policy,
                evaluatedAt: Date(timeIntervalSince1970: 3)
            )
        )

        #expect(result.status == .passed)
        #expect(result.failureCodes.isEmpty)
    }

    @Test("release gate blocks missing corner evidence", .timeLimit(.minutes(1)))
    func blocksMissingCorner() throws {
        let request = makeRequest()
        let specification = makeQualificationSpec(request: request)
        var runResult = makeRunResult(request: request)
        runResult.cornerResults.removeValue(forKey: "fast")
        let result = try DefaultElectricalSignoffReleaseGateEvaluator().evaluate(
            ElectricalSignoffReleaseGateRequest(
                runID: request.runID,
                runResult: runResult,
                qualificationSpec: specification,
                qualificationReport: makeQualificationReport(runID: request.runID),
                policy: makePolicy(),
                evaluatedAt: Date(timeIntervalSince1970: 3)
            )
        )

        #expect(result.status == .blocked)
        #expect(result.failureCodes.contains("missing-corner:fast"))
    }

    @Test("release gate fails non-zero electrical violations", .timeLimit(.minutes(1)))
    func failsViolations() throws {
        let request = makeRequest()
        let specification = makeQualificationSpec(request: request)
        var runResult = makeRunResult(request: request)
        let envelope = try #require(runResult.cornerResults["slow"]?[.erc])
        var payload = envelope.payload
        payload.violationCount = 1
        runResult.cornerResults["slow"]?[.erc] = XcircuiteEngineResultEnvelope(
            schemaVersion: envelope.schemaVersion,
            runID: envelope.runID,
            status: envelope.status,
            diagnostics: envelope.diagnostics,
            artifacts: envelope.artifacts,
            metadata: envelope.metadata,
            payload: payload
        )
        let result = try DefaultElectricalSignoffReleaseGateEvaluator().evaluate(
            ElectricalSignoffReleaseGateRequest(
                runID: request.runID,
                runResult: runResult,
                qualificationSpec: specification,
                qualificationReport: makeQualificationReport(runID: request.runID),
                policy: makePolicy(),
                evaluatedAt: Date(timeIntervalSince1970: 3)
            )
        )

        #expect(result.status == .failed)
        #expect(result.failureCodes.contains("violations:slow:erc"))
    }

    @Test("release gate rejects stale qualification evidence", .timeLimit(.minutes(1)))
    func rejectsStaleQualification() throws {
        let request = makeRequest()
        let specification = makeQualificationSpec(request: request)
        var policy = makePolicy()
        policy.maximumQualificationAgeSeconds = 1
        let result = try DefaultElectricalSignoffReleaseGateEvaluator().evaluate(
            ElectricalSignoffReleaseGateRequest(
                runID: request.runID,
                runResult: makeRunResult(request: request),
                qualificationSpec: specification,
                qualificationReport: makeQualificationReport(runID: request.runID),
                policy: policy,
                evaluatedAt: Date(timeIntervalSince1970: 4)
            )
        )

        #expect(result.status == .failed)
        #expect(result.failureCodes.contains("qualification-stale"))
    }

    @Test("release gate requires integrity observations to cover run artifacts", .timeLimit(.minutes(1)))
    func requiresArtifactIntegrityCoverage() throws {
        let request = makeRequest()
        let specification = makeQualificationSpec(request: request)
        var policy = makePolicy()
        policy.requireArtifactIntegrityVerification = true
        let result = try DefaultElectricalSignoffReleaseGateEvaluator().evaluate(
            ElectricalSignoffReleaseGateRequest(
                runID: request.runID,
                runResult: makeRunResult(request: request),
                qualificationSpec: specification,
                qualificationReport: makeQualificationReport(runID: request.runID),
                policy: policy,
                artifactIntegrity: [XcircuiteFileReferenceIntegrity(
                    status: .verified,
                    path: "report.json",
                    expectedSHA256: String(repeating: "b", count: 64),
                    actualSHA256: String(repeating: "b", count: 64),
                    expectedByteCount: 1,
                    actualByteCount: 1,
                    message: "fixture"
                )],
                evaluatedAt: Date(timeIntervalSince1970: 3)
            )
        )

        #expect(result.status == .blocked)
        #expect(result.failureCodes.contains("artifact-integrity-reference-mismatch:report.json"))
    }

    @Test("release gate rejects conflicting references for one artifact path", .timeLimit(.minutes(1)))
    func rejectsConflictingExpectedArtifactReferences() throws {
        let request = makeRequest()
        let specification = makeQualificationSpec(request: request)
        var runResult = makeRunResult(request: request)
        var fastERC = try #require(runResult.cornerResults["fast"]?[.erc])
        var conflictingArtifact = try #require(fastERC.artifacts.first)
        conflictingArtifact.sha256 = String(repeating: "c", count: 64)
        fastERC.artifacts = [conflictingArtifact]
        runResult.cornerResults["fast"]?[.erc] = fastERC
        var policy = makePolicy()
        policy.requireArtifactIntegrityVerification = true
        let result = try DefaultElectricalSignoffReleaseGateEvaluator().evaluate(
            ElectricalSignoffReleaseGateRequest(
                runID: request.runID,
                runResult: runResult,
                qualificationSpec: specification,
                qualificationReport: makeQualificationReport(runID: request.runID),
                policy: policy,
                evaluatedAt: Date(timeIntervalSince1970: 3)
            )
        )

        #expect(result.status == .blocked)
        #expect(result.failureCodes.contains("artifact-integrity-duplicate-expected-reference:report.json"))
    }

    @Test("release gate blocks qualification reports without exact corpus coverage", .timeLimit(.minutes(1)))
    func blocksIncompleteQualificationCoverage() throws {
        let request = makeRequest()
        let specification = makeQualificationSpec(request: request)
        var report = makeQualificationReport(runID: request.runID)
        report.caseResults = []
        let result = try DefaultElectricalSignoffReleaseGateEvaluator().evaluate(
            ElectricalSignoffReleaseGateRequest(
                runID: request.runID,
                runResult: makeRunResult(request: request),
                qualificationSpec: specification,
                qualificationReport: report,
                policy: makePolicy(),
                evaluatedAt: Date(timeIntervalSince1970: 3)
            )
        )

        #expect(result.status == .blocked)
        #expect(result.failureCodes.contains("missing-qualification-case:release-clean"))
        #expect(result.failureCodes.contains("qualification-case-coverage-incomplete"))
    }

    private func makePolicy() -> ElectricalSignoffReleaseGatePolicy {
        ElectricalSignoffReleaseGatePolicy(
            policyID: "electrical-release-v1",
            pdkDigest: "pdk-digest",
            requiredAxes: [.erc, .esd],
            requiredCornerIDs: ["slow", "fast"],
            requireIndependentOracle: true,
            requireArtifactIntegrityVerification: false
        )
    }

    private func makeRequest() -> ElectricalSignoffRequest {
        let reference = XcircuiteFileReference(
            artifactID: "fixture-input",
            path: "fixture.json",
            kind: .other,
            format: .json,
            sha256: String(repeating: "a", count: 64)
        )
        return ElectricalSignoffRequest(
            runID: "release-run",
            inputs: [reference],
            design: LogicDesignReference(artifact: reference, topDesignName: "top", designDigest: "design"),
            physicalDesign: PhysicalDesignReference(layoutArtifact: reference, topCell: "top", layoutDigest: "layout"),
            pdk: PDKReference(manifest: reference, processID: "fixture", version: "1", digest: "pdk-digest"),
            configuration: ElectricalSignoffConfiguration(
                requiredAxes: [.erc, .esd],
                operatingConditions: [
                    ElectricalOperatingCondition(id: "slow", pdkCornerID: "slow", temperatureC: 125, supplyVoltageScale: 0.9, activityScale: 1),
                    ElectricalOperatingCondition(id: "fast", pdkCornerID: "fast", temperatureC: -40, supplyVoltageScale: 1.1, activityScale: 1),
                ]
            )
        )
    }

    private func makeRunResult(request: ElectricalSignoffRequest) -> ElectricalSignoffRunResult {
        let metadata = XcircuiteEngineExecutionMetadata(
            engineID: "native",
            implementationID: "native-electrical-signoff",
            implementationVersion: "1",
            startedAt: Date(timeIntervalSince1970: 1),
            completedAt: Date(timeIntervalSince1970: 2)
        )
        let artifact = XcircuiteFileReference(
            artifactID: "electrical-report",
            path: "report.json",
            kind: .report,
            format: .json,
            sha256: String(repeating: "b", count: 64)
        )
        var corners: [String: [ElectricalSignoffAnalysisAxis: XcircuiteEngineResultEnvelope<ElectricalSignoffPayload>]] = [:]
        for corner in request.configuration.operatingConditions {
            for axis in request.configuration.requiredAxes {
                let payload = ElectricalSignoffPayload(
                    violationCount: 0,
                    axis: axis,
                    provenance: ElectricalSignoffPayload.Provenance(
                        designDigest: "design",
                        layoutDigest: "layout",
                        pdkDigest: "pdk-digest",
                        parasiticDigest: nil,
                        topCell: "top",
                        inputArtifactIDs: ["fixture-input"]
                    ),
                    cornerID: corner.id
                )
                corners[corner.id, default: [:]][axis] = XcircuiteEngineResultEnvelope(
                    schemaVersion: 1,
                    runID: request.runID,
                    status: .completed,
                    artifacts: [artifact],
                    metadata: metadata,
                    payload: payload
                )
            }
        }
        let aggregate = corners["slow"] ?? [:]
        return ElectricalSignoffRunResult(
            runID: request.runID,
            status: .completed,
            axisResults: aggregate,
            cornerResults: corners
        )
    }

    private func makeQualificationReport(runID: String) -> ElectricalSignoffQualificationReport {
        let oracle = ElectricalSignoffOracleObservation(
            oracleID: "independent-oracle",
            toolVersion: "1",
            pdkDigest: "pdk-digest",
            status: .completed,
            violationCount: 0
        )
        let caseResult = ElectricalSignoffQualificationCaseResult(
            caseID: "release-clean",
            axis: .erc,
            cornerID: "slow",
            pdkCornerID: "slow",
            nativeStatus: .completed,
            nativeViolationCount: 0,
            nativeDiagnosticCodes: [],
            nativeMetrics: [],
            nativeArtifacts: [],
            metricComparisons: [],
            oracle: oracle,
            oracleAgreementPassed: true,
            passed: true,
            failureCodes: []
        )
        return ElectricalSignoffQualificationReport(
            corpusID: "electrical-release-corpus",
            corpusVersion: "1",
            pdkDigest: "pdk-digest",
            runID: runID,
            implementationID: "native-electrical-signoff",
            generatedAt: Date(timeIntervalSince1970: 2),
            completed: true,
            passed: true,
            qualificationLevel: .oracleChecked,
            caseResults: [caseResult]
        )
    }

    private func makeQualificationSpec(request: ElectricalSignoffRequest) -> ElectricalSignoffQualificationSpec {
        ElectricalSignoffQualificationSpec(
            corpusID: "electrical-release-corpus",
            corpusVersion: "1",
            pdkDigest: request.pdk.digest,
            requireIndependentOracle: true,
            cases: [ElectricalSignoffQualificationCase(
                caseID: "release-clean",
                kind: .positive,
                axis: .erc,
                request: request,
                expected: ElectricalSignoffExpectedObservation(status: .completed, violationCount: 0)
            )]
        )
    }
}
