import Foundation

public enum ElectricalArtifactStoreError: Error, Sendable, Hashable {
    case invalidPathSegment(String)
    case invalidNamespace(String)
    case rootIsSymbolicLink(String)
    case rootIsNotDirectory(String)
    case pathEscapesRoot(String)
    case symbolicLinkInPath(String)
    case duplicateArtifact(String)
    case conflictingArtifact(String)
    case persistenceFailed(path: String, reason: String)
}

extension ElectricalArtifactStoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidPathSegment(let value):
            "Electrical artifact path segment is invalid: \(value)"
        case .invalidNamespace(let value):
            "Electrical artifact namespace is invalid: \(value)"
        case .rootIsSymbolicLink(let path):
            "Electrical artifact root must not be a symbolic link: \(path)"
        case .rootIsNotDirectory(let path):
            "Electrical artifact root must be a directory: \(path)"
        case .pathEscapesRoot(let path):
            "Electrical artifact path escapes the injected root: \(path)"
        case .symbolicLinkInPath(let path):
            "Electrical artifact path contains a symbolic link: \(path)"
        case .duplicateArtifact(let path):
            "Electrical artifact already exists with identical content: \(path)"
        case .conflictingArtifact(let path):
            "Electrical artifact already exists with different content: \(path)"
        case .persistenceFailed(let path, let reason):
            "Electrical artifact persistence failed at \(path): \(reason)"
        }
    }
}
