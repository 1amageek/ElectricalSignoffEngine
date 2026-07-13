import Foundation
import CircuiteFoundation
import ElectricalSignoffCore

public protocol ESDExecuting: Sendable {
    func execute(
        _ request: ElectricalSignoffRequest
    ) async throws -> ElectricalSignoffResult
}

