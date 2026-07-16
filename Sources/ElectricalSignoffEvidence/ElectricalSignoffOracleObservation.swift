import Foundation
import ElectricalSignoffCore
import CircuiteFoundation

public struct ElectricalSignoffOracleObservation: Sendable, Hashable, Codable {
    public var oracleID: String
    public var toolVersion: String
    public var pdkDigest: String
    public var status: ElectricalSignoffExecutionStatus
    public var violationCount: Int
    public var diagnosticCodes: [String]
    public var metrics: [ElectricalSignoffPayload.Metric]
    public var inputArtifacts: [ArtifactReference]
    public var artifacts: [ArtifactReference]
    public var evidenceArtifact: ArtifactReference

    public init(
        oracleID: String,
        toolVersion: String,
        pdkDigest: String,
        status: ElectricalSignoffExecutionStatus,
        violationCount: Int,
        diagnosticCodes: [String] = [],
        metrics: [ElectricalSignoffPayload.Metric] = [],
        inputArtifacts: [ArtifactReference],
        artifacts: [ArtifactReference],
        evidenceArtifact: ArtifactReference
    ) {
        self.oracleID = oracleID
        self.toolVersion = toolVersion
        self.pdkDigest = pdkDigest
        self.status = status
        self.violationCount = violationCount
        self.diagnosticCodes = diagnosticCodes.sorted()
        self.metrics = metrics
        self.inputArtifacts = inputArtifacts
        self.artifacts = artifacts
        self.evidenceArtifact = evidenceArtifact
    }

    public var hasEvidenceBinding: Bool {
        !inputArtifacts.isEmpty
            && artifacts.contains(evidenceArtifact)
            && Self.isValidArtifact(evidenceArtifact)
    }

    public func validate() throws {
        guard !oracleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !toolVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !pdkDigest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              hasEvidenceBinding,
              violationCount >= 0 else {
            throw ElectricalSignoffCorpusError.invalidSpec("oracle observation identity or violation count is invalid")
        }
        guard Set(diagnosticCodes).count == diagnosticCodes.count else {
            throw ElectricalSignoffCorpusError.invalidSpec("oracle diagnostic codes must be unique")
        }
        guard metrics.allSatisfy({
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !$0.unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.value.isFinite
        }), Set(metrics.map(\.name)).count == metrics.count else {
            throw ElectricalSignoffCorpusError.invalidSpec("oracle metrics must have unique finite names and units")
        }
        guard !inputArtifacts.isEmpty,
              inputArtifacts.allSatisfy(Self.isValidArtifact),
              !artifacts.isEmpty,
              artifacts.allSatisfy(Self.isValidArtifact) else {
            throw ElectricalSignoffCorpusError.invalidSpec("oracle input and output artifact references are invalid")
        }
    }

    private static func isValidArtifact(_ reference: ArtifactReference) -> Bool {
        !reference.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && reference.byteCount > 0
            && reference.digest.algorithm == .sha256
            && reference.digest.hexadecimalValue.utf8.count == 64
    }
}
