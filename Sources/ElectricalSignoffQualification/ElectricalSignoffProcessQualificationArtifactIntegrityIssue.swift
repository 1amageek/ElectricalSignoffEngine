import Foundation
import XcircuitePackage

public struct ElectricalSignoffProcessQualificationArtifactIntegrityIssue: Sendable, Hashable, Codable {
    public var category: String
    public var integrity: XcircuiteFileReferenceIntegrity

    public init(
        category: String,
        integrity: XcircuiteFileReferenceIntegrity
    ) {
        self.category = category
        self.integrity = integrity
    }
}
