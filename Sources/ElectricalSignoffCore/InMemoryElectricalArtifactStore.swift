import CircuiteFoundation
import Foundation

public actor InMemoryElectricalArtifactStore: ElectricalArtifactStoring {
    private var values: [String: Data] = [:]
    public let namespace: ElectricalArtifactNamespace

    public init(namespace: ElectricalArtifactNamespace = .electricalSignoff) {
        self.namespace = namespace
    }

    public func store(
        data: Data,
        artifactID: String,
        runID: String,
        axis: ElectricalSignoffAnalysisAxis
    ) async throws -> ArtifactReference {
        let runSegment = try ElectricalArtifactPathSegment(validating: runID)
        let axisSegment = try ElectricalArtifactPathSegment(validating: axis.rawValue)
        let artifactSegment = try ElectricalArtifactPathSegment(validating: artifactID)
        let path = "\(namespace.relativePath)/\(runSegment.rawValue)/\(axisSegment.rawValue)/\(artifactSegment.rawValue).json"
        if let existingData = values[path] {
            throw existingData == data
                ? ElectricalArtifactStoreError.duplicateArtifact(path)
                : ElectricalArtifactStoreError.conflictingArtifact(path)
        }
        values[path] = data
        return ArtifactReference(
            id: try ArtifactID(rawValue: artifactID),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: path),
                role: .output,
                kind: .report,
                format: .json
            ),
            digest: try SHA256ContentDigester().digest(data: data),
            byteCount: UInt64(data.count)
        )
    }

    public func data(artifactID: String, runID: String, axis: ElectricalSignoffAnalysisAxis) throws -> Data? {
        let runSegment = try ElectricalArtifactPathSegment(validating: runID)
        let axisSegment = try ElectricalArtifactPathSegment(validating: axis.rawValue)
        let artifactSegment = try ElectricalArtifactPathSegment(validating: artifactID)
        return values["\(namespace.relativePath)/\(runSegment.rawValue)/\(axisSegment.rawValue)/\(artifactSegment.rawValue).json"]
    }
}
