import Foundation
import ElectricalSignoffCore
import CircuiteFoundation

public struct ElectricalSignoffExpectedObservation: Sendable, Hashable, Codable {
    public var status: ElectricalSignoffExecutionStatus
    public var violationCount: Int
    public var diagnosticCodes: [String]
    public var metrics: [ElectricalSignoffMetricExpectation]

    public init(
        status: ElectricalSignoffExecutionStatus,
        violationCount: Int,
        diagnosticCodes: [String] = [],
        metrics: [ElectricalSignoffMetricExpectation] = []
    ) {
        self.status = status
        self.violationCount = violationCount
        self.diagnosticCodes = diagnosticCodes.sorted()
        self.metrics = metrics
    }

    public func validate() throws {
        guard violationCount >= 0 else {
            throw ElectricalSignoffQualificationError.invalidSpec("expected violation count cannot be negative")
        }
        for metric in metrics {
            try metric.validate()
        }
        guard Set(metrics.map(\.name)).count == metrics.count else {
            throw ElectricalSignoffQualificationError.invalidSpec("expected metric names must be unique")
        }
    }
}
