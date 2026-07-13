import Foundation
import CircuiteFoundation
import ElectricalSignoffCore

public struct ExternalAgingEngine: AgingAnalyzing {
    public let runner: any ExternalElectricalSignoffRunning

    public init(runner: any ExternalElectricalSignoffRunning) {
        self.runner = runner
    }

    public func execute(_ request: ElectricalSignoffRequest) async throws -> ElectricalSignoffResult {
        try await runner.execute(request, axis: .aging)
    }
}
