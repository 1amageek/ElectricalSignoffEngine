import Foundation
import ElectricalSignoffCore
import ElectricalSignoffCLI
import ElectricalSignoffEngine
import ElectricalSignoffQualification
import LogicIR
import PDKCore
import PhysicalDesignCore
import Testing
import ToolQualification
import XcircuitePackage

@Suite("Electrical signoff process qualification")
struct ElectricalSignoffProcessQualificationTests {
    @Test("process qualification promotes only complete PDK-scoped evidence", .timeLimit(.minutes(1)))
    func promotesCompleteEvidence() throws {
        let request = makeRequest()
        let now = Date(timeIntervalSince1970: 1_000)
        let processRequest = makeProcessQualificationRequest(
            request: request,
            evaluatedAt: now,
            approvalArtifacts: [artifact(id: "human-approval", character: "e")]
        )

        let result = try DefaultElectricalSignoffProcessQualificationEvaluator().evaluate(processRequest)

        #expect(result.qualified)
        #expect(result.status == .qualified)
        #expect(result.evidence.isQualified(at: now, requirePDKScope: true))
        #expect(result.evidence.independenceVerified)
        #expect(result.blockers.isEmpty)
    }

    @Test("process qualification blocks when human approval or artifact identity is missing", .timeLimit(.minutes(1)))
    func blocksIncompleteEvidence() throws {
        let request = makeRequest()
        let processRequest = makeProcessQualificationRequest(
            request: request,
            evaluatedAt: Date(timeIntervalSince1970: 1_000),
            approvalArtifacts: [],
            healthArtifacts: [XcircuiteFileReference(
                artifactID: "tampered-health",
                path: "qualification/health.json",
                kind: .report,
                format: .json,
                sha256: "invalid",
                byteCount: 1
            )]
        )

        let result = try DefaultElectricalSignoffProcessQualificationEvaluator().evaluate(processRequest)

        #expect(!result.qualified)
        #expect(result.status == .blocked)
        #expect(result.blockers.contains("typed-process-evidence-invalid"))
        #expect(result.evidence.status == .blocked)
    }

    @Test("process qualification CLI returns a reproducible evidence envelope", .timeLimit(.minutes(1)))
    func processQualificationCLI() async throws {
        let root = URL(filePath: NSTemporaryDirectory()).appending(path: "electrical-process-qualification-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let processRequest = try materializeArtifactReferences(
            makeProcessQualificationRequest(
                request: makeRequest(),
                evaluatedAt: Date(timeIntervalSince1970: 1_000),
                approvalArtifacts: [artifact(id: "human-approval", character: "e")]
            ),
            root: root
        )
        let requestURL = root.appending(path: "process-qualification.json")
        let outputURL = root.appending(path: "process-qualification-result.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(processRequest).write(to: requestURL)

        let exitCode = await ElectricalSignoffCLI.run(arguments: [
            "--process-qualification-request",
            requestURL.path(percentEncoded: false),
            "--project-root",
            root.path(percentEncoded: false),
            "--output",
            outputURL.path(percentEncoded: false),
        ])

        #expect(exitCode == 0)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let result = try decoder.decode(
            ElectricalSignoffProcessQualificationResult.self,
            from: Data(contentsOf: outputURL)
        )
        #expect(result.qualified)
        #expect(result.evidence.qualificationID == processRequest.qualificationID)
    }

