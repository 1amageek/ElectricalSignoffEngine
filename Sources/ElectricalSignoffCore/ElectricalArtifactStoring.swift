import Foundation
import CircuiteFoundation

public protocol ElectricalArtifactStoring: Sendable {
    func store(
        data: Data,
        artifactID: String,
        runID: String,
        axis: ElectricalSignoffAnalysisAxis
    ) async throws -> ArtifactReference
}
