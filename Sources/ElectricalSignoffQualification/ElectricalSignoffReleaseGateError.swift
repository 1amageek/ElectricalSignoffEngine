import Foundation

public enum ElectricalSignoffReleaseGateError: Error, Sendable, Hashable, Codable, LocalizedError {
    case invalidPolicy(String)
    case invalidRequest(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidPolicy(message):
            return "Electrical signoff release gate policy is invalid: \(message)"
        case let .invalidRequest(message):
            return "Electrical signoff release gate request is invalid: \(message)"
        }
    }
}
