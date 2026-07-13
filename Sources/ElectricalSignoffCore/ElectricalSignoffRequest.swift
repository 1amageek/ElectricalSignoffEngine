import Foundation
import XcircuitePackage
import LogicIR
import PowerIntent
import PDKCore
import PhysicalDesignCore

public struct ElectricalSignoffRequest: XcircuiteEngineRequest {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var runID: String
    public var inputs: [XcircuiteFileReference]

    public var design: LogicDesignReference
    public var physicalDesign: PhysicalDesignReference
    public var pdk: PDKReference
    public var powerIntent: PowerIntentReference?
    public var parasitics: XcircuiteFileReference?
    public var topologyArtifact: XcircuiteFileReference?
    public var topologyProfileArtifact: XcircuiteFileReference?
    public var processRuleArtifact: XcircuiteFileReference?
    public var configuration: ElectricalSignoffConfiguration

    public init(
        runID: String,
        inputs: [XcircuiteFileReference],
        design: LogicDesignReference,
        physicalDesign: PhysicalDesignReference,
        pdk: PDKReference,
        powerIntent: PowerIntentReference? = nil,
        parasitics: XcircuiteFileReference? = nil,
        topologyArtifact: XcircuiteFileReference? = nil,
        topologyProfileArtifact: XcircuiteFileReference? = nil,
        processRuleArtifact: XcircuiteFileReference? = nil,
        configuration: ElectricalSignoffConfiguration = ElectricalSignoffConfiguration()
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        self.inputs = inputs
        self.design = design
        self.physicalDesign = physicalDesign
        self.pdk = pdk
        self.powerIntent = powerIntent
        self.parasitics = parasitics
        self.topologyArtifact = topologyArtifact
        self.topologyProfileArtifact = topologyProfileArtifact
        self.processRuleArtifact = processRuleArtifact
        self.configuration = configuration
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case runID
        case inputs
        case design
        case physicalDesign
        case pdk
        case powerIntent
        case parasitics
        case topologyArtifact
        case topologyProfileArtifact
        case processRuleArtifact
        case configuration
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        runID = try container.decode(String.self, forKey: .runID)
        inputs = try container.decode([XcircuiteFileReference].self, forKey: .inputs)
        design = try container.decode(LogicDesignReference.self, forKey: .design)
        physicalDesign = try container.decode(PhysicalDesignReference.self, forKey: .physicalDesign)
        pdk = try container.decode(PDKReference.self, forKey: .pdk)
        powerIntent = try container.decodeIfPresent(PowerIntentReference.self, forKey: .powerIntent)
        parasitics = try container.decodeIfPresent(XcircuiteFileReference.self, forKey: .parasitics)
        topologyArtifact = try container.decodeIfPresent(XcircuiteFileReference.self, forKey: .topologyArtifact)
        topologyProfileArtifact = try container.decodeIfPresent(XcircuiteFileReference.self, forKey: .topologyProfileArtifact)
        processRuleArtifact = try container.decodeIfPresent(XcircuiteFileReference.self, forKey: .processRuleArtifact)
        configuration = try container.decodeIfPresent(ElectricalSignoffConfiguration.self, forKey: .configuration)
            ?? ElectricalSignoffConfiguration()
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ElectricalSignoffError.schemaVersionUnsupported(schemaVersion)
        }
        guard isSafePathComponent(runID) else {
            throw ElectricalSignoffError.invalidRequest(
                "runID must be a non-empty path-safe component"
            )
        }
        try validate(reference: design.artifact, role: "design")
        try validate(reference: physicalDesign.layoutArtifact, role: "physical-design")
        try validate(reference: pdk.manifest, role: "pdk")
        for reference in inputs {
            try validate(reference: reference, role: "input")
        }
        if let powerIntent {
            try validate(reference: powerIntent.artifact, role: "power-intent")
            guard powerIntent.designDigest == design.designDigest else {
                throw ElectricalSignoffError.digestMismatch(
                    kind: "power-intent design",
                    expected: design.designDigest,
                    actual: powerIntent.designDigest
                )
            }
        }
        for (role, reference) in [
            ("parasitic", parasitics),
            ("topology", topologyArtifact),
            ("topology-profile", topologyProfileArtifact),
            ("process-rules", processRuleArtifact),
        ] {
            if let reference {
                try validate(reference: reference, role: role)
            }
        }
        guard !design.topDesignName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !design.designDigest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !physicalDesign.topCell.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !physicalDesign.layoutDigest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !pdk.processID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !pdk.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !pdk.digest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ElectricalSignoffError.invalidRequest(
                "design, physical design and PDK identities are required"
            )
        }
        var referencesByPath: [String: XcircuiteFileReference] = [:]
        for reference in allReferences {
            if let existing = referencesByPath[reference.path], !compatibleArtifactReferences(existing, reference) {
                throw ElectricalSignoffError.conflictingArtifactReferences(path: reference.path)
            }
            referencesByPath[reference.path] = reference
        }
        try configuration.validate()
    }

    private var allReferences: [XcircuiteFileReference] {
        var references = inputs
        references.append(design.artifact)
        references.append(physicalDesign.layoutArtifact)
        references.append(pdk.manifest)
        if let powerIntent {
            references.append(powerIntent.artifact)
        }
        if let parasitics {
            references.append(parasitics)
        }
        if let topologyArtifact {
            references.append(topologyArtifact)
        }
        if let topologyProfileArtifact {
            references.append(topologyProfileArtifact)
        }
        if let processRuleArtifact {
            references.append(processRuleArtifact)
        }
        return references
    }

    private func validate(reference: XcircuiteFileReference, role: String) throws {
        guard !reference.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ElectricalSignoffError.invalidRequest("\(role) artifact path is required")
        }
        if let artifactID = reference.artifactID,
           artifactID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ElectricalSignoffError.invalidRequest("\(role) artifact ID must not be empty")
        }
        if let byteCount = reference.byteCount, byteCount < 0 {
            throw ElectricalSignoffError.invalidRequest("\(role) artifact byte count must not be negative")
        }
    }

    private func compatibleArtifactReferences(
        _ lhs: XcircuiteFileReference,
        _ rhs: XcircuiteFileReference
    ) -> Bool {
        guard lhs.format == rhs.format else { return false }
        if let lhsDigest = lhs.sha256, let rhsDigest = rhs.sha256,
           lhsDigest.caseInsensitiveCompare(rhsDigest) != .orderedSame {
            return false
        }
        if let lhsByteCount = lhs.byteCount, let rhsByteCount = rhs.byteCount,
           lhsByteCount != rhsByteCount {
            return false
        }
        return true
    }

    private func isSafePathComponent(_ value: String) -> Bool {
        guard !value.isEmpty, value != ".", value != ".." else {
            return false
        }
        return value.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar)
                || scalar == "-"
                || scalar == "_"
                || scalar == "."
        }
    }
}
