import Foundation

public struct ElectricalSignoffMetricComparison: Sendable, Hashable, Codable {
    public var name: String
    public var expectedValue: Double
    public var actualValue: Double?
    public var unit: String
    public var absoluteTolerance: Double
    public var relativeTolerance: Double
    public var passed: Bool

    public init(
        name: String,
        expectedValue: Double,
        actualValue: Double?,
        unit: String,
        absoluteTolerance: Double,
        relativeTolerance: Double,
        passed: Bool
    ) {
        self.name = name
        self.expectedValue = expectedValue
        self.actualValue = actualValue
        self.unit = unit
        self.absoluteTolerance = absoluteTolerance
        self.relativeTolerance = relativeTolerance
        self.passed = passed
    }
}
