import Foundation
import CircuiteFoundation

public struct ElectricalSignoffPayload: Sendable, Hashable, Codable {
    public struct AnalysisCoverage: Sendable, Hashable, Codable {
        public var expectedEntityIDs: [String]
        public var analyzedEntityIDs: [String]

        public init(
            expectedEntityIDs: [String],
            analyzedEntityIDs: [String]
        ) {
            self.expectedEntityIDs = Array(Set(expectedEntityIDs)).sorted()
            self.analyzedEntityIDs = Array(Set(analyzedEntityIDs)).sorted()
        }

        public var omittedEntityIDs: [String] {
            Array(
                Set(expectedEntityIDs).subtracting(analyzedEntityIDs)
            ).sorted()
        }

        public var unexpectedEntityIDs: [String] {
            Array(
                Set(analyzedEntityIDs).subtracting(expectedEntityIDs)
            ).sorted()
        }

        public var isComplete: Bool {
            let canonicalExpected = Array(Set(expectedEntityIDs)).sorted()
            let canonicalAnalyzed = Array(Set(analyzedEntityIDs)).sorted()
            return !expectedEntityIDs.isEmpty
                && expectedEntityIDs.allSatisfy {
                    !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                && analyzedEntityIDs.allSatisfy {
                    !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                && expectedEntityIDs == canonicalExpected
                && analyzedEntityIDs == canonicalAnalyzed
                && expectedEntityIDs == analyzedEntityIDs
        }

        public static let unassessed = AnalysisCoverage(
            expectedEntityIDs: [],
            analyzedEntityIDs: []
        )
    }

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
    public var analysisCoverage: AnalysisCoverage

    public init(
        violationCount: Int,
        worstMetric: Double? = nil,
        metricUnit: String? = nil,
        axis: ElectricalSignoffAnalysisAxis = .aggregate,
        metrics: [Metric] = [],
        findings: [Finding] = [],
        repairCandidates: [RepairCandidate] = [],
        provenance: Provenance? = nil,
        analysisCoverage: AnalysisCoverage = .unassessed,
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
        self.analysisCoverage = analysisCoverage
    }

    private enum CodingKeys: String, CodingKey {
        case axis
        case cornerID
        case violationCount
        case worstMetric
        case metricUnit
        case metrics
        case findings
        case repairCandidates
        case provenance
        case analysisCoverage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        axis = try container.decode(
            ElectricalSignoffAnalysisAxis.self,
            forKey: .axis
        )
        cornerID = try container.decodeIfPresent(String.self, forKey: .cornerID)
        violationCount = try container.decode(Int.self, forKey: .violationCount)
        worstMetric = try container.decodeIfPresent(Double.self, forKey: .worstMetric)
        metricUnit = try container.decodeIfPresent(String.self, forKey: .metricUnit)
        metrics = try container.decode([Metric].self, forKey: .metrics)
        findings = try container.decode([Finding].self, forKey: .findings)
        repairCandidates = try container.decode(
            [RepairCandidate].self,
            forKey: .repairCandidates
        )
        provenance = try container.decodeIfPresent(Provenance.self, forKey: .provenance)
        analysisCoverage = try container.decodeIfPresent(
            AnalysisCoverage.self,
            forKey: .analysisCoverage
        ) ?? .unassessed
    }
}
