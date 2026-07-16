import Foundation
import CircuiteFoundation
import LogicIR
import PowerIntent
import PDKCore
import PhysicalDesignCore

public struct ElectricalSignoffRequest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var runID: String
    public var inputs: [ArtifactReference]

    public var design: LogicDesignReference
    public var physicalDesign: PhysicalDesignReference
    public var pdk: PDKReference
    public var powerIntent: PowerIntentReference?
    public var parasitics: ArtifactReference?
    public var topologyArtifact: ArtifactReference?
    public var topologyProfileArtifact: ArtifactReference?
    public var processRuleArtifact: ArtifactReference?
    public var configuration: ElectricalSignoffConfiguration

    public init(
        runID: String,
        inputs: [ArtifactReference],
        design: LogicDesignReference,
        physicalDesign: PhysicalDesignReference,
        pdk: PDKReference,
        powerIntent: PowerIntentReference? = nil,
        parasitics: ArtifactReference? = nil,
        topologyArtifact: ArtifactReference? = nil,
        topologyProfileArtifact: ArtifactReference? = nil,
        processRuleArtifact: ArtifactReference? = nil,
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
        inputs = try container.decode([ArtifactReference].self, forKey: .inputs)
        design = try container.decode(LogicDesignReference.self, forKey: .design)
        physicalDesign = try container.decode(PhysicalDesignReference.self, forKey: .physicalDesign)
        pdk = try container.decode(PDKReference.self, forKey: .pdk)
        powerIntent = try container.decodeIfPresent(PowerIntentReference.self, forKey: .powerIntent)
        parasitics = try container.decodeIfPresent(ArtifactReference.self, forKey: .parasitics)
        topologyArtifact = try container.decodeIfPresent(ArtifactReference.self, forKey: .topologyArtifact)
        topologyProfileArtifact = try container.decodeIfPresent(ArtifactReference.self, forKey: .topologyProfileArtifact)
        processRuleArtifact = try container.decodeIfPresent(ArtifactReference.self, forKey: .processRuleArtifact)
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
        try validate(locator: design.artifact, role: "design")
        try validate(reference: physicalDesign.layoutArtifact, role: "physical-design")
        try validate(reference: pdk.manifest, role: "pdk")
        _ = try materializedArtifact(for: design.artifact, role: "design")
        for reference in inputs {
            try validate(reference: reference, role: "input")
        }
        if let powerIntent {
            try validate(locator: powerIntent.artifact, role: "power-intent")
            _ = try materializedArtifact(for: powerIntent.artifact, role: "power-intent")
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
        var referencesByPath: [String: ArtifactReference] = [:]
        for reference in allReferences {
            if let existing = referencesByPath[reference.path], !compatibleArtifactReferences(existing, reference) {
                throw ElectricalSignoffError.conflictingArtifactReferences(path: reference.path)
            }
            referencesByPath[reference.path] = reference
        }
        try configuration.validate()
    }

    private var allReferences: [ArtifactReference] {
        var references = inputs
        references.append(physicalDesign.layoutArtifact)
        references.append(pdk.manifest)
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

    private func validate(reference: ArtifactReference, role: String) throws {
        guard !reference.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ElectricalSignoffError.invalidRequest("\(role) artifact path is required")
        }
        guard !reference.artifactID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ElectricalSignoffError.invalidRequest("\(role) artifact ID must not be empty")
        }
    }

    private func validate(locator: ArtifactLocator, role: String) throws {
        let path = locator.location.value
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ElectricalSignoffError.invalidRequest("\(role) artifact path is required")
        }
    }

    /// Resolves a locator to the digest-bearing artifact supplied by the
    /// caller. Design and power-intent references intentionally contain only
    /// locators; their immutable identity is carried in `inputs`.
    public func materializedArtifact(
        for locator: ArtifactLocator,
        role: String = "input"
    ) throws -> ArtifactReference {
        if let reference = materializedReferences.first(where: { $0.locator == locator }) {
            return reference
        }
        throw ElectricalSignoffError.invalidRequest(
            "\(role) artifact locator must have a matching digest-bearing input artifact"
        )
    }

    private var materializedReferences: [ArtifactReference] {
        var references = inputs
        references.append(physicalDesign.layoutArtifact)
        references.append(pdk.manifest)
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

    private func compatibleArtifactReferences(
        _ lhs: ArtifactReference,
        _ rhs: ArtifactReference
    ) -> Bool {
        guard lhs.format == rhs.format else { return false }
        if lhs.sha256.caseInsensitiveCompare(rhs.sha256) != .orderedSame {
            return false
        }
        if lhs.byteCount != rhs.byteCount {
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
