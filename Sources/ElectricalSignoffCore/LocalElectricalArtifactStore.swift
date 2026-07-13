import CircuiteFoundation
import CryptoKit
import Foundation

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
    ) async throws -> ArtifactReference {
        let relativeDirectory = "\(outputDirectory)/\(runID)/electrical-signoff"
        let relativePath = "\(relativeDirectory)/\(safeFileName(artifactID)).json"
        let directoryLocation = try ArtifactLocation(workspaceRelativePath: relativeDirectory)
        let fileLocation = try ArtifactLocation(workspaceRelativePath: relativePath)
        let directoryURL = try directoryLocation.resolvedFileURL(relativeTo: projectRoot)
        let fileURL = try fileLocation.resolvedFileURL(relativeTo: projectRoot)
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
                role: .output,
                kind: .report,
                format: .json
            )
            let foundationReference = try LocalArtifactReferencer().reference(
                locator,
                relativeTo: projectRoot,
                producer: nil
            )
            return foundationReference
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
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined().prefix(12).description
    }
}
