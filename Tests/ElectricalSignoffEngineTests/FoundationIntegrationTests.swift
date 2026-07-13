import CircuiteFoundation
import Foundation
import Testing
import XcircuitePackage
@testable import ElectricalSignoffCore
@testable import ElectricalSignoffEngine

@Suite("ElectricalSignoffEngine CircuiteFoundation integration")
struct FoundationIntegrationTests {
    @Test("ElectricalSignoffExecuting refines the shared Engine contract")
    func engineContractIsDirect() {
        let engine = ElectricalSignoffEngine()
        let _: any Engine = engine
    }

    @Test("project artifact references lower to immutable Foundation references")
    func artifactReferenceProjectionPreservesIdentity() throws {
        let reference = XcircuiteFileReference(
            artifactID: "electrical-report",
            path: ".xcircuite/runs/run-1/electrical/report.json",
            kind: .report,
            format: .json,
            sha256: String(repeating: "a", count: 64),
            byteCount: 64
        )

        let foundation = try ElectricalSignoffFoundationArtifactBridge()
            .reference(from: reference)

        #expect(foundation.id.rawValue == "electrical-report")
        #expect(foundation.locator.location.value == reference.path)
        #expect(foundation.locator.kind.rawValue == "electrical-signoff.report")
        #expect(foundation.locator.format == .json)
        #expect(foundation.digest.hexadecimalValue == reference.sha256)
        #expect(foundation.byteCount == 64)
    }

    @Test("invalid project paths are rejected by the Foundation bridge")
    func artifactPathTraversalIsRejected() {
        let reference = XcircuiteFileReference(
            artifactID: "outside",
            path: "../outside.json",
            kind: .report,
            format: .json,
            sha256: String(repeating: "a", count: 64),
            byteCount: 1
        )

        #expect(throws: ElectricalSignoffFoundationArtifactBridgeError.self) {
            try ElectricalSignoffFoundationArtifactBridge().reference(from: reference)
        }
    }

    @Test("result evidence exposes artifacts and typed diagnostics")
    func resultProjectsToFoundationEvidence() throws {
        let report = XcircuiteFileReference(
            artifactID: "electrical-report",
            path: ".xcircuite/runs/run-1/electrical/report.json",
            kind: .report,
            format: .json,
            sha256: String(repeating: "b", count: 64),
            byteCount: 16
        )
        let instant = Date(timeIntervalSince1970: 100)
        let envelope = XcircuiteEngineResultEnvelope(
            schemaVersion: 1,
            runID: "run-1",
            status: .completed,
            diagnostics: [
                XcircuiteEngineDiagnostic(
                    severity: .warning,
                    code: "electrical.test.warning",
                    message: "Review the retained electrical evidence.",
                    entity: "M1",
                    suggestedActions: ["inspect-evidence"]
                )
            ],
            artifacts: [report],
            metadata: XcircuiteEngineExecutionMetadata(
                engineID: "ElectricalSignoffEngine.erc",
                implementationID: "native-erc",
                implementationVersion: "1",
                startedAt: instant,
                completedAt: instant
            ),
            payload: ElectricalSignoffPayload(
                violationCount: 0,
                axis: .erc
            )
        )
        let result = ElectricalSignoffRunResult(
            runID: "run-1",
            status: .completed,
            axisResults: [.erc: envelope]
        )
        let provenance = try ExecutionProvenance(
            producer: try ProducerIdentity(
                kind: .engine,
                identifier: "ElectricalSignoffEngine",
                version: "1"
            ),
            startedAt: instant,
            completedAt: instant
        )

        let evidence = try ElectricalSignoffFoundationEvidence(
            result: result,
            provenance: provenance
        )

        #expect(evidence.artifacts.count == 1)
        #expect(evidence.evidence.artifacts == evidence.artifacts)
        #expect(evidence.diagnostics.count == 1)
        #expect(evidence.diagnostics[0].code.rawValue == "electrical.test.warning")
        #expect(evidence.diagnostics[0].severity == .warning)
        #expect(evidence.diagnostics[0].detail == "entity=M1")
    }
}
