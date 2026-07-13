import CircuiteFoundation
import Foundation
import XcircuitePackage

public actor InMemoryElectricalArtifactStore: ElectricalArtifactStoring {
    private var values: [String: Data] = [:]
    private let digester = SHA256ContentDigester()

    public init() {}

    public func store(
        data: Data,
        artifactID: String,
        runID: String,
        axis: ElectricalSignoffAnalysisAxis
    ) async throws -> XcircuiteFileReference {
        let key = "\(runID)/\(artifactID)"
        values[key] = data
        let digest = try digester.digest(data: data, using: .sha256)
        return XcircuiteFileReference(
            artifactID: artifactID,
            path: "memory/\(runID)/\(safePathComponent(artifactID)).json",
            kind: .report,
            format: .json,
            sha256: digest.hexadecimalValue,
            byteCount: Int64(data.count),
            producedByRunID: runID
        )
    }

    public func data(artifactID: String, runID: String) -> Data? {
        values["\(runID)/\(artifactID)"]
    }

    private func safePathComponent(_ value: String) -> String {
        let scalars = value.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" ? Character(scalar) : "-"
        }
        let result = String(scalars)
        guard !result.isEmpty else {
            return "artifact-\(identifierDigest(value))"
        }
        guard result == value else {
            return "\(result)-\(identifierDigest(value))"
        }
        return result
    }

    private func identifierDigest(_ value: String) -> String {
        String(XcircuiteHasher().sha256(data: Data(value.utf8)).prefix(12))
    }
}
