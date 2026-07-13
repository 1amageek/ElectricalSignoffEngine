import Foundation

public protocol ElectricalSignoffQualificationOracle: Sendable {
    func evaluate(
        _ testCase: ElectricalSignoffQualificationCase
    ) async throws -> ElectricalSignoffOracleObservation
}
