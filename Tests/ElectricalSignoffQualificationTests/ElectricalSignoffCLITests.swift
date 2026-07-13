import Foundation
import Testing
import ElectricalSignoffCLI
import ElectricalSignoffCore
import ElectricalSignoffEngine
import ElectricalSignoffQualification
import LogicIR
import PDKCore
import PhysicalDesignCore
import XcircuitePackage

@Suite("Electrical signoff CLI")
struct ElectricalSignoffCLITests {
    @Test("release gate CLI verifies persisted artifact integrity", .timeLimit(.minutes(1)))
    func releaseGateCLIReplaysDecision() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "electrical-release-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            do {
                try FileManager.default.removeItem(at: root)
            } catch {
                Issue.record("Failed to remove CLI fixture root: \(error)")
            }
        }

        let inputURL = root.appending(path: "input.json")
        let reportURL = root.appending(path: "report.json")
        try Data("input".utf8).write(to: inputURL, options: [.atomic])
        try Data("report".utf8).write(to: reportURL, options: [.atomic])

        let hasher = XcircuiteHasher()
        let inputReference = try reference(
            path: "input.json",
            url: inputURL,
            artifactID: "fixture-input",
            hasher: hasher
        )
        let reportReference = try reference(
            path: "report.json",
            url: reportURL,
            artifactID: "electrical-report",
            hasher: hasher
        )
        let request = ElectricalSignoffRequest(
            runID: "release-cli-run",
            inputs: [inputReference],
            design: LogicDesignReference(
                artifact: inputReference,
                topDesignName: "top",
                designDigest: "design"
            ),
            physicalDesign: PhysicalDesignReference(
                layoutArtifact: inputReference,
                topCell: "top",
                layoutDigest: "layout"
            ),
            pdk: PDKReference(
                manifest: inputReference,
                processID: "fixture",
                version: "1",
                digest: "pdk-digest"
            ),
            configuration: ElectricalSignoffConfiguration(
                requiredAxes: [.erc],
                operatingCondition: .typical
            )
        )
        let payload = ElectricalSignoffPayload(
            violationCount: 0,
            axis: .erc,
            provenance: ElectricalSignoffPayload.Provenance(
                designDigest: "design",
                layoutDigest: "layout",
                pdkDigest: "pdk-digest",
                parasiticDigest: nil,
                topCell: "top",
                inputArtifactIDs: ["fixture-input"]
            ),
            cornerID: "typical"
        )
        let metadata = XcircuiteEngineExecutionMetadata(
            engineID: "native",
            implementationID: "native-electrical-signoff",
            implementationVersion: "1",
            startedAt: Date(timeIntervalSince1970: 1),
            completedAt: Date(timeIntervalSince1970: 2)
        )
        let envelope = XcircuiteEngineResultEnvelope(
            schemaVersion: 1,
            runID: request.runID,
            status: .completed,
            artifacts: [reportReference],
            metadata: metadata,
            payload: payload
        )
        let runResult = ElectricalSignoffRunResult(
            runID: request.runID,
            status: .completed,
            axisResults: [.erc: envelope],
            cornerResults: ["typical": [.erc: envelope]]
        )
        let qualificationSpec = ElectricalSignoffQualificationSpec(
            corpusID: "release-cli-corpus",
            corpusVersion: "1",
            pdkDigest: "pdk-digest",
            cases: [ElectricalSignoffQualificationCase(
                caseID: "clean-erc",
                kind: .positive,
                axis: .erc,
                request: request,
                expected: ElectricalSignoffExpectedObservation(
                    status: .completed,
                    violationCount: 0
                )
            )]
        )
        let qualificationReport = ElectricalSignoffQualificationReport(
            corpusID: "release-cli-corpus",
            corpusVersion: "1",
            pdkDigest: "pdk-digest",
            runID: request.runID,
            implementationID: "native-electrical-signoff",
            generatedAt: Date(timeIntervalSince1970: 1),
            completed: true,
            passed: true,
            qualificationLevel: .corpusChecked,
            caseResults: [ElectricalSignoffQualificationCaseResult(
                caseID: "clean-erc",
                axis: .erc,
                cornerID: "typical",
                pdkCornerID: "typical",
                nativeStatus: .completed,
                nativeViolationCount: 0,
                nativeDiagnosticCodes: [],
                nativeMetrics: [],
                nativeArtifacts: [reportReference],
                metricComparisons: [],
                oracle: nil,
                oracleAgreementPassed: nil,
                passed: true,
                failureCodes: []
            )]
        )
        let policy = ElectricalSignoffReleaseGatePolicy(
            policyID: "release-cli-policy",
            pdkDigest: "pdk-digest",
            requiredAxes: [.erc],
            requiredCornerIDs: ["typical"],
            requireIndependentOracle: false,
            requireArtifactIntegrityVerification: true
        )
        let integrity = XcircuiteFileReferenceVerifier().verify(
            reportReference,
            projectRoot: root
        )
        let gateRequest = ElectricalSignoffReleaseGateRequest(
            runID: request.runID,
            runResult: runResult,
            qualificationSpec: qualificationSpec,
            qualificationReport: qualificationReport,
            policy: policy,
            artifactIntegrity: [integrity],
            evaluatedAt: Date(timeIntervalSince1970: 2)
        )
        let gateRequestURL = root.appending(path: "gate-request.json")
        let outputURL = root.appending(path: "gate-result.json")
        try JSONEncoder().encode(gateRequest).write(to: gateRequestURL, options: [.atomic])

        let exitCode = await ElectricalSignoffCLI.run(arguments: [
            "--release-gate-request", gateRequestURL.path,
            "--project-root", root.path,
            "--output", outputURL.path,
        ])

        #expect(exitCode == 0)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let result = try decoder.decode(
            ElectricalSignoffReleaseGateResult.self,
            from: Data(contentsOf: outputURL)
        )
        #expect(result.status == .passed)
        #expect(result.failureCodes.isEmpty)
    }

    private func reference(
        path: String,
        url: URL,
        artifactID: String,
        hasher: XcircuiteHasher
    ) throws -> XcircuiteFileReference {
        XcircuiteFileReference(
            artifactID: artifactID,
            path: path,
            kind: .report,
            format: .json,
            sha256: try hasher.sha256(fileAt: url),
            byteCount: try hasher.byteCount(fileAt: url)
        )
    }
}
