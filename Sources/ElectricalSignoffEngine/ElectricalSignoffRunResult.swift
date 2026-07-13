import Foundation
import CircuiteFoundation
import ElectricalSignoffCore

public struct ElectricalSignoffRunResult: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = ElectricalSignoffEngineAPI.contractVersion

    public var schemaVersion: Int
    public var runID: String
    public var status: ElectricalSignoffExecutionStatus
    public var axisResults: [ElectricalSignoffAnalysisAxis: ElectricalSignoffResult]
    public var cornerResults: [String: [ElectricalSignoffAnalysisAxis: ElectricalSignoffResult]]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case runID
        case status
        case axisResults
        case cornerResults
    }

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        runID: String,
        status: ElectricalSignoffExecutionStatus,
        axisResults: [ElectricalSignoffAnalysisAxis: ElectricalSignoffResult],
        cornerResults: [String: [ElectricalSignoffAnalysisAxis: ElectricalSignoffResult]] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.status = status
        self.axisResults = axisResults
        self.cornerResults = cornerResults
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        runID = try container.decode(String.self, forKey: .runID)
        status = try container.decode(ElectricalSignoffExecutionStatus.self, forKey: .status)
        axisResults = try container.decode([ElectricalSignoffAnalysisAxis: ElectricalSignoffResult].self, forKey: .axisResults)
        cornerResults = try container.decodeIfPresent(
            [String: [ElectricalSignoffAnalysisAxis: ElectricalSignoffResult]].self,
            forKey: .cornerResults
        ) ?? [:]
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ElectricalSignoffError.schemaVersionUnsupported(schemaVersion)
        }
        guard !runID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              runID != ".", runID != "..",
              !runID.contains("/"), !runID.contains("\\") else {
            throw ElectricalSignoffError.invalidRequest("run result run ID is not path-safe")
        }
        for (axis, envelope) in axisResults {
            try validate(envelope, axis: axis, cornerID: nil)
        }
        for (cornerID, results) in cornerResults {
            guard !cornerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ElectricalSignoffError.invalidExecutionResult("corner ID is empty")
            }
            for (axis, envelope) in results {
                try validate(envelope, axis: axis, cornerID: cornerID)
            }
        }
    }

    private func validate(
        _ envelope: ElectricalSignoffResult,
        axis: ElectricalSignoffAnalysisAxis,
        cornerID: String?
    ) throws {
        guard axis != .aggregate,
              envelope.schemaVersion == Self.currentSchemaVersion,
              envelope.runID == runID,
              envelope.payload.axis == axis,
              cornerID.map({ envelope.payload.cornerID == $0 }) ?? true,
              envelope.payload.violationCount >= 0,
              envelope.artifacts.allSatisfy({
                  !$0.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && $0.byteCount >= 0
              }) else {
            throw ElectricalSignoffError.invalidExecutionResult(
                "envelope identity or payload contract does not match the run result"
            )
        }
    }
}
