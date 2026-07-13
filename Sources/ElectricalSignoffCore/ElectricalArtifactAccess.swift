import CircuiteFoundation
import Foundation

/// Provides the electrical domain's direct access to Foundation artifact
/// location and integrity contracts.
public struct ElectricalArtifactAccess: Sendable {
    private let verifier: LocalArtifactVerifier

    public init(verifier: LocalArtifactVerifier = LocalArtifactVerifier()) {
        self.verifier = verifier
    }

    public func locator(for reference: ArtifactReference) -> ArtifactLocator {
        reference.locator
    }

    public func resolveURL(
        for reference: ArtifactReference,
        relativeTo projectRoot: URL
    ) throws -> URL {
        do {
            return try reference.locator.location.resolvedFileURL(relativeTo: projectRoot)
        } catch {
            throw ElectricalArtifactAccessError.invalidReference(
                path: reference.path,
                reason: error.localizedDescription
            )
        }
    }

    @discardableResult
    public func validate(
        _ reference: ArtifactReference,
        relativeTo projectRoot: URL,
        verifyIntegrity: Bool
    ) throws -> ArtifactReference? {
        let url = try resolveURL(for: reference, relativeTo: projectRoot)
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw ElectricalArtifactAccessError.missingArtifact(reference.path)
        }
        guard !isDirectory.boolValue else {
            throw ElectricalArtifactAccessError.notRegularFile(reference.path)
        }
        guard verifyIntegrity else { return nil }

        let integrity = verifier.verify(reference, relativeTo: projectRoot)
        guard integrity.isVerified else {
            throw ElectricalArtifactAccessError.integrityFailure(
                path: reference.path,
                reason: integrity.issues.map { issue in
                    issue.detail ?? issue.code.rawValue
                }.joined(separator: "; ")
            )
        }
        return reference
    }

    public func reference(from reference: ArtifactReference) -> ArtifactReference {
        reference
    }
}
