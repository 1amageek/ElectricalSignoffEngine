import Foundation
import XcircuitePackage
import ElectricalSignoffCore

public struct ElectricalSignoffRunResult: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = ElectricalSignoffEngineAPI.contractVersion

    public var schemaVersion: Int
    public var runID: String
    public var status: XcircuiteEngineExecutionStatus
    public var axisResults: [ElectricalSignoffAnalysisAxis: XcircuiteEngineResultEnvelope<ElectricalSignoffPayload>]
    public var cornerResults: [String: [ElectricalSignoffAnalysisAxis: XcircuiteEngineResultEnvelope<ElectricalSignoffPayload>]]

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
        status: XcircuiteEngineExecutionStatus,
        axisResults: [ElectricalSignoffAnalysisAxis: XcircuiteEngineResultEnvelope<ElectricalSignoffPayload>],
        cornerResults: [String: [ElectricalSignoffAnalysisAxis: XcircuiteEngineResultEnvelope<ElectricalSignoffPayload>]] = [:]
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
        status = try container.decode(XcircuiteEngineExecutionStatus.self, forKey: .status)
        axisResults = try container.decode([ElectricalSignoffAnalysisAxis: XcircuiteEngineResultEnvelope<ElectricalSignoffPayload>].self, forKey: .axisResults)
        cornerResults = try container.decodeIfPresent(
            [String: [ElectricalSignoffAnalysisAxis: XcircuiteEngineResultEnvelope<ElectricalSignoffPayload>]].self,
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
        _ envelope: XcircuiteEngineResultEnvelope<ElectricalSignoffPayload>,
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
                      && ($0.byteCount == nil || $0.byteCount! >= 0)
              }) else {
            throw ElectricalSignoffError.invalidExecutionResult(
                "envelope identity or payload contract does not match the run result"
            )
        }
    }
}
