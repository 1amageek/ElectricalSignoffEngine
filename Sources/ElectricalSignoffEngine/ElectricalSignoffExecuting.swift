import Foundation
import CircuiteFoundation
import ElectricalSignoffCore

public protocol ElectricalSignoffExecuting: Engine
where Request == ElectricalSignoffRequest, Output == ElectricalSignoffRunResult {
    func execute(
        _ request: ElectricalSignoffRequest,
        axes: [ElectricalSignoffAnalysisAxis]
    ) async throws -> ElectricalSignoffRunResult
}

public extension ElectricalSignoffExecuting {
    func execute(_ request: ElectricalSignoffRequest) async throws -> ElectricalSignoffRunResult {
        try await execute(request, axes: ElectricalSignoffEngineAPI.supportedAxes)
    }
}
