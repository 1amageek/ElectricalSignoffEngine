import Foundation
import XcircuitePackage
import ElectricalSignoffCore

public struct ExternalLatchUpEngine: LatchUpExecuting {
    public let runner: any ExternalElectricalSignoffRunning

    public init(runner: any ExternalElectricalSignoffRunning) {
        self.runner = runner
    }

    public func execute(_ request: ElectricalSignoffRequest) async throws -> XcircuiteEngineResultEnvelope<ElectricalSignoffPayload> {
        try await runner.execute(request, axis: .latchUp)
    }
}
