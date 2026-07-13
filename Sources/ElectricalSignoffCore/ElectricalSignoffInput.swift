import Foundation
import XcircuitePackage

public struct ElectricalSignoffInput: Sendable, Hashable, Codable {
    public var request: ElectricalSignoffRequest
    public var topology: ElectricalTopology
    public var verifiedReferences: [XcircuiteFileReference]

    public init(
        request: ElectricalSignoffRequest,
        topology: ElectricalTopology,
        verifiedReferences: [XcircuiteFileReference]
    ) {
        self.request = request
        self.topology = topology
        self.verifiedReferences = verifiedReferences
    }
}
