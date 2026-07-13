import Foundation

public struct ElectricalProcessRuleSet: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public struct CornerRule: Sendable, Hashable, Codable {
        public var cornerID: String
        public var rules: ElectricalTopology.RuleSet

        public init(cornerID: String, rules: ElectricalTopology.RuleSet) {
            self.cornerID = cornerID
            self.rules = rules
        }
    }

    public var schemaVersion: Int
    public var pdkDigest: String
    public var processID: String
    public var pdkVersion: String
    public var cornerRules: [CornerRule]

    public init(
        pdkDigest: String,
        processID: String,
        pdkVersion: String,
        cornerRules: [CornerRule],
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.pdkDigest = pdkDigest
        self.processID = processID
        self.pdkVersion = pdkVersion
        self.cornerRules = cornerRules
    }

    public func ruleSet(for cornerID: String) -> ElectricalTopology.RuleSet? {
        cornerRules.first { $0.cornerID == cornerID }?.rules
    }
}
