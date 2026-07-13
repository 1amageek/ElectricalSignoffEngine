import Foundation
import ElectricalSignoffCore

public enum ElectricalSignoffQualificationCaseKind: String, Sendable, Hashable, Codable {
    case positive
    case negative
    case boundary
    case regression
}

public struct ElectricalSignoffQualificationCase: Sendable, Hashable, Codable {
    public var caseID: String
    public var kind: ElectricalSignoffQualificationCaseKind
    public var axis: ElectricalSignoffAnalysisAxis
    public var request: ElectricalSignoffRequest
    public var expected: ElectricalSignoffExpectedObservation

    public init(
        caseID: String,
        kind: ElectricalSignoffQualificationCaseKind,
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
        guard !caseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ElectricalSignoffQualificationError.invalidSpec("case IDs are required")
        }
        guard axis != .aggregate else {
            throw ElectricalSignoffQualificationError.invalidSpec("aggregate is not a qualification axis")
        }
        guard request.pdk.digest.caseInsensitiveCompare(pdkDigest) == .orderedSame else {
            throw ElectricalSignoffQualificationError.invalidSpec(
                "case \(caseID) PDK digest does not match the corpus scope"
            )
        }
        try request.validate()
        try request.configuration.validate()
        try expected.validate()
    }
}
