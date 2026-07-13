import Foundation
import CircuiteFoundation

public protocol ExternalElectricalSignoffRunning: Sendable {
    func execute(
        _ request: ElectricalSignoffRequest,
        axis: ElectricalSignoffAnalysisAxis
    ) async throws -> ElectricalSignoffResult
}
