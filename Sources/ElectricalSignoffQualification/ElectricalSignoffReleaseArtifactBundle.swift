import Foundation
import XcircuitePackage

public struct ElectricalSignoffReleaseArtifactBundle: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var runID: String
    public var createdAt: Date
    public var gateResult: XcircuiteFileReference
    public var request: XcircuiteFileReference
    public var runResult: XcircuiteFileReference
    public var qualificationSpec: XcircuiteFileReference
    public var qualificationReport: XcircuiteFileReference
    public var qualificationArtifacts: [XcircuiteFileReference]
    public var policy: XcircuiteFileReference
    public var sourceArtifacts: [XcircuiteFileReference]
    public var cornerAxisEvidence: [XcircuiteFileReference]
    public var repairPlan: XcircuiteFileReference?
    public var approvalArtifacts: [XcircuiteFileReference]
    public var plan: XcircuiteFileReference?
    public var actionLog: XcircuiteFileReference?
    public var runManifest: XcircuiteFileReference?
    public var bundleDigest: String

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case runID
        case createdAt
        case gateResult
        case request
        case runResult
        case qualificationSpec
        case qualificationReport
        case qualificationArtifacts
        case policy
        case sourceArtifacts
        case cornerAxisEvidence
        case repairPlan
        case approvalArtifacts
        case plan
        case actionLog
        case runManifest
        case bundleDigest
    }

    public init(
        runID: String,
        createdAt: Date,
        gateResult: XcircuiteFileReference,
        request: XcircuiteFileReference,
        runResult: XcircuiteFileReference,
        qualificationSpec: XcircuiteFileReference,
        qualificationReport: XcircuiteFileReference,
        qualificationArtifacts: [XcircuiteFileReference] = [],
        policy: XcircuiteFileReference,
        sourceArtifacts: [XcircuiteFileReference] = [],
        cornerAxisEvidence: [XcircuiteFileReference] = [],
        repairPlan: XcircuiteFileReference? = nil,
        approvalArtifacts: [XcircuiteFileReference] = [],
        plan: XcircuiteFileReference? = nil,
        actionLog: XcircuiteFileReference? = nil,
        runManifest: XcircuiteFileReference? = nil,
        bundleDigest: String? = nil,
        schemaVersion: Int = Self.currentSchemaVersion
    ) throws {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.createdAt = createdAt
        self.gateResult = gateResult
        self.request = request
        self.runResult = runResult
        self.qualificationSpec = qualificationSpec
        self.qualificationReport = qualificationReport
        self.qualificationArtifacts = qualificationArtifacts.sorted { $0.path < $1.path }
        self.policy = policy
        self.sourceArtifacts = sourceArtifacts.sorted { $0.path < $1.path }
        self.cornerAxisEvidence = cornerAxisEvidence.sorted { $0.path < $1.path }
        self.repairPlan = repairPlan
        self.approvalArtifacts = approvalArtifacts.sorted { $0.path < $1.path }
        self.plan = plan
        self.actionLog = actionLog
        self.runManifest = runManifest
        let references = Self.references(
            gateResult: gateResult,
            request: request,
            runResult: runResult,
            qualificationSpec: qualificationSpec,
            qualificationReport: qualificationReport,
            qualificationArtifacts: qualificationArtifacts,
            policy: policy,
            sourceArtifacts: sourceArtifacts,
            cornerAxisEvidence: cornerAxisEvidence,
            repairPlan: repairPlan,
            approvalArtifacts: approvalArtifacts,
            plan: plan,
            actionLog: actionLog,
            runManifest: runManifest
        )
        self.bundleDigest = bundleDigest ?? Self.digest(runID: runID, references: references)
        try validate()
        if let bundleDigest, bundleDigest != self.bundleDigest {
            throw ElectricalSignoffReleaseArtifactBundleError.digestMismatch(
                expected: bundleDigest,
                actual: self.bundleDigest
            )
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            runID: try container.decode(String.self, forKey: .runID),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            gateResult: try container.decode(XcircuiteFileReference.self, forKey: .gateResult),
            request: try container.decode(XcircuiteFileReference.self, forKey: .request),
            runResult: try container.decode(XcircuiteFileReference.self, forKey: .runResult),
            qualificationSpec: try container.decode(XcircuiteFileReference.self, forKey: .qualificationSpec),
            qualificationReport: try container.decode(XcircuiteFileReference.self, forKey: .qualificationReport),
            qualificationArtifacts: try container.decode([XcircuiteFileReference].self, forKey: .qualificationArtifacts),
            policy: try container.decode(XcircuiteFileReference.self, forKey: .policy),
            sourceArtifacts: try container.decode([XcircuiteFileReference].self, forKey: .sourceArtifacts),
            cornerAxisEvidence: try container.decode([XcircuiteFileReference].self, forKey: .cornerAxisEvidence),
            repairPlan: try container.decodeIfPresent(XcircuiteFileReference.self, forKey: .repairPlan),
            approvalArtifacts: try container.decode([XcircuiteFileReference].self, forKey: .approvalArtifacts),
            plan: try container.decodeIfPresent(XcircuiteFileReference.self, forKey: .plan),
            actionLog: try container.decodeIfPresent(XcircuiteFileReference.self, forKey: .actionLog),
            runManifest: try container.decodeIfPresent(XcircuiteFileReference.self, forKey: .runManifest),
            bundleDigest: try container.decode(String.self, forKey: .bundleDigest),
            schemaVersion: try container.decode(Int.self, forKey: .schemaVersion)
        )
    }

    public var allReferences: [XcircuiteFileReference] {
        Self.references(
            gateResult: gateResult,
            request: request,
            runResult: runResult,
            qualificationSpec: qualificationSpec,
            qualificationReport: qualificationReport,
            qualificationArtifacts: qualificationArtifacts,
            policy: policy,
            sourceArtifacts: sourceArtifacts,
            cornerAxisEvidence: cornerAxisEvidence,
            repairPlan: repairPlan,
            approvalArtifacts: approvalArtifacts,
            plan: plan,
            actionLog: actionLog,
            runManifest: runManifest
        )
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ElectricalSignoffReleaseArtifactBundleError.unsupportedSchemaVersion(schemaVersion)
        }
        guard !runID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ElectricalSignoffReleaseArtifactBundleError.invalidRunID
        }
        let required: [(String, XcircuiteFileReference)] = [
            ("gate-result", gateResult),
            ("request", request),
            ("run-result", runResult),
            ("qualification-spec", qualificationSpec),
            ("qualification-report", qualificationReport),
            ("policy", policy),
        ]
        for (role, reference) in required {
            try validate(reference, role: role)
        }
        for reference in qualificationArtifacts + sourceArtifacts + cornerAxisEvidence + approvalArtifacts {
            try validate(reference, role: "supporting-artifact")
        }
        for (role, reference) in [
            ("repair-plan", repairPlan),
            ("plan", plan),
            ("action-log", actionLog),
            ("run-manifest", runManifest),
        ] {
            if let reference {
                try validate(reference, role: role)
            }
        }
        var paths = Set<String>()
        for reference in allReferences {
            guard paths.insert(reference.path).inserted else {
                throw ElectricalSignoffReleaseArtifactBundleError.duplicatePath(path: reference.path)
            }
        }
        let expectedDigest = Self.digest(runID: runID, references: allReferences)
        guard expectedDigest == bundleDigest else {
            throw ElectricalSignoffReleaseArtifactBundleError.digestMismatch(
                expected: expectedDigest,
                actual: bundleDigest
            )
        }
    }

    public static func digest(runID: String, references: [XcircuiteFileReference]) -> String {
        let canonical = (["runID=\(runID)"] + references.sorted { $0.path < $1.path }.map { reference in
            [
                reference.artifactID ?? "",
                reference.path,
                reference.kind.rawValue,
                reference.format.rawValue,
                reference.sha256 ?? "",
                reference.byteCount.map(String.init) ?? "",
                reference.producedByRunID ?? "",
                reference.verifiedByRunID ?? "",
            ].joined(separator: "|")
        }).joined(separator: "\n")
        return XcircuiteHasher().sha256(data: Data(canonical.utf8))
    }

    private func validate(_ reference: XcircuiteFileReference, role: String) throws {
        guard !reference.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ElectricalSignoffReleaseArtifactBundleError.missingReference(role: role)
        }
        guard reference.sha256 != nil, reference.byteCount != nil else {
            throw ElectricalSignoffReleaseArtifactBundleError.missingIntegrity(path: reference.path)
        }
    }

    private static func references(
        gateResult: XcircuiteFileReference,
        request: XcircuiteFileReference,
        runResult: XcircuiteFileReference,
        qualificationSpec: XcircuiteFileReference,
        qualificationReport: XcircuiteFileReference,
        qualificationArtifacts: [XcircuiteFileReference],
        policy: XcircuiteFileReference,
        sourceArtifacts: [XcircuiteFileReference],
        cornerAxisEvidence: [XcircuiteFileReference],
        repairPlan: XcircuiteFileReference?,
        approvalArtifacts: [XcircuiteFileReference],
        plan: XcircuiteFileReference?,
        actionLog: XcircuiteFileReference?,
        runManifest: XcircuiteFileReference?
    ) -> [XcircuiteFileReference] {
        var references = [gateResult, request, runResult, qualificationSpec, qualificationReport]
        references.append(contentsOf: qualificationArtifacts)
        references.append(policy)
        references.append(contentsOf: sourceArtifacts)
        references.append(contentsOf: cornerAxisEvidence)
        if let repairPlan {
            references.append(repairPlan)
        }
        references.append(contentsOf: approvalArtifacts)
        if let plan {
            references.append(plan)
        }
        if let actionLog {
            references.append(actionLog)
        }
        if let runManifest {
            references.append(runManifest)
        }
        return references
    }
}
