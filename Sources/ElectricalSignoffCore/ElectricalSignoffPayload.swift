import Foundation
import CircuiteFoundation

public struct ElectricalSignoffPayload: Sendable, Hashable, Codable {
    public struct Metric: Sendable, Hashable, Codable {
        public var name: String
        public var value: Double
        public var unit: String
        public var limit: Double?
        public var passed: Bool?

        public init(name: String, value: Double, unit: String, limit: Double? = nil, passed: Bool? = nil) {
            self.name = name
            self.value = value
            self.unit = unit
            self.limit = limit
            self.passed = passed
        }
    }

    public struct Finding: Sendable, Hashable, Codable {
        public var code: String
        public var severity: DiagnosticSeverity
        public var message: String
        public var entity: String?
        public var observedValue: Double?
        public var limitValue: Double?
        public var suggestedActions: [String]

        public init(
            code: String,
            severity: DiagnosticSeverity,
            message: String,
            entity: String? = nil,
            observedValue: Double? = nil,
            limitValue: Double? = nil,
            suggestedActions: [String] = []
        ) {
            self.code = code
            self.severity = severity
            self.message = message
            self.entity = entity
            self.observedValue = observedValue
            self.limitValue = limitValue
            self.suggestedActions = suggestedActions
        }
    }

    public struct RepairCandidate: Sendable, Hashable, Codable {
        public var candidateID: String
        public var kind: String
        public var entity: String
        public var rationale: String
        public var actions: [String]

        public init(candidateID: String, kind: String, entity: String, rationale: String, actions: [String]) {
            self.candidateID = candidateID
            self.kind = kind
            self.entity = entity
            self.rationale = rationale
            self.actions = actions
        }
    }

    public struct Provenance: Sendable, Hashable, Codable {
        public var designDigest: String
        public var layoutDigest: String
        public var pdkDigest: String
        public var parasiticDigest: String?
        public var topCell: String
        public var inputArtifactIDs: [String]

        public init(
            designDigest: String,
            layoutDigest: String,
            pdkDigest: String,
            parasiticDigest: String?,
            topCell: String,
            inputArtifactIDs: [String]
        ) {
            self.designDigest = designDigest
            self.layoutDigest = layoutDigest
            self.pdkDigest = pdkDigest
            self.parasiticDigest = parasiticDigest
            self.topCell = topCell
            self.inputArtifactIDs = inputArtifactIDs
        }
    }

    public var axis: ElectricalSignoffAnalysisAxis
    public var cornerID: String?
    public var violationCount: Int
    public var worstMetric: Double?
    public var metricUnit: String?
    public var metrics: [Metric]
    public var findings: [Finding]
    public var repairCandidates: [RepairCandidate]
    public var provenance: Provenance?

    public init(
        violationCount: Int,
        worstMetric: Double? = nil,
        metricUnit: String? = nil,
        axis: ElectricalSignoffAnalysisAxis = .aggregate,
        metrics: [Metric] = [],
        findings: [Finding] = [],
        repairCandidates: [RepairCandidate] = [],
        provenance: Provenance? = nil,
        cornerID: String? = nil
    ) {
        self.axis = axis
        self.cornerID = cornerID
        self.violationCount = violationCount
        self.worstMetric = worstMetric
        self.metricUnit = metricUnit
        self.metrics = metrics
        self.findings = findings
        self.repairCandidates = repairCandidates
        self.provenance = provenance
    }
}
