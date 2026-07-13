import CircuiteFoundation
import Foundation
import XcircuitePackage

/// Converts the legacy project-package artifact declaration into the
/// Foundation locator/reference contract at the ElectricalSignoff boundary.
///
/// `XcircuiteFileReference` remains the project and run-lifecycle type owned by
/// XcircuitePackage. This bridge prevents that lifecycle type from becoming
/// the integrity implementation used by the electrical engine.
public struct ElectricalSignoffFoundationArtifactBridge: Sendable {
    public init() {}

    public func locator(
        for reference: XcircuiteFileReference
    ) throws -> ArtifactLocator {
        let location: ArtifactLocation
        do {
            if reference.path.hasPrefix("/") {
                location = try ArtifactLocation(fileURL: URL(fileURLWithPath: reference.path))
            } else {
                location = try ArtifactLocation(workspaceRelativePath: reference.path)
            }
        } catch {
            throw ElectricalSignoffFoundationArtifactBridgeError.invalidReference(
                path: reference.path,
                reason: error.localizedDescription
            )
        }

        do {
            return ArtifactLocator(
                location: location,
                kind: try ArtifactKind(rawValue: "electrical-signoff.\(reference.kind.rawValue)"),
                format: try ArtifactFormat(rawValue: normalizedFormat(reference.format.rawValue))
            )
        } catch {
            throw ElectricalSignoffFoundationArtifactBridgeError.invalidReference(
                path: reference.path,
                reason: error.localizedDescription
            )
        }
    }

    public func resolveURL(
        for reference: XcircuiteFileReference,
        relativeTo projectRoot: URL
    ) throws -> URL {
        try locator(for: reference).location.resolvedFileURL(relativeTo: projectRoot)
    }

    /// Validates a declared project artifact using Foundation's path and file
    /// semantics. When integrity checking is enabled, the returned reference
    /// contains the digest and byte count captured from the materialized file.
    @discardableResult
    public func validate(
        _ reference: XcircuiteFileReference,
        relativeTo projectRoot: URL,
        verifyIntegrity: Bool
    ) throws -> ArtifactReference? {
        let artifactLocator: ArtifactLocator
        do {
            artifactLocator = try locator(for: reference)
        } catch let error as ElectricalSignoffFoundationArtifactBridgeError {
            throw error
        } catch {
            throw ElectricalSignoffFoundationArtifactBridgeError.invalidReference(
                path: reference.path,
                reason: error.localizedDescription
            )
        }

        let url: URL
        do {
            url = try artifactLocator.location.resolvedFileURL(relativeTo: projectRoot)
        } catch {
            throw ElectricalSignoffFoundationArtifactBridgeError.invalidReference(
                path: reference.path,
                reason: error.localizedDescription
            )
        }

        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw ElectricalSignoffFoundationArtifactBridgeError.missingArtifact(reference.path)
        }
        guard !isDirectory.boolValue else {
            throw ElectricalSignoffFoundationArtifactBridgeError.notRegularFile(reference.path)
        }

        guard verifyIntegrity else {
            return nil
        }

        let materialized: ArtifactReference
        do {
            materialized = try LocalArtifactReferencer().reference(
                artifactLocator,
                relativeTo: projectRoot,
                producer: nil
            )
        } catch ArtifactReferenceError.fileNotFound {
            throw ElectricalSignoffFoundationArtifactBridgeError.missingArtifact(reference.path)
        } catch ArtifactReferenceError.notRegularFile {
            throw ElectricalSignoffFoundationArtifactBridgeError.notRegularFile(reference.path)
        } catch {
            throw ElectricalSignoffFoundationArtifactBridgeError.unreadable(
                path: reference.path,
                reason: error.localizedDescription
            )
        }

        if let expectedSHA256 = reference.sha256 {
            let expectedDigest: ContentDigest
            do {
                expectedDigest = try ContentDigest(
                    algorithm: .sha256,
                    hexadecimalValue: expectedSHA256
                )
            } catch {
                throw ElectricalSignoffFoundationArtifactBridgeError.invalidReference(
                    path: reference.path,
                    reason: "Invalid SHA-256 digest: \(error.localizedDescription)"
                )
            }
            guard materialized.digest == expectedDigest else {
                throw ElectricalSignoffFoundationArtifactBridgeError.digestMismatch(
                    path: reference.path,
                    expected: expectedDigest.hexadecimalValue,
                    actual: materialized.digest.hexadecimalValue
                )
            }
        }

        if let expectedByteCount = reference.byteCount {
            guard expectedByteCount >= 0 else {
                throw ElectricalSignoffFoundationArtifactBridgeError.invalidReference(
                    path: reference.path,
                    reason: "Byte count must not be negative."
                )
            }
            guard UInt64(expectedByteCount) == materialized.byteCount else {
                throw ElectricalSignoffFoundationArtifactBridgeError.byteCountMismatch(
                    path: reference.path,
                    expected: expectedByteCount,
                    actual: Int64(materialized.byteCount)
                )
            }
        }

        return ArtifactReference(
            id: try foundationID(for: reference),
            locator: artifactLocator,
            digest: materialized.digest,
            byteCount: materialized.byteCount
        )
    }

    /// Produces a Foundation artifact reference from an already materialized
    /// Xcircuite reference while preserving its captured identity and proof.
    /// This method does not re-read the file; callers that need an on-disk
    /// integrity check must call `validate(_:relativeTo:verifyIntegrity:)`.
    public func reference(
        from reference: XcircuiteFileReference
    ) throws -> ArtifactReference {
        let locator = try locator(for: reference)
        guard let sha256 = reference.sha256 else {
            throw ElectricalSignoffFoundationArtifactBridgeError.missingDigest(reference.path)
        }
        guard let byteCount = reference.byteCount, byteCount >= 0 else {
            throw ElectricalSignoffFoundationArtifactBridgeError.missingByteCount(reference.path)
        }

        let digest: ContentDigest
        do {
            digest = try ContentDigest(algorithm: .sha256, hexadecimalValue: sha256)
        } catch {
            throw ElectricalSignoffFoundationArtifactBridgeError.invalidReference(
                path: reference.path,
                reason: "Invalid SHA-256 digest: \(error.localizedDescription)"
            )
        }

        return ArtifactReference(
            id: try foundationID(for: reference),
            locator: locator,
            digest: digest,
            byteCount: UInt64(byteCount)
        )
    }

    private func foundationID(
        for reference: XcircuiteFileReference
    ) throws -> ArtifactID? {
        guard let rawValue = reference.artifactID, !rawValue.isEmpty else {
            return nil
        }
        do {
            return try ArtifactID(rawValue: rawValue)
        } catch {
            throw ElectricalSignoffFoundationArtifactBridgeError.invalidReference(
                path: reference.path,
                reason: error.localizedDescription
            )
        }
    }

    private func normalizedFormat(_ value: String) -> String {
        value.lowercased().replacingOccurrences(of: "_", with: "-")
    }
}
