import Foundation

public protocol ElectricalSignoffProcessQualificationEvaluating: Sendable {
    func evaluate(
        _ request: ElectricalSignoffProcessQualificationRequest
    ) throws -> ElectricalSignoffProcessQualificationResult
}
