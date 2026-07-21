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
    func resultDirectlyProvidesFoundationEvidence() throws {
        let childProducer = try ProducerIdentity(
            kind: .engine,
            identifier: "electrical-signoff.erc",
            version: "1.0.0",
            build: String(repeating: "a", count: 64)
        )
        let report = try makeArtifact(
            id: "electrical-report",
            path: ".xcircuite/runs/run-1/electrical/report.json",
            role: .output,
            kind: .report,
            format: .json,
            hexadecimalDigest: String(repeating: "b", count: 64),
            byteCount: 16,
            producer: childProducer
        )
        let instant = Date(timeIntervalSince1970: 100)
        let childProvenance = try ExecutionProvenance(
            producer: childProducer,
            invocation: try .inProcess(entryPoint: "ElectricalSignoffEngine.erc"),
            environment: try testEnvironmentFingerprint(),
            startedAt: instant,
            completedAt: instant
        )
        let provenance = try ExecutionProvenance(
            producer: try ProducerIdentity(
                kind: .engine,
                identifier: "native-electrical-signoff",
                version: "1.0.0",
                build: String(repeating: "b", count: 64)
            ),
            supportingTools: [childProducer],
            invocation: try .inProcess(entryPoint: "ElectricalSignoffEngine.execute"),
            environment: try testEnvironmentFingerprint(),
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
            schemaVersion: ElectricalSignoffRunResult.currentSchemaVersion,
            runID: "run-1",
            status: .completed,
            diagnostics: [diagnostic],
            artifacts: [report],
            provenance: childProvenance,
            payload: ElectricalSignoffPayload(
                violationCount: 0,
                axis: .erc
            )
        )
        let result = ElectricalSignoffRunResult(
            runID: "run-1",
            status: .completed,
            axisResults: [.erc: axisResult],
            provenance: provenance
        )
        try result.validate()

        #expect(result.artifacts.count == 1)
        #expect(result.evidence.artifacts == result.artifacts)
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics[0].code.rawValue == "electrical.test.warning")
        #expect(result.diagnostics[0].severity == .warning)
        #expect(result.diagnostics[0].detail == "entity=M1")
    }
}

private func makeArtifact(
    id: String,
    path: String,
    role: ArtifactRole,
    kind: ArtifactKind,
    format: ArtifactFormat,
    hexadecimalDigest: String,
    byteCount: UInt64,
    producer: ProducerIdentity? = nil
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
        byteCount: byteCount,
        producer: producer
    )
}

private func testEnvironmentFingerprint() throws -> ExecutionEnvironmentFingerprint {
    try ExecutionEnvironmentFingerprint(
        platform: "test",
        architecture: "test",
        toolchain: "test",
        environmentDigest: ContentDigest(
            algorithm: .sha256,
            hexadecimalValue: String(repeating: "c", count: 64)
        )
    )
}
