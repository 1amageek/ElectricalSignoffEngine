import ElectricalSignoffCore
import Foundation

public struct ElectricalSignoffRepairPlan: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public struct Candidate: Sendable, Hashable, Codable {
        public var candidateID: String
        public var axis: ElectricalSignoffAnalysisAxis
        public var cornerID: String?
        public var kind: String
        public var entity: String
        public var rationale: String
        public var actions: [String]

        public init(
            candidateID: String,
            axis: ElectricalSignoffAnalysisAxis,
            cornerID: String?,
            kind: String,
            entity: String,
            rationale: String,
            actions: [String]
        ) {
            self.candidateID = candidateID
            self.axis = axis
            self.cornerID = cornerID
            self.kind = kind
            self.entity = entity
            self.rationale = rationale
            self.actions = actions
        }
    }

    public var schemaVersion: Int
    public var runID: String
    public var designDigest: String?
    public var layoutDigest: String?
    public var pdkDigest: String?
    public var candidates: [Candidate]
    public var sourceArtifactIDs: [String]
    public var applicationPolicy: String

    public init(
        runID: String,
        designDigest: String?,
        layoutDigest: String?,
        pdkDigest: String?,
        candidates: [Candidate],
        sourceArtifactIDs: [String],
        applicationPolicy: String = "Apply only as a new immutable design revision, then rerun all required signoff axes."
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        self.designDigest = designDigest
        self.layoutDigest = layoutDigest
        self.pdkDigest = pdkDigest
        self.candidates = candidates.sorted { $0.candidateID < $1.candidateID }
        self.sourceArtifactIDs = Array(Set(sourceArtifactIDs)).sorted()
        self.applicationPolicy = applicationPolicy
    }

    public init(runResult: ElectricalSignoffRunResult) {
        let envelopes = runResult.cornerResults.values.flatMap { $0.values }
        let fallbackEnvelopes = envelopes.isEmpty ? Array(runResult.axisResults.values) : envelopes
        let candidates = fallbackEnvelopes.flatMap { envelope in
            envelope.payload.repairCandidates.map { candidate in
                Candidate(
                    candidateID: candidate.candidateID,
                    axis: envelope.payload.axis,
                    cornerID: envelope.payload.cornerID,
                    kind: candidate.kind,
                    entity: candidate.entity,
                    rationale: candidate.rationale,
                    actions: candidate.actions
                )
            }
        }
        let provenance = fallbackEnvelopes.compactMap { $0.payload.provenance }.first
        let sourceArtifactIDs = fallbackEnvelopes.flatMap { envelope in
            envelope.artifacts.compactMap(\.artifactID)
        }
        self.init(
            runID: runResult.runID,
            designDigest: provenance?.designDigest,
            layoutDigest: provenance?.layoutDigest,
            pdkDigest: provenance?.pdkDigest,
            candidates: candidates,
            sourceArtifactIDs: sourceArtifactIDs
        )
    }
}
