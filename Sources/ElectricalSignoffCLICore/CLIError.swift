import Foundation

enum CLIError: Error, LocalizedError {
    case missingOption(String)
    case missingValue(String)
    case invalidValue(String, String)
    case unknownOption(String)
    case conflictingOptions(String)

    var code: String {
        switch self {
        case .missingOption:
            return "electrical-signoff.cli.missing-option"
        case .missingValue:
            return "electrical-signoff.cli.missing-value"
        case .invalidValue:
            return "electrical-signoff.cli.invalid-value"
        case .unknownOption:
            return "electrical-signoff.cli.unknown-option"
        case .conflictingOptions:
            return "electrical-signoff.cli.conflicting-options"
        }
    }

    var errorDescription: String? {
        switch self {
        case let .missingOption(option):
            return "Required option is missing: \(option)."
        case let .missingValue(option):
            return "Option requires a value: \(option)."
        case let .invalidValue(option, value):
            return "Invalid value \(value) for \(option)."
        case let .unknownOption(option):
            return "Unknown option: \(option)."
        case let .conflictingOptions(message):
            return message
        }
    }
}
