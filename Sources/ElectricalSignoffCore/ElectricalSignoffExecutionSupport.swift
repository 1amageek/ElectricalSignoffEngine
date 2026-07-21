import Foundation
import CircuiteFoundation

public struct ElectricalSignoffExecutionSupport: Sendable {
    public let loader: any ElectricalTopologyLoading
    public let artifactStore: any ElectricalArtifactStoring
    public let clock: any ElectricalClock
    public let implementationVersion: String
    public let implementationBuild: String?

    public init(
        loader: any ElectricalTopologyLoading,
        artifactStore: any ElectricalArtifactStoring = InMemoryElectricalArtifactStore(),
        clock: any ElectricalClock = SystemElectricalClock(),
        implementationVersion: String = "1.0.0",
        implementationBuild: String? = nil
    ) {
        self.loader = loader
        self.artifactStore = artifactStore
        self.clock = clock
        self.implementationVersion = implementationVersion
        self.implementationBuild = implementationBuild
    }

    public init(
        projectRoot: URL = URL(filePath: FileManager.default.currentDirectoryPath),
        verifyIntegrity: Bool = true,
        artifactStore: (any ElectricalArtifactStoring)? = nil,
        clock: any ElectricalClock = SystemElectricalClock(),
        implementationVersion: String = "1.0.0",
        implementationBuild: String? = nil
    ) {
        self.init(
            loader: LocalElectricalTopologyLoader(projectRoot: projectRoot, verifyIntegrity: verifyIntegrity),
            artifactStore: artifactStore ?? InMemoryElectricalArtifactStore(),
            clock: clock,
            implementationVersion: implementationVersion,
            implementationBuild: implementationBuild
        )
    }

    public func load(request: ElectricalSignoffRequest) async throws -> ElectricalSignoffInput {
        try request.validate()
        return try await loader.load(request: request)
    }

