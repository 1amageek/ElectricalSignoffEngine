import Foundation

public protocol ElectricalTopologyExtracting: Sendable {
    func extract(_ sources: ElectricalTopologySourceBundle) throws -> ElectricalTopology
}
