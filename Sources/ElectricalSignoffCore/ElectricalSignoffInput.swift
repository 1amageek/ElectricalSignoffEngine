import Foundation
import CircuiteFoundation

public struct ElectricalSignoffInput: Sendable, Hashable, Codable {
    public var request: ElectricalSignoffRequest
    public var topology: ElectricalTopology
    public var verifiedReferences: [ArtifactReference]

    public init(
        request: ElectricalSignoffRequest,
        topology: ElectricalTopology,
        verifiedReferences: [ArtifactReference]
    ) {
        self.request = request
        self.topology = topology
        self.verifiedReferences = verifiedReferences
    }
}
