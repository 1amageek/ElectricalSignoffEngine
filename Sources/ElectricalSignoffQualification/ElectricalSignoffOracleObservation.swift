import Foundation
import ElectricalSignoffCore
import XcircuitePackage

public struct ElectricalSignoffOracleObservation: Sendable, Hashable, Codable {
    public var oracleID: String
    public var toolVersion: String
    public var pdkDigest: String
    public var status: XcircuiteEngineExecutionStatus
    public var violationCount: Int
    public var diagnosticCodes: [String]
    public var metrics: [ElectricalSignoffPayload.Metric]
    public var artifacts: [XcircuiteFileReference]

    public init(
        oracleID: String,
        toolVersion: String,
        pdkDigest: String,
        status: XcircuiteEngineExecutionStatus,
        violationCount: Int,
        diagnosticCodes: [String] = [],
        metrics: [ElectricalSignoffPayload.Metric] = [],
        artifacts: [XcircuiteFileReference] = []
    ) {
        self.oracleID = oracleID
        self.toolVersion = toolVersion
        self.pdkDigest = pdkDigest
        self.status = status
        self.violationCount = violationCount
        self.diagnosticCodes = diagnosticCodes.sorted()
        self.metrics = metrics
        self.artifacts = artifacts
    }

    public var isIndependent: Bool {
        let normalized = oracleID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !normalized.isEmpty
            && normalized != "native"
            && !normalized.contains("electricalsignoffengine")
            && !normalized.contains("native-electrical")
    }

    public func validate() throws {
        guard !oracleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !toolVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !pdkDigest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              isIndependent,
              violationCount >= 0 else {
            throw ElectricalSignoffQualificationError.invalidSpec("oracle observation identity or violation count is invalid")
        }
        guard Set(diagnosticCodes).count == diagnosticCodes.count else {
            throw ElectricalSignoffQualificationError.invalidSpec("oracle diagnostic codes must be unique")
        }
        guard metrics.allSatisfy({
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !$0.unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.value.isFinite
        }), Set(metrics.map(\.name)).count == metrics.count else {
            throw ElectricalSignoffQualificationError.invalidSpec("oracle metrics must have unique finite names and units")
        }
        guard artifacts.allSatisfy({ reference in
            !reference.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && (reference.byteCount == nil || reference.byteCount! >= 0)
        }) else {
            throw ElectricalSignoffQualificationError.invalidSpec("oracle artifact references are invalid")
        }
    }
}
