import Foundation

public enum ElectricalSignoffProcessQualificationError: Error, Sendable, Hashable, Codable, LocalizedError {
    case unsupportedSchemaVersion(Int)
    case invalidRequest(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedSchemaVersion(version):
            return "Electrical process qualification schema version is unsupported: \(version)."
        case let .invalidRequest(message):
            return "Electrical process qualification request is invalid: \(message)."
        }
    }
}
