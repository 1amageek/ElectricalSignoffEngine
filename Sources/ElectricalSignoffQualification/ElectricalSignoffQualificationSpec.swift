import Foundation

public struct ElectricalSignoffQualificationSpec: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var corpusID: String
    public var corpusVersion: String
    public var pdkDigest: String
    public var requireIndependentOracle: Bool
    public var cases: [ElectricalSignoffQualificationCase]

    public init(
        corpusID: String,
        corpusVersion: String,
        pdkDigest: String,
        requireIndependentOracle: Bool = false,
        cases: [ElectricalSignoffQualificationCase],
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.corpusID = corpusID
        self.corpusVersion = corpusVersion
        self.pdkDigest = pdkDigest
        self.requireIndependentOracle = requireIndependentOracle
        self.cases = cases
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ElectricalSignoffQualificationError.invalidSpec("unsupported corpus schema version \(schemaVersion)")
        }
        guard !corpusID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !corpusVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !pdkDigest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ElectricalSignoffQualificationError.invalidSpec("corpus identity and PDK digest are required")
        }
        guard !cases.isEmpty else {
            throw ElectricalSignoffQualificationError.invalidSpec("qualification corpus must contain at least one case")
        }
        let runIDs = Set(cases.map(\.request.runID))
        guard runIDs.count == 1 else {
            throw ElectricalSignoffQualificationError.invalidSpec(
                "all qualification cases must belong to one reproducible run ID"
            )
        }
        var caseIDs = Set<String>()
        for testCase in cases {
            guard caseIDs.insert(testCase.caseID).inserted else {
                throw ElectricalSignoffQualificationError.duplicateCaseID(testCase.caseID)
            }
            try testCase.validate(pdkDigest: pdkDigest)
        }
    }
}
