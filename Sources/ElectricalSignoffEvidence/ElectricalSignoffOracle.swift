import Foundation

public protocol ElectricalSignoffOracle: Sendable {
    func evaluate(
        _ testCase: ElectricalSignoffCorpusCase
    ) async throws -> ElectricalSignoffOracleObservation
}
