import ElectricalSignoffCore

struct CLIOptions: Sendable {
    var requestPath: String?
    var projectRoot: String?
    var outputPath: String?
    var corpusSpecPath: String?
    var oracleObservationsPath: String?
    var axis: ElectricalSignoffAnalysisAxis
    var pretty: Bool
    var help: Bool
    var allowUnverifiedInputs: Bool
    var extractTopology: Bool

    init(arguments: [String]) throws {
        requestPath = nil
        projectRoot = nil
        outputPath = nil
        corpusSpecPath = nil
        oracleObservationsPath = nil
        axis = .aggregate
        pretty = false
        help = false
        allowUnverifiedInputs = false
        extractTopology = false
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--help", "-h":
                help = true
            case "--pretty":
                pretty = true
            case "--allow-unverified-inputs":
                allowUnverifiedInputs = true
            case "--extract-topology":
                extractTopology = true
            case "--request":
                index += 1
                requestPath = try value(
                    after: argument,
                    index: index,
                    arguments: arguments
                )
            case "--corpus-spec":
                index += 1
                corpusSpecPath = try value(
                    after: argument,
                    index: index,
                    arguments: arguments
                )
            case "--oracle-observations":
                index += 1
                oracleObservationsPath = try value(
                    after: argument,
                    index: index,
                    arguments: arguments
                )
            case "--project-root":
                index += 1
                projectRoot = try value(
                    after: argument,
                    index: index,
                    arguments: arguments
                )
            case "--output":
                index += 1
                outputPath = try value(
                    after: argument,
                    index: index,
                    arguments: arguments
                )
            case "--axis":
                index += 1
                let rawValue = try value(
                    after: argument,
                    index: index,
                    arguments: arguments
                )
                guard let parsed = ElectricalSignoffAnalysisAxis(rawValue: rawValue),
                      parsed != .aggregate else {
                    throw CLIError.invalidValue("--axis", rawValue)
                }
                axis = parsed
            default:
                throw CLIError.unknownOption(argument)
            }
            index += 1
        }
        if oracleObservationsPath != nil && corpusSpecPath == nil {
            throw CLIError.conflictingOptions(
                "--oracle-observations requires --corpus-spec"
            )
        }
        let selectedModes = [
            requestPath != nil,
            corpusSpecPath != nil,
        ].filter { $0 }.count
        if selectedModes > 1 {
            throw CLIError.conflictingOptions(
                "--request and --corpus-spec are mutually exclusive"
            )
        }
    }

    private func value(
        after option: String,
        index: Int,
        arguments: [String]
    ) throws -> String {
        guard index < arguments.count, !arguments[index].hasPrefix("--") else {
            throw CLIError.missingValue(option)
        }
        return arguments[index]
    }
}
