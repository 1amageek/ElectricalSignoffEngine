import CircuiteFoundation
import ElectricalSignoffCore
import Foundation

/// Canonical cross-engine evidence view for an electrical signoff run.
///
/// The rich electrical result remains owned by the electrical domain. This
/// projection gives agents, flow policy, and human review a stable Foundation
/// representation without making Foundation depend on either package.
public struct ElectricalSignoffFoundationEvidence: Sendable, Hashable, Codable, ArtifactProducing, EvidenceProviding, DiagnosticReporting {
    public let artifacts: [ArtifactReference]
    public let evidence: EvidenceManifest
    public let diagnostics: [DesignDiagnostic]

    public init(
        result: ElectricalSignoffRunResult,
        provenance: ExecutionProvenance
    ) throws {
        try result.validate()
        let references = try Self.uniqueArtifacts(from: result)
        var foundationArtifacts: [ArtifactReference] = []
        foundationArtifacts.reserveCapacity(references.count)
        for reference in references {
            foundationArtifacts.append(reference)
        }

        self.artifacts = foundationArtifacts.sorted {
            if $0.locator.location.value == $1.locator.location.value {
                return $0.id.rawValue < $1.id.rawValue
            }
            return $0.locator.location.value < $1.locator.location.value
        }
        self.evidence = EvidenceManifest(
            provenance: provenance,
            artifacts: self.artifacts
        )
        self.diagnostics = try Self.diagnostics(from: result)
    }

    private static func uniqueArtifacts(
        from result: ElectricalSignoffRunResult
    ) throws -> [ArtifactReference] {
        var referencesByPath: [String: ArtifactReference] = [:]
        for envelope in envelopes(from: result) {
            for reference in envelope.artifacts {
                if let existing = referencesByPath[reference.path] {
                    guard existing == reference else {
                        throw ElectricalSignoffFoundationBoundaryError.conflictingArtifact(
                            path: reference.path
                        )
                    }
                } else {
                    referencesByPath[reference.path] = reference
                }
            }
        }
        return referencesByPath.values.sorted { $0.path < $1.path }
    }

    private static func envelopes(
        from result: ElectricalSignoffRunResult
    ) -> [ElectricalSignoffResult] {
        let axisEnvelopes = result.axisResults
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map(\.value)
        let cornerEnvelopes = result.cornerResults
            .sorted { $0.key < $1.key }
            .flatMap { _, values in
                values.sorted { $0.key.rawValue < $1.key.rawValue }.map(\.value)
            }
        return axisEnvelopes + cornerEnvelopes
    }

    private static func diagnostics(
        from result: ElectricalSignoffRunResult
    ) throws -> [DesignDiagnostic] {
        envelopes(from: result).flatMap(\.diagnostics)
    }
}
