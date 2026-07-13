import Foundation

public enum ElectricalSignoffReleaseArtifactBundleError: Error, Sendable, Hashable, Codable, LocalizedError {
    case unsupportedSchemaVersion(Int)
    case invalidRunID
    case missingReference(role: String)
    case missingIntegrity(path: String)
    case duplicatePath(path: String)
    case digestMismatch(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedSchemaVersion(version):
            return "Electrical signoff release artifact bundle schema version is unsupported: \(version)."
        case .invalidRunID:
            return "Electrical signoff release artifact bundle requires a non-empty run ID."
        case let .missingReference(role):
            return "Electrical signoff release artifact bundle is missing required reference: \(role)."
        case let .missingIntegrity(path):
            return "Electrical signoff release artifact bundle reference has no verified digest or byte count: \(path)."
        case let .duplicatePath(path):
            return "Electrical signoff release artifact bundle contains duplicate artifact path: \(path)."
        case let .digestMismatch(expected, actual):
            return "Electrical signoff release artifact bundle digest mismatch: expected \(expected), actual \(actual)."
        }
    }
}
