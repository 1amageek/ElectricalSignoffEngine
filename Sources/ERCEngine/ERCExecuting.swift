import Foundation
import CircuiteFoundation
import ElectricalSignoffCore

public protocol ERCExecuting: Sendable {
    func execute(
        _ request: ElectricalSignoffRequest
    ) async throws -> ElectricalSignoffResult
}

