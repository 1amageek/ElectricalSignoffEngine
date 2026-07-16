import CircuiteFoundation
import Foundation

/// Domain-specific result for one electrical signoff axis.
public struct ElectricalSignoffResult: Sendable, Hashable, Codable, ArtifactProducing,
    EvidenceProviding, DiagnosticReporting
{
    public var schemaVersion: Int
    public var runID: String
    public var status: ElectricalSignoffExecutionStatus
    public var diagnostics: [DesignDiagnostic]
    public var artifacts: [ArtifactReference] {
        didSet {
            evidence = EvidenceManifest(
                id: evidence.id,
                provenance: provenance,
                artifacts: artifacts
            )
        }
    }
    public var provenance: ExecutionProvenance {
        didSet {
            evidence = EvidenceManifest(
                id: evidence.id,
                provenance: provenance,
                artifacts: artifacts
            )
        }
    }
    public var payload: ElectricalSignoffPayload
    public private(set) var evidence: EvidenceManifest

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case runID
        case status
        case diagnostics
        case artifacts
        case provenance
        case payload
        case evidence
    }

    public init(
        schemaVersion: Int,
        runID: String,
        status: ElectricalSignoffExecutionStatus,
        diagnostics: [DesignDiagnostic] = [],
        artifacts: [ArtifactReference] = [],
        provenance: ExecutionProvenance,
        payload: ElectricalSignoffPayload
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.status = status
        self.diagnostics = diagnostics
        self.artifacts = artifacts
        self.provenance = provenance
        self.payload = payload
        self.evidence = EvidenceManifest(provenance: provenance, artifacts: artifacts)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        runID = try container.decode(String.self, forKey: .runID)
        status = try container.decode(ElectricalSignoffExecutionStatus.self, forKey: .status)
        diagnostics = try container.decode([DesignDiagnostic].self, forKey: .diagnostics)
        artifacts = try container.decode([ArtifactReference].self, forKey: .artifacts)
        provenance = try container.decode(ExecutionProvenance.self, forKey: .provenance)
        payload = try container.decode(ElectricalSignoffPayload.self, forKey: .payload)
        evidence = try container.decode(EvidenceManifest.self, forKey: .evidence)
        guard evidence.provenance == provenance, evidence.artifacts == artifacts else {
            throw DecodingError.dataCorruptedError(
                forKey: .evidence,
                in: container,
                debugDescription: "Electrical signoff evidence does not match result provenance and artifacts."
            )
        }
    }
}