    public func completedEnvelope(
        request: ElectricalSignoffRequest,
        axis: ElectricalSignoffAnalysisAxis,
        payload: ElectricalSignoffPayload,
        startedAt: Date
    ) async throws -> ElectricalSignoffResult {
        let data: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            data = try encoder.encode(payload)
        } catch {
            throw ElectricalSignoffError.artifactPersistence("report encoding failed: \(error.localizedDescription)")
        }
        let producer = try producer(axis: axis)
        let artifact = try await artifactStore.store(
            data: data,
            artifactID: artifactID(axis: axis, cornerID: payload.cornerID),
            runID: request.runID,
            axis: axis,
            producer: producer
        )
        return ElectricalSignoffResult(
            schemaVersion: ElectricalSignoffRequest.currentSchemaVersion,
            runID: request.runID,
            status: .completed,
            diagnostics: try diagnostics(from: payload.findings),
            artifacts: [artifact],
            provenance: try provenance(
                axis: axis,
                request: request,
                producer: producer,
                startedAt: startedAt
            ),
            payload: payload
        )
    }

    public func blockedEnvelope(
        request: ElectricalSignoffRequest,
        axis: ElectricalSignoffAnalysisAxis,
        error: Error,
        startedAt: Date
    ) throws -> ElectricalSignoffResult {
        let diagnostic = try diagnostic(for: error, severity: .error)
        return ElectricalSignoffResult(
            schemaVersion: ElectricalSignoffRequest.currentSchemaVersion,
            runID: request.runID,
            status: .blocked,
            diagnostics: [diagnostic],
            provenance: try provenance(
                axis: axis,
                request: request,
                producer: producer(axis: axis),
                startedAt: startedAt
            ),
            payload: ElectricalSignoffPayload(
                violationCount: 0,
                axis: axis,
                findings: [],
                cornerID: request.configuration.operatingCondition.id
            )
        )
    }

    public func failedEnvelope(
        request: ElectricalSignoffRequest,
        axis: ElectricalSignoffAnalysisAxis,
        error: Error,
        startedAt: Date
    ) throws -> ElectricalSignoffResult {
        let diagnostic = try diagnostic(for: error, severity: .error)
        return ElectricalSignoffResult(
            schemaVersion: ElectricalSignoffRequest.currentSchemaVersion,
            runID: request.runID,
            status: .failed,
            diagnostics: [diagnostic],
            provenance: try provenance(
                axis: axis,
                request: request,
                producer: producer(axis: axis),
                startedAt: startedAt
            ),
            payload: ElectricalSignoffPayload(
                violationCount: 0,
                axis: axis,
                findings: [],
                cornerID: request.configuration.operatingCondition.id
            )
        )
    }

    public func provenance(from input: ElectricalSignoffInput) -> ElectricalSignoffPayload.Provenance {
        ElectricalSignoffPayload.Provenance(
            designDigest: input.topology.designDigest,
            layoutDigest: input.topology.layoutDigest,
            pdkDigest: input.topology.pdkDigest,
            parasiticDigest: input.topology.parasiticDigest,
            topCell: input.topology.topCell,
            inputArtifactIDs: input.verifiedReferences.map(\.artifactID)
        )
    }

    private func producer(axis: ElectricalSignoffAnalysisAxis) throws -> ProducerIdentity {
        try ProducerIdentity(
            kind: .engine,
            identifier: "electrical-signoff.\(axis.rawValue)",
            version: implementationVersion,
            build: implementationBuild
                ?? ElectricalSignoffRuntimeIdentity.currentExecutableDigest()
        )
    }

    private func provenance(
        axis: ElectricalSignoffAnalysisAxis,
        request: ElectricalSignoffRequest,
        producer: ProducerIdentity,
        startedAt: Date
    ) throws -> ExecutionProvenance {
        return try ExecutionProvenance(
            producer: producer,
            inputs: request.executionInputArtifacts,
            invocation: try ExecutionInvocation.inProcess(
                entryPoint: "ElectricalSignoffEngine.\(axis.rawValue)"
            ),
            environment: try ElectricalSignoffRuntimeIdentity.environmentFingerprint(
                toolchain: "\(producer.identifier)-\(producer.version)"
            ),
            startedAt: startedAt,
            completedAt: clock.now
        )
    }

    private func artifactID(axis: ElectricalSignoffAnalysisAxis, cornerID: String?) -> String {
        let suffix = cornerID.map { "-\(safeIdentifier($0))" } ?? "-typical"
        return "electrical-signoff-\(axis.rawValue)\(suffix)"
    }

    private func safeIdentifier(_ value: String) -> String {
        let scalars = value.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" ? Character(scalar) : "-"
        }
        let result = String(scalars)
        guard !result.isEmpty else {
            return "condition-\(identifierDigest(value))"
        }
        guard result == value else {
            return "\(result)-\(identifierDigest(value))"
        }
        return result
    }

    private func identifierDigest(_ value: String) -> String {
        String(value.utf8.reduce(into: UInt64(1469598103934665603)) { hash, byte in
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }, radix: 16).prefix(12).description
    }

    private func diagnostics(from findings: [ElectricalSignoffPayload.Finding]) throws -> [DesignDiagnostic] {
        try findings.map { finding in
            try DesignDiagnostic(
                code: DiagnosticCode(rawValue: finding.code),
                severity: finding.severity,
                summary: finding.message,
                detail: finding.entity.map { "entity=\($0)" },
                suggestedActions: finding.suggestedActions.map {
                    SuggestedAction(code: $0, summary: $0)
                }
            )
        }
    }

    private func diagnostic(for error: Error, severity: DiagnosticSeverity) throws -> DesignDiagnostic {
        let code: String
        if let signoffError = error as? ElectricalSignoffError {
            code = diagnosticCode(for: signoffError)
        } else {
            code = "electrical.execution.failed"
        }
        return try DesignDiagnostic(
            code: DiagnosticCode(rawValue: code),
            severity: severity,
            summary: error.localizedDescription,
            suggestedActions: [
                SuggestedAction(code: "inspect_input_artifact_provenance", summary: "Inspect input artifact provenance."),
                SuggestedAction(code: "retain_the_blocked_run_artifacts", summary: "Retain blocked run artifacts.")
            ]
        )
    }

    private func diagnosticCode(for error: ElectricalSignoffError) -> String {
        switch error {
        case .missingTopologyArtifact: return "electrical.topology.missing"
        case .unsupportedTopologyFormat: return "electrical.topology.format-unsupported"
        case .unsupportedSourceFormat: return "electrical.topology.source-format-unsupported"
        case .artifactIntegrity: return "electrical.input.integrity-failed"
        case .malformedTopology: return "electrical.topology.malformed"
        case .schemaVersionUnsupported: return "electrical.topology.schema-unsupported"
        case .digestMismatch: return "electrical.input.digest-mismatch"
        case .missingParasitics: return "electrical.parasitics.missing"
        case .insufficientTopology: return "electrical.topology.insufficient-semantics"
        case .invalidConfiguration: return "electrical.configuration.invalid"
        case .invalidRequest: return "electrical.request.invalid"
        case .conflictingArtifactReferences: return "electrical.input.conflicting-reference"
        case .invalidExecutionResult: return "electrical.execution.result-invalid"
        case .artifactPersistence: return "electrical.artifact.persistence-failed"
        }
    }
}
