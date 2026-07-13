import Foundation
import XcircuitePackage
import ElectricalSignoffCore

public protocol PowerIntegrityAnalyzing: Sendable {
    func execute(
        _ request: ElectricalSignoffRequest
    ) async throws -> XcircuiteEngineResultEnvelope<ElectricalSignoffPayload>
}

