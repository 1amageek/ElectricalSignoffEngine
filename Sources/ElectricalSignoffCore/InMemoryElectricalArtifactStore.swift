import CircuiteFoundation
import CryptoKit
import Foundation

public actor InMemoryElectricalArtifactStore: ElectricalArtifactStoring {
    private var values: [String: Data] = [:]
    private let digester = SHA256ContentDigester()

    public init() {}

    public func store(
        data: Data,
        artifactID: String,
        runID: String,
        axis: ElectricalSignoffAnalysisAxis
    ) async throws -> ArtifactReference {
        let key = "\(runID)/\(artifactID)"
        values[key] = data
        let digest = try digester.digest(data: data, using: .sha256)
        let location = try ArtifactLocation(
            workspaceRelativePath: "memory/\(runID)/\(safePathComponent(artifactID)).json"
        )
        let locator = ArtifactLocator(
            location: location,
            role: .output,
            kind: .report,
            format: .json
        )
        return ArtifactReference(
            locator: locator,
            digest: digest,
            byteCount: UInt64(data.count)
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
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined().prefix(12).description
    }
}
