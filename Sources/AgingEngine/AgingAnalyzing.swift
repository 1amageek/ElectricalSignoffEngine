import Foundation
import XcircuitePackage
import ElectricalSignoffCore

public protocol AgingAnalyzing: Sendable {
    func execute(
        _ request: ElectricalSignoffRequest
    ) async throws -> XcircuiteEngineResultEnvelope<ElectricalSignoffPayload>
}

