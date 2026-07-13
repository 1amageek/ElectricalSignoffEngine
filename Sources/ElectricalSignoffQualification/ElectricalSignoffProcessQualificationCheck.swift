import Foundation

public struct ElectricalSignoffProcessQualificationCheck: Sendable, Hashable, Codable {
    public var checkID: String
    public var passed: Bool
    public var observed: String
    public var expected: String
    public var failureCode: String?

    public init(
        checkID: String,
        passed: Bool,
        observed: String,
        expected: String,
        failureCode: String? = nil
    ) {
        self.checkID = checkID
        self.passed = passed
        self.observed = observed
        self.expected = expected
        self.failureCode = failureCode
    }
}