    private func makeProcessQualificationRequest(
        request: ElectricalSignoffRequest,
        evaluatedAt: Date,
        approvalArtifacts: [XcircuiteFileReference],
        healthArtifacts: [XcircuiteFileReference]? = nil
    ) -> ElectricalSignoffProcessQualificationRequest {
        let caseID = "clean-erc"
        let condition = request.configuration.operatingCondition
        let specification = ElectricalSignoffQualificationSpec(
            corpusID: "electrical-process-corpus",
            corpusVersion: "1",
            pdkDigest: request.pdk.digest,
            requireIndependentOracle: true,
            cases: [ElectricalSignoffQualificationCase(
                caseID: caseID,
                kind: .positive,
                axis: .erc,
                request: request,
                expected: ElectricalSignoffExpectedObservation(status: .completed, violationCount: 0)
            )]
        )
        let oracle = ElectricalSignoffOracleObservation(
            oracleID: "independent-electrical-oracle",
            toolVersion: "oracle-1",
            pdkDigest: request.pdk.digest,
            status: .completed,
            violationCount: 0
        )
        let result = ElectricalSignoffQualificationCaseResult(
            caseID: caseID,
            axis: .erc,
            cornerID: condition.id,
            pdkCornerID: condition.pdkCornerID,
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
        let report = ElectricalSignoffQualificationReport(
            corpusID: specification.corpusID,
            corpusVersion: specification.corpusVersion,
            pdkDigest: specification.pdkDigest,
            runID: request.runID,
            implementationID: "native-electrical-signoff",
            generatedAt: Date(timeIntervalSince1970: 900),
            completed: true,
            passed: true,
            qualificationLevel: .oracleChecked,
            caseResults: [result]
        )
        let scope = ToolQualificationScope(
            implementationID: "native-electrical-signoff",
            binaryDigest: String(repeating: "b", count: 64),
            algorithmVersion: "1",
            processProfileID: request.pdk.processID,
            deckDigest: request.pdk.digest,
            pdkID: request.pdk.processID,
            pdkDigest: request.pdk.digest
        )
        let corpusArtifact = artifact(id: "corpus-report", character: "a")
        let oracleArtifact = artifact(id: "oracle-observation", character: "b")
        let resolvedHealthArtifacts = healthArtifacts ?? [artifact(id: "health-check", character: "c")]
        let evidenceArtifacts = [corpusArtifact, oracleArtifact]
            + resolvedHealthArtifacts
            + approvalArtifacts
        let processEvidence = ToolProcessQualificationEvidenceBuildRequest(
            qualificationID: "electrical-process-qualification",
            toolID: "native-electrical-signoff",
            scope: scope,
            corpusEvidence: [evidence(
                id: "corpus-evidence",
                kind: .corpus,
                artifact: corpusArtifact,
                scope: scope
            )],
            oracleEvidence: [evidence(
                id: "oracle-evidence",
                kind: .oracle,
                artifact: oracleArtifact,
                scope: scope
            )],
            healthEvidence: resolvedHealthArtifacts.map {
                evidence(
                    id: "health-evidence-\($0.artifactID ?? $0.path)",
                    kind: .healthCheck,
                    artifact: $0,
                    scope: scope
                )
            },
            approvalEvidence: approvalArtifacts.map {
                evidence(
                    id: "approval-evidence-\($0.artifactID ?? $0.path)",
                    kind: .productionApproval,
                    artifact: $0,
                    scope: scope
                )
            },
            evidenceArtifacts: evidenceArtifacts,
            independenceVerified: true,
            qualifiedAt: Date(timeIntervalSince1970: 900),
            expiresAt: Date(timeIntervalSince1970: 2_000)
        )
        return ElectricalSignoffProcessQualificationRequest(
            qualificationID: "electrical-process-qualification",
            toolID: "native-electrical-signoff",
            qualificationSpec: specification,
            qualificationReport: report,
            scope: scope,
            processEvidence: processEvidence,
            qualifiedAt: Date(timeIntervalSince1970: 900),
            expiresAt: Date(timeIntervalSince1970: 2_000),
            evaluatedAt: evaluatedAt
        )
    }

    private func evidence(
        id: String,
        kind: ToolEvidenceKind,
        artifact: XcircuiteFileReference,
        scope: ToolQualificationScope
    ) -> ToolEvidence {
        ToolEvidence(
            evidenceID: id,
            kind: kind,
            artifact: artifact,
            qualification: ToolEvidenceQualificationSummary(
                qualified: true,
                observedCounts: ["evidence": 1],
                scope: scope,
                qualificationID: "electrical-process-qualification",
                independenceVerified: true
            ),
            checkedAt: Date(timeIntervalSince1970: 1_000)
        )
    }

    private func makeRequest() -> ElectricalSignoffRequest {
        let reference = XcircuiteFileReference(path: "fixture.json", kind: .other, format: .json)
        return ElectricalSignoffRequest(
            runID: "qualification-run",
            inputs: [reference],
            design: LogicDesignReference(artifact: reference, topDesignName: "top", designDigest: "design"),
            physicalDesign: PhysicalDesignReference(layoutArtifact: reference, topCell: "top", layoutDigest: "layout"),
            pdk: PDKReference(manifest: reference, processID: "fixture", version: "1", digest: "pdk-digest"),
            configuration: ElectricalSignoffConfiguration(requiredAxes: [.erc])
        )
    }

    private func artifact(id: String, character: Character) -> XcircuiteFileReference {
        XcircuiteFileReference(
            artifactID: id,
            path: "qualification/\(id).json",
            kind: .report,
            format: .json,
            sha256: String(repeating: character, count: 64),
            byteCount: 1
        )
    }

    private func materializeArtifactReferences(
        _ request: ElectricalSignoffProcessQualificationRequest,
        root: URL
    ) throws -> ElectricalSignoffProcessQualificationRequest {
        let store = XcircuitePackageStore()
        var materialized = request
        var processEvidence = request.processEvidence
        processEvidence.corpusEvidence = try materializeEvidence(
            processEvidence.corpusEvidence,
            root: root,
            store: store
        )
        processEvidence.oracleEvidence = try materializeEvidence(
            processEvidence.oracleEvidence,
            root: root,
            store: store
        )
        processEvidence.healthEvidence = try materializeEvidence(
            processEvidence.healthEvidence,
            root: root,
            store: store
        )
        processEvidence.approvalEvidence = try materializeEvidence(
            processEvidence.approvalEvidence,
            root: root,
            store: store
        )
        processEvidence.evidenceArtifacts = try materialize(
            processEvidence.evidenceArtifacts,
            root: root,
            store: store
        )
        processEvidence.corpusEvidence = rebindEvidence(
            processEvidence.corpusEvidence,
            artifacts: processEvidence.evidenceArtifacts
        )
        processEvidence.oracleEvidence = rebindEvidence(
            processEvidence.oracleEvidence,
            artifacts: processEvidence.evidenceArtifacts
        )
        processEvidence.healthEvidence = rebindEvidence(
            processEvidence.healthEvidence,
            artifacts: processEvidence.evidenceArtifacts
        )
        processEvidence.approvalEvidence = rebindEvidence(
            processEvidence.approvalEvidence,
            artifacts: processEvidence.evidenceArtifacts
        )
        materialized.processEvidence = processEvidence
        return materialized
    }

    private func rebindEvidence(
        _ evidence: [ToolEvidence],
        artifacts: [XcircuiteFileReference]
    ) -> [ToolEvidence] {
        let artifactsByKey = Dictionary(
            uniqueKeysWithValues: artifacts.map {
                ("\($0.artifactID ?? "")|\($0.path)", $0)
            }
        )
        return evidence.map { item in
            var rebound = item
            if let artifact = item.artifact {
                let key = "\(artifact.artifactID ?? "")|\(artifact.path)"
                rebound.artifact = artifactsByKey[key]
            }
            return rebound
        }
    }

    private func materializeEvidence(
        _ evidence: [ToolEvidence],
        root: URL,
        store: XcircuitePackageStore
    ) throws -> [ToolEvidence] {
        try evidence.map { item in
            var materialized = item
            if let artifact = item.artifact {
                materialized.artifact = try materialize(
                    [artifact],
                    root: root,
                    store: store
                )[0]
            }
            return materialized
        }
    }

    private func materialize(
        _ references: [XcircuiteFileReference],
        root: URL,
        store: XcircuitePackageStore
    ) throws -> [XcircuiteFileReference] {
        try references.map { reference in
            let url = root.appending(path: reference.path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data: Data
            if reference.artifactID == "human-approval" {
                data = try JSONEncoder().encode(XcircuiteApprovalRecord(
                    runID: "qualification-run",
                    stageID: ElectricalSignoffProcessQualificationRequest.requiredApprovalStageID,
                    verdict: .approved,
                    reviewer: "human-reviewer",
                    reviewerKind: .human,
                    createdAt: Date(timeIntervalSince1970: 950)
                ))
            } else {
                data = Data("retained-artifact".utf8)
            }
            try data.write(to: url)
            return try store.fileReference(
                forProjectRelativePath: reference.path,
                artifactID: reference.artifactID,
                kind: reference.kind,
                format: reference.format,
                inProjectAt: root
            )
        }
    }
}
