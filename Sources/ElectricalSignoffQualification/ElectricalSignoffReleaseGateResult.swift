import Foundation

public struct ElectricalSignoffReleaseGateResult: Sendable, Hashable, Codable {
    public enum Status: String, Sendable, Hashable, Codable {
        case passed
        case blocked
        case failed
    }

    public struct Check: Sendable, Hashable, Codable {
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

    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var runID: String
    public var policyID: String
    public var pdkDigest: String
    public var evaluatedAt: Date
    public var status: Status
    public var checks: [Check]
    public var failureCodes: [String]

    public init(
        runID: String,
        policyID: String,
        pdkDigest: String,
        evaluatedAt: Date,
        status: Status,
        checks: [Check],
        failureCodes: [String] = [],
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.policyID = policyID
        self.pdkDigest = pdkDigest
        self.evaluatedAt = evaluatedAt
        self.status = status
        self.checks = checks
        self.failureCodes = Array(Set(failureCodes)).sorted()
    }

    public var isReleaseReady: Bool {
        status == .passed && failureCodes.isEmpty
    }
}
