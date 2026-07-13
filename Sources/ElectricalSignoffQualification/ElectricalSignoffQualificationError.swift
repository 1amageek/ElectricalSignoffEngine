import Foundation

public enum ElectricalSignoffQualificationError: Error, Sendable, Hashable, Codable, LocalizedError {
    case invalidSpec(String)
    case duplicateCaseID(String)
    case missingAxisResult(String)
    case oracleUnavailable(String)
    case oracleNotIndependent(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidSpec(message):
            return "Electrical signoff qualification spec is invalid: \(message)"
        case let .duplicateCaseID(caseID):
            return "Electrical signoff qualification case ID is duplicated: \(caseID)"
        case let .missingAxisResult(axis):
            return "Electrical signoff qualification result is missing axis: \(axis)"
        case let .oracleUnavailable(caseID):
            return "Independent electrical signoff oracle is unavailable for case \(caseID)."
        case let .oracleNotIndependent(oracleID):
            return "Electrical signoff oracle is not independent: \(oracleID)"
        }
    }
}
