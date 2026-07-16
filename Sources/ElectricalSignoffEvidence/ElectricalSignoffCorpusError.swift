import Foundation

public enum ElectricalSignoffCorpusError: Error, Sendable, Hashable, Codable, LocalizedError {
    case invalidSpec(String)
    case duplicateCaseID(String)
    case missingAxisResult(String)
    case oracleUnavailable(String)
    case oracleEvidenceUnbound(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidSpec(message):
            return "Electrical signoff corpus spec is invalid: \(message)"
        case let .duplicateCaseID(caseID):
            return "Electrical signoff corpus case ID is duplicated: \(caseID)"
        case let .missingAxisResult(axis):
            return "Electrical signoff corpus result is missing axis: \(axis)"
        case let .oracleUnavailable(caseID):
            return "Electrical signoff oracle observation is unavailable for case \(caseID)."
        case let .oracleEvidenceUnbound(oracleID):
            return "Electrical signoff oracle evidence is not externally bound: \(oracleID)"
        }
    }
}
