import Foundation
import XcircuitePackage

public protocol ExternalElectricalSignoffRunning: Sendable {
    func execute(
        _ request: ElectricalSignoffRequest,
        axis: ElectricalSignoffAnalysisAxis
    ) async throws -> XcircuiteEngineResultEnvelope<ElectricalSignoffPayload>
}
