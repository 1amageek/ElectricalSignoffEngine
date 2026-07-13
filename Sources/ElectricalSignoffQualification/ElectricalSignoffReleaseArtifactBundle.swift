import Foundation
import CryptoKit
import CircuiteFoundation

public struct ElectricalSignoffReleaseArtifactBundle: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var runID: String
    public var createdAt: Date
    public var gateResult: ArtifactReference
    public var request: ArtifactReference
    public var runResult: ArtifactReference
    public var qualificationSpec: ArtifactReference
    public var qualificationReport: ArtifactReference
    public var qualificationArtifacts: [ArtifactReference]
    public var policy: ArtifactReference
    public var sourceArtifacts: [ArtifactReference]
    public var cornerAxisEvidence: [ArtifactReference]
    public var repairPlan: ArtifactReference?
    public var approvalArtifacts: [ArtifactReference]
    public var plan: ArtifactReference?
    public var actionLog: ArtifactReference?
    public var runManifest: ArtifactReference?
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
        gateResult: ArtifactReference,
        request: ArtifactReference,
        runResult: ArtifactReference,
        qualificationSpec: ArtifactReference,
        qualificationReport: ArtifactReference,
        qualificationArtifacts: [ArtifactReference] = [],
        policy: ArtifactReference,
        sourceArtifacts: [ArtifactReference] = [],
        cornerAxisEvidence: [ArtifactReference] = [],
        repairPlan: ArtifactReference? = nil,
        approvalArtifacts: [ArtifactReference] = [],
        plan: ArtifactReference? = nil,
        actionLog: ArtifactReference? = nil,
        runManifest: ArtifactReference? = nil,
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
            gateResult: try container.decode(ArtifactReference.self, forKey: .gateResult),
            request: try container.decode(ArtifactReference.self, forKey: .request),
            runResult: try container.decode(ArtifactReference.self, forKey: .runResult),
            qualificationSpec: try container.decode(ArtifactReference.self, forKey: .qualificationSpec),
            qualificationReport: try container.decode(ArtifactReference.self, forKey: .qualificationReport),
            qualificationArtifacts: try container.decode([ArtifactReference].self, forKey: .qualificationArtifacts),
            policy: try container.decode(ArtifactReference.self, forKey: .policy),
            sourceArtifacts: try container.decode([ArtifactReference].self, forKey: .sourceArtifacts),
            cornerAxisEvidence: try container.decode([ArtifactReference].self, forKey: .cornerAxisEvidence),
            repairPlan: try container.decodeIfPresent(ArtifactReference.self, forKey: .repairPlan),
            approvalArtifacts: try container.decode([ArtifactReference].self, forKey: .approvalArtifacts),
            plan: try container.decodeIfPresent(ArtifactReference.self, forKey: .plan),
            actionLog: try container.decodeIfPresent(ArtifactReference.self, forKey: .actionLog),
            runManifest: try container.decodeIfPresent(ArtifactReference.self, forKey: .runManifest),
            bundleDigest: try container.decode(String.self, forKey: .bundleDigest),
            schemaVersion: try container.decode(Int.self, forKey: .schemaVersion)
        )
    }

    public var allReferences: [ArtifactReference] {
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
        let required: [(String, ArtifactReference)] = [
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

    public static func digest(runID: String, references: [ArtifactReference]) -> String {
        let canonical = (["runID=\(runID)"] + references.sorted { $0.path < $1.path }.map { reference in
            [
                reference.artifactID,
                reference.path,
                reference.kind.rawValue,
                reference.format.rawValue,
                reference.sha256,
                String(reference.byteCount),
            ].joined(separator: "|")
        }).joined(separator: "\n")
        return SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func validate(_ reference: ArtifactReference, role: String) throws {
        guard !reference.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ElectricalSignoffReleaseArtifactBundleError.missingReference(role: role)
        }
    }

    private static func references(
        gateResult: ArtifactReference,
        request: ArtifactReference,
        runResult: ArtifactReference,
        qualificationSpec: ArtifactReference,
        qualificationReport: ArtifactReference,
        qualificationArtifacts: [ArtifactReference],
        policy: ArtifactReference,
        sourceArtifacts: [ArtifactReference],
        cornerAxisEvidence: [ArtifactReference],
        repairPlan: ArtifactReference?,
        approvalArtifacts: [ArtifactReference],
        plan: ArtifactReference?,
        actionLog: ArtifactReference?,
        runManifest: ArtifactReference?
    ) -> [ArtifactReference] {
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
