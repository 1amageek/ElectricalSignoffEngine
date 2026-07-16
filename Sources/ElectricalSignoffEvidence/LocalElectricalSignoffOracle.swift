import Foundation

public struct LocalElectricalSignoffOracle: ElectricalSignoffOracle, Sendable {
    private let observations: [String: ElectricalSignoffOracleObservation]

    public init(observationSet: ElectricalSignoffOracleObservationSet) throws {
        try observationSet.validate()
        observations = Dictionary(uniqueKeysWithValues: observationSet.observations.map {
            ($0.caseID, $0.observation)
        })
    }

    public init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url)
        let observationSet = try JSONDecoder().decode(ElectricalSignoffOracleObservationSet.self, from: data)
        try self.init(observationSet: observationSet)
    }

    public func evaluate(
        _ testCase: ElectricalSignoffCorpusCase
    ) async throws -> ElectricalSignoffOracleObservation {
        guard let observation = observations[testCase.caseID] else {
            throw ElectricalSignoffCorpusError.oracleUnavailable(testCase.caseID)
        }
        guard observation.pdkDigest.caseInsensitiveCompare(testCase.request.pdk.digest) == .orderedSame else {
            throw ElectricalSignoffCorpusError.invalidSpec(
                "oracle observation PDK digest does not match case \(testCase.caseID)"
            )
        }
        return observation
    }
}
