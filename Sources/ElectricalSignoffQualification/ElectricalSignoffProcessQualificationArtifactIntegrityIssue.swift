import Foundation
import CircuiteFoundation

public struct ElectricalSignoffProcessQualificationArtifactIntegrityIssue: Sendable, Hashable, Codable {
    public var category: String
    public var integrity: ArtifactIntegrity

    public init(
        category: String,
        integrity: ArtifactIntegrity
    ) {
        self.category = category
        self.integrity = integrity
    }
}
