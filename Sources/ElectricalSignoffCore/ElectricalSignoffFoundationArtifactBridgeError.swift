import Foundation

public enum ElectricalSignoffFoundationArtifactBridgeError: Error, Sendable, Hashable, Codable, LocalizedError {
    case invalidReference(path: String, reason: String)
    case missingArtifact(String)
    case notRegularFile(String)
    case unreadable(path: String, reason: String)
    case digestMismatch(path: String, expected: String, actual: String)
    case byteCountMismatch(path: String, expected: Int64, actual: Int64)
    case missingDigest(String)
    case missingByteCount(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidReference(path, reason):
            return "Electrical artifact reference is invalid at \(path): \(reason)"
        case let .missingArtifact(path):
            return "Electrical artifact is missing: \(path)"
        case let .notRegularFile(path):
            return "Electrical artifact is not a regular file: \(path)"
        case let .unreadable(path, reason):
            return "Electrical artifact cannot be read at \(path): \(reason)"
        case let .digestMismatch(path, expected, actual):
            return "Electrical artifact digest mismatch at \(path): expected \(expected), actual \(actual)."
        case let .byteCountMismatch(path, expected, actual):
            return "Electrical artifact byte count mismatch at \(path): expected \(expected), actual \(actual)."
        case let .missingDigest(path):
            return "Electrical artifact has no captured digest: \(path)"
        case let .missingByteCount(path):
            return "Electrical artifact has no captured byte count: \(path)"
        }
    }
}
