import Foundation

public protocol ElectricalTopologyLoading: Sendable {
    func load(request: ElectricalSignoffRequest) async throws -> ElectricalSignoffInput
}
