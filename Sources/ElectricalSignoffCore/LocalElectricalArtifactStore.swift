import CircuiteFoundation
import Foundation
import XcircuitePackage

public actor LocalElectricalArtifactStore: ElectricalArtifactStoring {
    public let projectRoot: URL
    public let outputDirectory: String

    public init(projectRoot: URL, outputDirectory: String = ".xcircuite/runs") {
        self.projectRoot = projectRoot.standardizedFileURL
        self.outputDirectory = outputDirectory
    }

    public func store(
        data: Data,
        artifactID: String,
        runID: String,
        axis: ElectricalSignoffAnalysisAxis
    ) async throws -> XcircuiteFileReference {
        let relativeDirectory = "\(outputDirectory)/\(runID)/electrical-signoff"
        let relativePath = "\(relativeDirectory)/\(safeFileName(artifactID)).json"
        let directoryURL = try XcircuitePackage(projectRoot: projectRoot)
            .url(forProjectRelativePath: relativeDirectory)
        let fileURL = try XcircuitePackage(projectRoot: projectRoot)
            .url(forProjectRelativePath: relativePath)
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            throw ElectricalSignoffError.artifactPersistence(error.localizedDescription)
        }
        do {
            let location = try ArtifactLocation(workspaceRelativePath: relativePath)
            let locator = ArtifactLocator(
                location: location,
                kind: .report,
                format: .json
            )
            let foundationReference = try LocalArtifactReferencer().reference(
                locator,
                relativeTo: projectRoot,
                producer: nil
            )
            return XcircuiteFileReference(
                artifactID: artifactID,
                path: relativePath,
                kind: .report,
                format: .json,
                sha256: foundationReference.digest.hexadecimalValue,
                byteCount: Int64(foundationReference.byteCount),
                producedByRunID: runID,
                verifiedByRunID: runID
            )
        } catch {
            throw ElectricalSignoffError.artifactPersistence(
                "artifact integrity capture failed: \(error.localizedDescription)"
            )
        }
    }

    private func safeFileName(_ value: String) -> String {
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
