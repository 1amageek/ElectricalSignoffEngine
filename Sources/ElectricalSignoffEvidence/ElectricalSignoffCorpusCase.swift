import Foundation
import ElectricalSignoffCore

public enum ElectricalSignoffCorpusCaseKind: String, Sendable, Hashable, Codable {
    case positive
    case negative
    case boundary
    case regression
}

public struct ElectricalSignoffCorpusCase: Sendable, Hashable, Codable {
    public var caseID: String
    public var kind: ElectricalSignoffCorpusCaseKind
    public var axis: ElectricalSignoffAnalysisAxis
    public var request: ElectricalSignoffRequest
    public var expected: ElectricalSignoffExpectedObservation

    public init(
        caseID: String,
        kind: ElectricalSignoffCorpusCaseKind,
        axis: ElectricalSignoffAnalysisAxis,
        request: ElectricalSignoffRequest,
        expected: ElectricalSignoffExpectedObservation
    ) {
        self.caseID = caseID
        self.kind = kind
        self.axis = axis
        self.request = request
        self.expected = expected
    }

    public func validate(pdkDigest: String) throws {
        do {
            _ = try ElectricalArtifactPathSegment(validating: caseID)
            _ = try ElectricalArtifactPathSegment(
                validating: request.runID + "-" + caseID
            )
        } catch {
            throw ElectricalSignoffCorpusError.invalidSpec(
                "case IDs and derived execution run IDs must be path-safe components"
            )
        }
        guard axis != .aggregate else {
            throw ElectricalSignoffCorpusError.invalidSpec("aggregate is not a corpus axis")
        }
        guard request.pdk.digest.caseInsensitiveCompare(pdkDigest) == .orderedSame else {
            throw ElectricalSignoffCorpusError.invalidSpec(
                "case \(caseID) PDK digest does not match the corpus scope"
            )
        }
        try request.validate()
        try request.configuration.validate()
        try expected.validate()
    }
}
