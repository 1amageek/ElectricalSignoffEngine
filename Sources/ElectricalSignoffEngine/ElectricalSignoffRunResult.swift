import Foundation
import CircuiteFoundation
import ElectricalSignoffCore

public struct ElectricalSignoffRunResult: Sendable, Hashable, Codable, ArtifactProducing,
    EvidenceProviding, DiagnosticReporting
{
    public static let currentSchemaVersion = ElectricalSignoffEngineAPI.contractVersion

    public var schemaVersion: Int
    public var runID: String
    public var status: ElectricalSignoffExecutionStatus
    public var axisResults: [ElectricalSignoffAnalysisAxis: ElectricalSignoffResult] {
        didSet { synchronizeEvidence() }
    }
    public var cornerResults: [String: [ElectricalSignoffAnalysisAxis: ElectricalSignoffResult]] {
        didSet { synchronizeEvidence() }
    }
    public var provenance: ExecutionProvenance {
        didSet { synchronizeEvidence() }
    }
    public private(set) var evidence: EvidenceManifest

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case runID
        case status
        case axisResults
        case cornerResults
        case provenance
        case evidence
    }

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        runID: String,
        status: ElectricalSignoffExecutionStatus,
        axisResults: [ElectricalSignoffAnalysisAxis: ElectricalSignoffResult],
        cornerResults: [String: [ElectricalSignoffAnalysisAxis: ElectricalSignoffResult]] = [:],
        provenance: ExecutionProvenance
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.status = status
        self.axisResults = axisResults
        self.cornerResults = cornerResults
        self.provenance = provenance
        self.evidence = EvidenceManifest(
            provenance: provenance,
            artifacts: Self.artifacts(axisResults: axisResults, cornerResults: cornerResults)
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ElectricalSignoffError.schemaVersionUnsupported(schemaVersion)
        }
        runID = try container.decode(String.self, forKey: .runID)
        status = try container.decode(ElectricalSignoffExecutionStatus.self, forKey: .status)
        axisResults = try container.decode([ElectricalSignoffAnalysisAxis: ElectricalSignoffResult].self, forKey: .axisResults)
        cornerResults = try container.decode(
            [String: [ElectricalSignoffAnalysisAxis: ElectricalSignoffResult]].self,
            forKey: .cornerResults
        )
        provenance = try container.decode(ExecutionProvenance.self, forKey: .provenance)
        evidence = try container.decode(EvidenceManifest.self, forKey: .evidence)
        try validate()
    }

    public var artifacts: [ArtifactReference] {
        Self.artifacts(axisResults: axisResults, cornerResults: cornerResults)
    }

    private static func artifacts(
        axisResults: [ElectricalSignoffAnalysisAxis: ElectricalSignoffResult],
        cornerResults: [String: [ElectricalSignoffAnalysisAxis: ElectricalSignoffResult]]
    ) -> [ArtifactReference] {
        var referencesByID: [ArtifactID: ArtifactReference] = [:]
        let axes = axisResults.sorted { $0.key.rawValue < $1.key.rawValue }.map(\.value)
        let corners = cornerResults.sorted { $0.key < $1.key }.flatMap { _, values in
            values.sorted { $0.key.rawValue < $1.key.rawValue }.map(\.value)
        }
        for result in axes + corners {
            for reference in result.artifacts {
                referencesByID[reference.id] = reference
            }
        }
        return referencesByID.values.sorted { $0.id.rawValue < $1.id.rawValue }
    }

    private mutating func synchronizeEvidence() {
        evidence = EvidenceManifest(
            id: evidence.id,
            provenance: provenance,
            artifacts: artifacts
        )
    }

    public var diagnostics: [DesignDiagnostic] {
        allResults.flatMap(\.diagnostics)
    }

    private var allResults: [ElectricalSignoffResult] {
        let axes = axisResults.sorted { $0.key.rawValue < $1.key.rawValue }.map(\.value)
        let corners = cornerResults.sorted { $0.key < $1.key }.flatMap { _, values in
            values.sorted { $0.key.rawValue < $1.key.rawValue }.map(\.value)
        }
        return axes + corners
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ElectricalSignoffError.schemaVersionUnsupported(schemaVersion)
        }
        guard !runID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              runID != ".", runID != "..",
              !runID.contains("/"), !runID.contains("\\") else {
            throw ElectricalSignoffError.invalidRequest("run result run ID is not path-safe")
        }
        guard evidence.provenance == provenance, evidence.artifacts == artifacts else {
            throw ElectricalSignoffError.invalidExecutionResult(
                "run evidence does not match run provenance and artifacts"
            )
        }
        for (axis, envelope) in axisResults {
            try validate(envelope, axis: axis, cornerID: nil)
        }
        for (cornerID, results) in cornerResults {
            guard !cornerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ElectricalSignoffError.invalidExecutionResult("corner ID is empty")
            }
            for (axis, envelope) in results {
                try validate(envelope, axis: axis, cornerID: cornerID)
            }
        }
    }

    private func validate(
        _ envelope: ElectricalSignoffResult,
        axis: ElectricalSignoffAnalysisAxis,
        cornerID: String?
    ) throws {
        guard axis != .aggregate,
              envelope.schemaVersion == Self.currentSchemaVersion,
              envelope.runID == runID,
              envelope.payload.axis == axis,
              cornerID.map({ envelope.payload.cornerID == $0 }) ?? true,
              envelope.payload.violationCount >= 0,
              envelope.evidence.provenance == envelope.provenance,
              envelope.evidence.artifacts == envelope.artifacts,
              envelope.artifacts.allSatisfy({
                  !$0.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && $0.byteCount >= 0
              }) else {
            throw ElectricalSignoffError.invalidExecutionResult(
                "envelope identity or payload contract does not match the run result"
            )
        }
    }
}
