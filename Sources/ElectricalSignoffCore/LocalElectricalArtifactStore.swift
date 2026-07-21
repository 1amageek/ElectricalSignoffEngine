import CircuiteFoundation
import Foundation

public actor LocalElectricalArtifactStore: ElectricalArtifactStoring {
    public let artifactRoot: URL
    public let namespace: ElectricalArtifactNamespace

    public init(
        artifactRoot: URL,
        namespace: ElectricalArtifactNamespace
    ) throws {
        let standardizedRoot = artifactRoot.standardizedFileURL
        if FileManager.default.fileExists(atPath: standardizedRoot.path(percentEncoded: false)) {
            let values = try standardizedRoot.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else {
                throw ElectricalArtifactStoreError.rootIsSymbolicLink(
                    standardizedRoot.path(percentEncoded: false)
                )
            }
        }
        self.artifactRoot = standardizedRoot.resolvingSymlinksInPath()
        self.namespace = namespace
    }

    public func store(
        data: Data,
        artifactID: String,
        runID: String,
        axis: ElectricalSignoffAnalysisAxis,
        producer: ProducerIdentity
    ) async throws -> ArtifactReference {
        try prepareArtifactRoot()
        let runSegment = try ElectricalArtifactPathSegment(validating: runID)
        let axisSegment = try ElectricalArtifactPathSegment(validating: axis.rawValue)
        let artifactSegment = try ElectricalArtifactPathSegment(validating: artifactID)
        let relativePath = "\(namespace.relativePath)/\(runSegment.rawValue)/\(axisSegment.rawValue)/\(artifactSegment.rawValue).json"
        let fileURL = artifactRoot.appending(path: relativePath).standardizedFileURL
        try validateContainment(fileURL)
        try rejectSymbolicLinks(through: fileURL)

        let directoryURL = fileURL.deletingLastPathComponent()
        do {
            try validateArtifactRoot()
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try validateArtifactRoot()
            try rejectSymbolicLinks(through: directoryURL)
            if FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) {
                let collision = try collisionError(
                    at: fileURL,
                    proposedData: data,
                    relativePath: relativePath
                )
                throw collision
            }
            try writeImmutable(data, to: fileURL, relativePath: relativePath)
        } catch let error as ElectricalArtifactStoreError {
            throw error
        } catch {
            if FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) {
                let collision = try collisionError(
                    at: fileURL,
                    proposedData: data,
                    relativePath: relativePath
                )
                throw collision
            }
            throw ElectricalArtifactStoreError.persistenceFailed(
                path: relativePath,
                reason: error.localizedDescription
            )
        }

        return ArtifactReference(
            id: try ArtifactID(rawValue: artifactID),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: relativePath),
                role: .output,
                kind: .report,
                format: .json
            ),
            digest: try SHA256ContentDigester().digest(data: data),
            byteCount: UInt64(data.count),
            producer: producer
        )
    }

    private func prepareArtifactRoot() throws {
        let rootPath = artifactRoot.path(percentEncoded: false)
        if !FileManager.default.fileExists(atPath: rootPath) {
            try FileManager.default.createDirectory(
                at: artifactRoot,
                withIntermediateDirectories: true
            )
        }
        try validateArtifactRoot()
    }

    private func validateArtifactRoot() throws {
        let rootPath = artifactRoot.path(percentEncoded: false)
        let values = try artifactRoot.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard values.isSymbolicLink != true else {
            throw ElectricalArtifactStoreError.rootIsSymbolicLink(rootPath)
        }
        guard values.isDirectory == true else {
            throw ElectricalArtifactStoreError.rootIsNotDirectory(rootPath)
        }
    }

    private func validateContainment(_ url: URL) throws {
        let rootPath = artifactRoot.path(percentEncoded: false)
        let candidatePath = url.path(percentEncoded: false)
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard candidatePath.hasPrefix(rootPrefix) else {
            throw ElectricalArtifactStoreError.pathEscapesRoot(candidatePath)
        }
    }

    private func rejectSymbolicLinks(through url: URL) throws {
        var candidate = artifactRoot
        let rootComponents = artifactRoot.pathComponents
        let candidateComponents = url.pathComponents
        guard candidateComponents.starts(with: rootComponents) else {
            throw ElectricalArtifactStoreError.pathEscapesRoot(url.path(percentEncoded: false))
        }
        for component in candidateComponents.dropFirst(rootComponents.count) {
            candidate.append(path: component)
            guard FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) else {
                continue
            }
            let values = try candidate.resourceValues(forKeys: [.isSymbolicLinkKey])
            if values.isSymbolicLink == true {
                throw ElectricalArtifactStoreError.symbolicLinkInPath(
                    candidate.path(percentEncoded: false)
                )
            }
        }
    }

    private func collisionError(
        at url: URL,
        proposedData: Data,
        relativePath: String
    ) throws -> ElectricalArtifactStoreError {
        let existingData: Data
        do {
            existingData = try Data(contentsOf: url)
        } catch {
            throw ElectricalArtifactStoreError.persistenceFailed(
                path: relativePath,
                reason: error.localizedDescription
            )
        }
        return existingData == proposedData
            ? .duplicateArtifact(relativePath)
            : .conflictingArtifact(relativePath)
    }

    private func writeImmutable(
        _ data: Data,
        to destinationURL: URL,
        relativePath: String
    ) throws {
        let temporaryURL = destinationURL.deletingLastPathComponent().appending(
            path: ".\(destinationURL.lastPathComponent).\(UUID().uuidString).tmp"
        )
        do {
            try data.write(to: temporaryURL, options: .atomic)
            try validateArtifactRoot()
            try rejectSymbolicLinks(through: destinationURL.deletingLastPathComponent())
            try FileManager.default.linkItem(at: temporaryURL, to: destinationURL)
        } catch {
            let originalError = error
            if FileManager.default.fileExists(atPath: temporaryURL.path(percentEncoded: false)) {
                do {
                    try FileManager.default.removeItem(at: temporaryURL)
                } catch {
                    throw ElectricalArtifactStoreError.persistenceFailed(
                        path: relativePath,
                        reason: "Temporary artifact cleanup failed: \(error.localizedDescription)"
                    )
                }
            }
            if FileManager.default.fileExists(atPath: destinationURL.path(percentEncoded: false)) {
                throw try collisionError(
                    at: destinationURL,
                    proposedData: data,
                    relativePath: relativePath
                )
            }
            throw ElectricalArtifactStoreError.persistenceFailed(
                path: relativePath,
                reason: originalError.localizedDescription
            )
        }
        do {
            try FileManager.default.removeItem(at: temporaryURL)
        } catch {
            throw ElectricalArtifactStoreError.persistenceFailed(
                path: relativePath,
                reason: "Temporary artifact cleanup failed: \(error.localizedDescription)"
            )
        }
    }
}
