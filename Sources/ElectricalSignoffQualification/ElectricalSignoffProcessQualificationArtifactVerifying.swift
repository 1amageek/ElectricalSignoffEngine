import Foundation

public protocol ElectricalSignoffProcessQualificationArtifactVerifying: Sendable {
    func verify(
        _ request: ElectricalSignoffProcessQualificationRequest,
        projectRoot: URL
    ) -> [ElectricalSignoffProcessQualificationArtifactIntegrityIssue]
}
