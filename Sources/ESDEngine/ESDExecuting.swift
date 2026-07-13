import Foundation
import XcircuitePackage
import ElectricalSignoffCore

public protocol ESDExecuting: Sendable {
    func execute(
        _ request: ElectricalSignoffRequest
    ) async throws -> XcircuiteEngineResultEnvelope<ElectricalSignoffPayload>
}

