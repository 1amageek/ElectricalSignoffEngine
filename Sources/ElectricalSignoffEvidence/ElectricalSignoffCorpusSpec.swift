import Foundation

public struct ElectricalSignoffCorpusSpec: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var corpusID: String
    public var corpusVersion: String
    public var pdkDigest: String
    public var requireExternalOracleEvidence: Bool
    public var cases: [ElectricalSignoffCorpusCase]

    public init(
        corpusID: String,
        corpusVersion: String,
        pdkDigest: String,
        requireExternalOracleEvidence: Bool = false,
        cases: [ElectricalSignoffCorpusCase],
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.corpusID = corpusID
        self.corpusVersion = corpusVersion
        self.pdkDigest = pdkDigest
        self.requireExternalOracleEvidence = requireExternalOracleEvidence
        self.cases = cases
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ElectricalSignoffCorpusError.invalidSpec("unsupported corpus schema version \(schemaVersion)")
        }
        guard !corpusID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !corpusVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !pdkDigest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ElectricalSignoffCorpusError.invalidSpec("corpus identity and PDK digest are required")
        }
        guard !cases.isEmpty else {
            throw ElectricalSignoffCorpusError.invalidSpec("corpus must contain at least one case")
        }
        let runIDs = Set(cases.map(\.request.runID))
        guard runIDs.count == 1 else {
            throw ElectricalSignoffCorpusError.invalidSpec(
                "all corpus cases must belong to one reproducible run ID"
            )
        }
        var caseIDs = Set<String>()
        for testCase in cases {
            guard caseIDs.insert(testCase.caseID).inserted else {
                throw ElectricalSignoffCorpusError.duplicateCaseID(testCase.caseID)
            }
            try testCase.validate(pdkDigest: pdkDigest)
        }
    }
}
