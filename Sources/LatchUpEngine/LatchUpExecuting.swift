import Foundation
import CircuiteFoundation
import ElectricalSignoffCore

public protocol LatchUpExecuting: Sendable {
    func execute(
        _ request: ElectricalSignoffRequest
    ) async throws -> ElectricalSignoffResult
}

