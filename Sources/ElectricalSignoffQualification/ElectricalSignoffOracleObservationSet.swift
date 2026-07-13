import Foundation

public struct ElectricalSignoffOracleObservationSet: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public struct Entry: Sendable, Hashable, Codable {
        public var caseID: String
        public var observation: ElectricalSignoffOracleObservation

        public init(caseID: String, observation: ElectricalSignoffOracleObservation) {
            self.caseID = caseID
            self.observation = observation
        }
    }

    public var schemaVersion: Int
    public var oracleID: String
    public var toolVersion: String
    public var pdkDigest: String
    public var observations: [Entry]

    public init(
        oracleID: String,
        toolVersion: String,
        pdkDigest: String,
        observations: [Entry],
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.oracleID = oracleID
        self.toolVersion = toolVersion
        self.pdkDigest = pdkDigest
        self.observations = observations.sorted { $0.caseID < $1.caseID }
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ElectricalSignoffQualificationError.invalidSpec("unsupported oracle observation schema version \(schemaVersion)")
        }
        guard !oracleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !toolVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !pdkDigest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ElectricalSignoffQualificationError.invalidSpec("oracle identity and PDK digest are required")
        }
        guard !observations.isEmpty else {
            throw ElectricalSignoffQualificationError.invalidSpec("oracle observation set must not be empty")
        }
        guard Set(observations.map(\.caseID)).count == observations.count else {
            throw ElectricalSignoffQualificationError.invalidSpec("oracle observation case IDs must be unique")
        }
        for entry in observations {
            guard !entry.caseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ElectricalSignoffQualificationError.invalidSpec("oracle observation case IDs are required")
            }
            guard entry.observation.oracleID == oracleID,
                  entry.observation.toolVersion == toolVersion,
                  entry.observation.pdkDigest.caseInsensitiveCompare(pdkDigest) == .orderedSame,
                  entry.observation.isIndependent else {
                throw ElectricalSignoffQualificationError.oracleNotIndependent(entry.observation.oracleID)
            }
            try entry.observation.validate()
        }
    }
}
