import Foundation

public protocol ElectricalTopologySourceLoading: Sendable {
    func load(request: ElectricalSignoffRequest) async throws -> ElectricalTopologySourceBundle
}
