import Foundation
import ElectricalSignoffCore
import ElectricalSignoffEngine
import ElectricalSignoffEvidence
import CircuiteFoundation

public struct ElectricalSignoffCommand: ElectricalSignoffCommandRunning {
    public init() {}

    public func run(arguments: [String]) async -> Int {
        do {
            let options = try CLIOptions(arguments: arguments)
            if options.help {
                print(Self.usage)
                return 0
            }
            if let corpusSpecPath = options.corpusSpecPath {
                guard options.requestPath == nil, !options.extractTopology else {
                    throw CLIError.conflictingOptions(
                        "--corpus-spec cannot be combined with --request or --extract-topology"
                    )
                }
                let specURL = URL(filePath: corpusSpecPath).standardizedFileURL
                let specData = try Data(contentsOf: specURL)
                let spec = try JSONDecoder().decode(
                    ElectricalSignoffCorpusSpec.self,
                    from: specData
                )
                let projectRoot = options.projectRoot.map { URL(filePath: $0) }
                    ?? specURL.deletingLastPathComponent()
                let support = ElectricalSignoffExecutionSupport(
                    projectRoot: projectRoot,
                    verifyIntegrity: !options.allowUnverifiedInputs,
                    artifactStore: try LocalElectricalArtifactStore(
                        artifactRoot: projectRoot,
                        namespace: ElectricalArtifactNamespace(
                            validating: "artifacts/electrical-signoff"
                        )
                    )
                )
                let oracle = try options.oracleObservationsPath.map {
                    try LocalElectricalSignoffOracle(
                        contentsOf: URL(filePath: $0).standardizedFileURL
                    )
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
            let request = try JSONDecoder().decode(
                ElectricalSignoffRequest.self,
                from: data
            )
            let projectRoot = options.projectRoot.map { URL(filePath: $0) }
                ?? requestURL.deletingLastPathComponent()
            if options.extractTopology {
                let topology = try await ElectricalTopologyExtractionService(
                    projectRoot: projectRoot
                ).extract(request: request)
                let topologyData = try encode(topology: topology, pretty: options.pretty)
                try write(topologyData, outputPath: options.outputPath)
                return 0
            }
            let support = ElectricalSignoffExecutionSupport(
                projectRoot: projectRoot,
                verifyIntegrity: !options.allowUnverifiedInputs,
                artifactStore: try LocalElectricalArtifactStore(
                    artifactRoot: projectRoot,
                    namespace: ElectricalArtifactNamespace(
                        validating: "artifacts/electrical-signoff"
                    )
                )
            )
            let engine = ElectricalSignoffEngine(support: support)
            let axes = options.axis == .aggregate
                ? request.configuration.requiredAxes
                : [options.axis]
            let result = try await engine.execute(request, axes: axes)
            let output = try encode(result: result, pretty: options.pretty)
            try write(output, outputPath: options.outputPath)
            let hasViolations = result.axisResults.values.contains {
                $0.payload.violationCount > 0
            }
            return result.status == ElectricalSignoffExecutionStatus.completed
                && !hasViolations
                ? 0
                : 2
        } catch let error as CLIError {
            printError(code: error.code, message: error.localizedDescription)
            return 1
        } catch {
            printError(
                code: "electrical-signoff.cli.failed",
                message: error.localizedDescription
            )
            return 1
        }
    }

    private func encode(
        result: ElectricalSignoffRunResult,
        pretty: Bool
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(result)
    }

    private func encode(
        topology: ElectricalTopology,
        pretty: Bool
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try encoder.encode(topology)
    }

    private func encode(
        report: ElectricalSignoffCorpusReport,
        pretty: Bool
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(report)
    }

    private func write(_ data: Data, outputPath: String?) throws {
        if let outputPath {
            try data.write(
                to: URL(filePath: outputPath),
                options: Data.WritingOptions.atomic
            )
        } else {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data([10]))
        }
    }

    private func printError(code: String, message: String) {
        let value = ["code": code, "message": message, "status": "failed"]
        do {
            let data = try JSONSerialization.data(
                withJSONObject: value,
                options: [.sortedKeys]
            )
            FileHandle.standardError.write(data)
            FileHandle.standardError.write(Data([10]))
        } catch {
            FileHandle.standardError.write(
                Data("{\"code\":\"electrical-signoff.cli.failed\"}\n".utf8)
            )
        }
    }

    private static let usage = """
    electrical-signoff --request <request.json> [--extract-topology] [--axis <power-integrity|erc|esd|latch-up|aging>] [--project-root <path>] [--output <path>] [--pretty]
    electrical-signoff --corpus-spec <spec.json> [--oracle-observations <oracle.json>] [--project-root <path>] [--output <path>] [--allow-unverified-inputs] [--pretty]
    """
}
