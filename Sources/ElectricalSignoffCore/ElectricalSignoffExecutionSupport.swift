import Foundation
import XcircuitePackage

public struct ElectricalSignoffExecutionSupport: Sendable {
    public let loader: any ElectricalTopologyLoading
    public let artifactStore: any ElectricalArtifactStoring
    public let clock: any ElectricalClock
    public let implementationVersion: String

    public init(
        loader: any ElectricalTopologyLoading,
        artifactStore: any ElectricalArtifactStoring = InMemoryElectricalArtifactStore(),
        clock: any ElectricalClock = SystemElectricalClock(),
        implementationVersion: String = "1"
    ) {
        self.loader = loader
        self.artifactStore = artifactStore
        self.clock = clock
        self.implementationVersion = implementationVersion
    }

    public init(
        projectRoot: URL = URL(filePath: FileManager.default.currentDirectoryPath),
        verifyIntegrity: Bool = true,
        artifactStore: (any ElectricalArtifactStoring)? = nil,
        clock: any ElectricalClock = SystemElectricalClock(),
        implementationVersion: String = "1"
    ) {
        self.init(
            loader: LocalElectricalTopologyLoader(projectRoot: projectRoot, verifyIntegrity: verifyIntegrity),
            artifactStore: artifactStore ?? InMemoryElectricalArtifactStore(),
            clock: clock,
            implementationVersion: implementationVersion
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
    ) async throws -> XcircuiteEngineResultEnvelope<ElectricalSignoffPayload> {
        let data: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            data = try encoder.encode(payload)
        } catch {
            throw ElectricalSignoffError.artifactPersistence("report encoding failed: \(error.localizedDescription)")
        }
        let artifact = try await artifactStore.store(
            data: data,
            artifactID: artifactID(axis: axis, cornerID: payload.cornerID),
            runID: request.runID,
            axis: axis
        )
        return XcircuiteEngineResultEnvelope(
            schemaVersion: ElectricalSignoffRequest.currentSchemaVersion,
            runID: request.runID,
            status: .completed,
            diagnostics: diagnostics(from: payload.findings),
            artifacts: [artifact],
            metadata: metadata(axis: axis, runID: request.runID, startedAt: startedAt),
            payload: payload
        )
    }

    public func blockedEnvelope(
        request: ElectricalSignoffRequest,
        axis: ElectricalSignoffAnalysisAxis,
        error: Error,
        startedAt: Date
    ) -> XcircuiteEngineResultEnvelope<ElectricalSignoffPayload> {
        let diagnostic = diagnostic(for: error, severity: .error)
        return XcircuiteEngineResultEnvelope(
            schemaVersion: ElectricalSignoffRequest.currentSchemaVersion,
            runID: request.runID,
            status: .blocked,
            diagnostics: [diagnostic],
            metadata: metadata(axis: axis, runID: request.runID, startedAt: startedAt),
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
    ) -> XcircuiteEngineResultEnvelope<ElectricalSignoffPayload> {
        let diagnostic = diagnostic(for: error, severity: .error)
        return XcircuiteEngineResultEnvelope(
            schemaVersion: ElectricalSignoffRequest.currentSchemaVersion,
            runID: request.runID,
            status: .failed,
            diagnostics: [diagnostic],
            metadata: metadata(axis: axis, runID: request.runID, startedAt: startedAt),
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
            inputArtifactIDs: input.verifiedReferences.compactMap(\.artifactID)
        )
    }

    private func metadata(axis: ElectricalSignoffAnalysisAxis, runID: String, startedAt: Date) -> XcircuiteEngineExecutionMetadata {
        XcircuiteEngineExecutionMetadata(
            engineID: "ElectricalSignoffEngine.\(axis.rawValue)",
            implementationID: "native-\(axis.rawValue)",
            implementationVersion: implementationVersion,
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
        String(XcircuiteHasher().sha256(data: Data(value.utf8)).prefix(12))
    }

    private func diagnostics(from findings: [ElectricalSignoffPayload.Finding]) -> [XcircuiteEngineDiagnostic] {
        findings.map { finding in
            XcircuiteEngineDiagnostic(
                severity: finding.severity,
                code: finding.code,
                message: finding.message,
                entity: finding.entity,
                suggestedActions: finding.suggestedActions
            )
        }
    }

    private func diagnostic(for error: Error, severity: XcircuiteEngineDiagnosticSeverity) -> XcircuiteEngineDiagnostic {
        let code: String
        if let signoffError = error as? ElectricalSignoffError {
            code = diagnosticCode(for: signoffError)
        } else {
            code = "electrical.execution.failed"
        }
        return XcircuiteEngineDiagnostic(
            severity: severity,
            code: code,
            message: error.localizedDescription,
            suggestedActions: ["inspect_input_artifact_provenance", "retain_the_blocked_run_artifacts"]
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
