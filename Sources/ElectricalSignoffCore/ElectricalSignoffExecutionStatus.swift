import Foundation

/// Lifecycle status for an electrical signoff axis result.
public enum ElectricalSignoffExecutionStatus: String, Sendable, Hashable, Codable {
    case completed
    case failed
    case blocked
    case cancelled
}
