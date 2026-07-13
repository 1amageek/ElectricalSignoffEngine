import Foundation
import CircuiteFoundation
import ElectricalSignoffCore

public struct ExternalPowerIntegrityEngine: PowerIntegrityAnalyzing {
    public let runner: any ExternalElectricalSignoffRunning

    public init(runner: any ExternalElectricalSignoffRunning) {
        self.runner = runner
    }

    public func execute(_ request: ElectricalSignoffRequest) async throws -> ElectricalSignoffResult {
        try await runner.execute(request, axis: .powerIntegrity)
    }
}
