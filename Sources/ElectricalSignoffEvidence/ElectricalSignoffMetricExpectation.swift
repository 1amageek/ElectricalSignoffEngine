import Foundation

public struct ElectricalSignoffMetricExpectation: Sendable, Hashable, Codable {
    public var name: String
    public var expectedValue: Double
    public var unit: String
    public var absoluteTolerance: Double
    public var relativeTolerance: Double

    public init(
        name: String,
        expectedValue: Double,
        unit: String,
        absoluteTolerance: Double = 0,
        relativeTolerance: Double = 0
    ) {
        self.name = name
        self.expectedValue = expectedValue
        self.unit = unit
        self.absoluteTolerance = absoluteTolerance
        self.relativeTolerance = relativeTolerance
    }

    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ElectricalSignoffCorpusError.invalidSpec("metric names are required")
        }
        guard expectedValue.isFinite,
              absoluteTolerance.isFinite,
              absoluteTolerance >= 0,
              relativeTolerance.isFinite,
              relativeTolerance >= 0 else {
            throw ElectricalSignoffCorpusError.invalidSpec("metric expectations must be finite and non-negative")
        }
    }

    public func matches(_ actualValue: Double) -> Bool {
        let tolerance = max(absoluteTolerance, abs(expectedValue) * relativeTolerance)
        return abs(actualValue - expectedValue) <= tolerance
    }
}
