import CircuiteFoundation
import ElectricalSignoffCore
import ElectricalSignoffEngine
import Foundation
import Testing

@Suite("ElectricalSignoffEngine CircuiteFoundation integration")
struct FoundationIntegrationTests {
    @Test("ElectricalSignoffExecuting refines the shared Engine contract")
    func engineContractIsDirect() {
        let engine = ElectricalSignoffEngine()
        let _: any Engine = engine
    }

    @Test("electrical report artifacts use the shared Foundation identity")
    func artifactReferenceUsesFoundationIdentity() throws {
        let reference = try makeArtifact(
            id: "electrical-report",
            path: ".xcircuite/runs/run-1/electrical/report.json",
            role: .output,
            kind: .report,
            format: .json,
            hexadecimalDigest: String(repeating: "a", count: 64),
            byteCount: 64
        )

        #expect(reference.id.rawValue == "electrical-report")
        #expect(reference.locator.location.value == ".xcircuite/runs/run-1/electrical/report.json")
        #expect(reference.locator.role == .output)
        #expect(reference.locator.kind == .report)
        #expect(reference.locator.format == .json)
        #expect(reference.digest.hexadecimalValue == String(repeating: "a", count: 64))
        #expect(reference.byteCount == 64)
    }

    @Test("invalid project paths are rejected by the Foundation location")
    func artifactPathTraversalIsRejected() {
        #expect(throws: ArtifactLocationError.self) {
            _ = try ArtifactLocation(workspaceRelativePath: "../outside.json")
        }
    }

    @Test("result evidence exposes artifacts and typed diagnostics")
    func resultProjectsToFoundationEvidence() throws {
        let report = try makeArtifact(
            id: "electrical-report",
            path: ".xcircuite/runs/run-1/electrical/report.json",
            role: .output,
            kind: .report,
            format: .json,
            hexadecimalDigest: String(repeating: "b", count: 64),
            byteCount: 16
        )
        let instant = Date(timeIntervalSince1970: 100)
        let provenance = try ExecutionProvenance(
            producer: try ProducerIdentity(
                kind: .engine,
                identifier: "ElectricalSignoffEngine",
                version: "1"
            ),
            startedAt: instant,
            completedAt: instant
        )
        let diagnostic = DesignDiagnostic(
            code: try DiagnosticCode(rawValue: "electrical.test.warning"),
            severity: .warning,
            summary: "Review the retained electrical evidence.",
            detail: "entity=M1"
        )
        let axisResult = ElectricalSignoffResult(
            schemaVersion: ElectricalSignoffEngineAPI.contractVersion,
            runID: "run-1",
            status: .completed,
            diagnostics: [diagnostic],
            artifacts: [report],
            metadata: provenance,
            payload: ElectricalSignoffPayload(
                violationCount: 0,
                axis: .erc
            )
        )
        let result = ElectricalSignoffRunResult(
            runID: "run-1",
            status: .completed,
            axisResults: [.erc: axisResult]
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

private func makeArtifact(
    id: String,
    path: String,
    role: ArtifactRole,
    kind: ArtifactKind,
    format: ArtifactFormat,
    hexadecimalDigest: String,
    byteCount: UInt64
) throws -> ArtifactReference {
    try ArtifactReference(
        id: ArtifactID(rawValue: id),
        locator: ArtifactLocator(
            location: ArtifactLocation(workspaceRelativePath: path),
            role: role,
            kind: kind,
            format: format
        ),
        digest: ContentDigest(
            algorithm: .sha256,
            hexadecimalValue: hexadecimalDigest
        ),
        byteCount: byteCount
    )
}
