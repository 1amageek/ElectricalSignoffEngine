import Foundation
import ElectricalSignoffCore
import ElectricalSignoffEngine
import ElectricalSignoffEvidence
import CircuiteFoundation

@main
public struct ElectricalSignoffCLI {
    public static func main() async {
        let code = await run(arguments: Array(CommandLine.arguments.dropFirst()))
        Foundation.exit(Int32(code))
    }

    public static func run(arguments: [String]) async -> Int {
        do {
            let options = try CLIOptions(arguments: arguments)
            if options.help {
                print(usage)
                return 0
            }
            if let corpusSpecPath = options.corpusSpecPath {
                guard options.requestPath == nil, !options.extractTopology else {
                    throw CLIError.conflictingOptions("--corpus-spec cannot be combined with --request or --extract-topology")
                }
                let specURL = URL(filePath: corpusSpecPath).standardizedFileURL
                let specData = try Data(contentsOf: specURL)
                let spec = try JSONDecoder().decode(ElectricalSignoffCorpusSpec.self, from: specData)
                let projectRoot = options.projectRoot.map { URL(filePath: $0) }
                    ?? specURL.deletingLastPathComponent()
                let support = ElectricalSignoffExecutionSupport(
                    projectRoot: projectRoot,
                    verifyIntegrity: !options.allowUnverifiedInputs,
                    artifactStore: LocalElectricalArtifactStore(projectRoot: projectRoot)
                )
                let oracle = try options.oracleObservationsPath.map {
                    try LocalElectricalSignoffOracle(contentsOf: URL(filePath: $0).standardizedFileURL)
                }
                let report = try await ElectricalSignoffCorpusRunner(
                    engine: ElectricalSignoffEngine(support: support),
                    oracle: oracle
                ).run(spec: spec)
                let output = try encode(report: report, pretty: options.pretty)
                try write(output, outputPath: options.outputPath)
                return report.passed ? 0 : 2
            }

            guard let requestPath = options.requestPath else {
                throw CLIError.missingOption("--request or --corpus-spec")
            }
            let requestURL = URL(filePath: requestPath).standardizedFileURL
            let data = try Data(contentsOf: requestURL)
            let request = try JSONDecoder().decode(ElectricalSignoffRequest.self, from: data)
            let projectRoot = options.projectRoot.map { URL(filePath: $0) }
                ?? requestURL.deletingLastPathComponent()
            if options.extractTopology {
                let topology = try await ElectricalTopologyExtractionService(projectRoot: projectRoot).extract(request: request)
                let topologyData = try encode(topology: topology, pretty: options.pretty)
                try write(topologyData, outputPath: options.outputPath)
                return 0
            }
            let support = ElectricalSignoffExecutionSupport(
                projectRoot: projectRoot,
                verifyIntegrity: !options.allowUnverifiedInputs,
                artifactStore: LocalElectricalArtifactStore(projectRoot: projectRoot)
            )
            let engine = ElectricalSignoffEngine(support: support)
            let axes = options.axis == .aggregate ? request.configuration.requiredAxes : [options.axis]
            let result = try await engine.execute(request, axes: axes)
            let output = try encode(result: result, pretty: options.pretty)
            if let outputPath = options.outputPath {
                let outputURL = URL(filePath: outputPath)
                try output.write(to: outputURL, options: Data.WritingOptions.atomic)
            } else {
                FileHandle.standardOutput.write(output)
                FileHandle.standardOutput.write(Data([10]))
            }
            let hasViolations = result.axisResults.values.contains { $0.payload.violationCount > 0 }
            return result.status == ElectricalSignoffExecutionStatus.completed && !hasViolations ? 0 : 2
        } catch let error as CLIError {
            printError(code: error.code, message: error.localizedDescription)
            return 1
        } catch {
            printError(code: "electrical-signoff.cli.failed", message: error.localizedDescription)
            return 1
        }
    }

    private static func encode(result: ElectricalSignoffRunResult, pretty: Bool) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(result)
    }

    private static func encode(topology: ElectricalTopology, pretty: Bool) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try encoder.encode(topology)
    }

    private static func encode(report: ElectricalSignoffCorpusReport, pretty: Bool) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(report)
    }

    private static func write(_ data: Data, outputPath: String?) throws {
        if let outputPath {
            try data.write(to: URL(filePath: outputPath), options: Data.WritingOptions.atomic)
        } else {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data([10]))
        }
    }

    private static func printError(code: String, message: String) {
        let value: [String: String] = ["code": code, "message": message, "status": "failed"]
        do {
            let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
            FileHandle.standardError.write(data)
            FileHandle.standardError.write(Data([10]))
        } catch {
            FileHandle.standardError.write(Data("{\"code\":\"electrical-signoff.cli.failed\"}\n".utf8))
        }
    }

    private static let usage = """
    electrical-signoff --request <request.json> [--extract-topology] [--axis <power-integrity|erc|esd|latch-up|aging>] [--project-root <path>] [--output <path>] [--pretty]
    electrical-signoff --corpus-spec <spec.json> [--oracle-observations <oracle.json>] [--project-root <path>] [--output <path>] [--allow-unverified-inputs] [--pretty]
    """
}

private struct CLIOptions: Sendable {
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
                requestPath = try value(after: argument, index: index, arguments: arguments)
            case "--corpus-spec":
                index += 1
                corpusSpecPath = try value(after: argument, index: index, arguments: arguments)
            case "--oracle-observations":
                index += 1
                oracleObservationsPath = try value(after: argument, index: index, arguments: arguments)
            case "--project-root":
                index += 1
                projectRoot = try value(after: argument, index: index, arguments: arguments)
            case "--output":
                index += 1
                outputPath = try value(after: argument, index: index, arguments: arguments)
            case "--axis":
                index += 1
                let rawValue = try value(after: argument, index: index, arguments: arguments)
                guard let parsed = ElectricalSignoffAnalysisAxis(rawValue: rawValue), parsed != .aggregate else {
                    throw CLIError.invalidValue("--axis", rawValue)
                }
                axis = parsed
            default:
                throw CLIError.unknownOption(argument)
            }
            index += 1
        }
        if oracleObservationsPath != nil && corpusSpecPath == nil {
            throw CLIError.conflictingOptions("--oracle-observations requires --corpus-spec")
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

    private func value(after option: String, index: Int, arguments: [String]) throws -> String {
        guard index < arguments.count, !arguments[index].hasPrefix("--") else {
            throw CLIError.missingValue(option)
        }
        return arguments[index]
    }
}

private enum CLIError: Error, LocalizedError {
    case missingOption(String)
    case missingValue(String)
    case invalidValue(String, String)
    case unknownOption(String)
    case conflictingOptions(String)

    var code: String {
        switch self {
        case .missingOption: return "electrical-signoff.cli.missing-option"
        case .missingValue: return "electrical-signoff.cli.missing-value"
        case .invalidValue: return "electrical-signoff.cli.invalid-value"
        case .unknownOption: return "electrical-signoff.cli.unknown-option"
        case .conflictingOptions: return "electrical-signoff.cli.conflicting-options"
        }
    }

    var errorDescription: String? {
        switch self {
        case let .missingOption(option): return "Required option is missing: \(option)."
        case let .missingValue(option): return "Option requires a value: \(option)."
        case let .invalidValue(option, value): return "Invalid value \(value) for \(option)."
        case let .unknownOption(option): return "Unknown option: \(option)."
        case let .conflictingOptions(message): return message
        }
    }
}
