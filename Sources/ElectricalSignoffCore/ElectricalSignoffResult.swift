import CircuiteFoundation
import Foundation

/// Domain-specific result for one electrical signoff axis.
public struct ElectricalSignoffResult: Sendable, Hashable, Codable {
    public var schemaVersion: Int
    public var runID: String
    public var status: ElectricalSignoffExecutionStatus
    public var diagnostics: [DesignDiagnostic]
    public var artifacts: [ArtifactReference]
    public var provenance: ExecutionProvenance
    public var payload: ElectricalSignoffPayload

    public init(
        schemaVersion: Int,
        runID: String,
        status: ElectricalSignoffExecutionStatus,
        diagnostics: [DesignDiagnostic] = [],
        artifacts: [ArtifactReference] = [],
        metadata: ExecutionProvenance,
        payload: ElectricalSignoffPayload
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.status = status
        self.diagnostics = diagnostics
        self.artifacts = artifacts
        self.provenance = metadata
        self.payload = payload
    }
}
