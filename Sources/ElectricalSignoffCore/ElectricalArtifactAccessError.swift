import Foundation

public enum ElectricalArtifactAccessError: Error, Sendable, Hashable, Codable, LocalizedError {
    case invalidReference(path: String, reason: String)
    case missingArtifact(String)
    case notRegularFile(String)
    case integrityFailure(path: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case let .invalidReference(path, reason):
            "Electrical artifact reference is invalid at \(path): \(reason)"
        case let .missingArtifact(path):
            "Electrical artifact is missing: \(path)"
        case let .notRegularFile(path):
            "Electrical artifact is not a regular file: \(path)"
        case let .integrityFailure(path, reason):
            "Electrical artifact integrity failed at \(path): \(reason)"
        }
    }
}
