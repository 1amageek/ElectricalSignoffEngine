import Foundation
import XcircuitePackage
import ElectricalSignoffCore

public protocol LatchUpExecuting: Sendable {
    func execute(
        _ request: ElectricalSignoffRequest
    ) async throws -> XcircuiteEngineResultEnvelope<ElectricalSignoffPayload>
}

