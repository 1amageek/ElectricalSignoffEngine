import Foundation

/// Errors raised when an electrical result cannot be projected to the shared
/// evidence contract without losing artifact or diagnostic integrity.
public enum ElectricalSignoffFoundationBoundaryError: Error, Sendable, Hashable, Codable, LocalizedError {
    case invalidArtifact(path: String, reason: String)
    case conflictingArtifact(path: String)
    case invalidDiagnostic(code: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case let .invalidArtifact(path, reason):
            return "Electrical signoff artifact cannot cross the Foundation boundary at \(path): \(reason)"
        case let .conflictingArtifact(path):
            return "Electrical signoff produced conflicting references for artifact path: \(path)"
        case let .invalidDiagnostic(code, reason):
            return "Electrical signoff diagnostic cannot cross the Foundation boundary (\(code)): \(reason)"
        }
    }
}
