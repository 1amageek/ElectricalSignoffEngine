import Foundation
import ElectricalSignoffCore
import ToolQualification

public struct ElectricalSignoffReleaseGatePolicy: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var policyID: String
    public var pdkDigest: String
    public var requiredAxes: [ElectricalSignoffAnalysisAxis]
    public var requiredCornerIDs: [String]
    public var minimumQualificationLevel: ToolQualificationLevel
    public var requireIndependentOracle: Bool
    public var requireProcessQualificationEvidence: Bool
    public var requireArtifactHashes: Bool
    public var requireArtifactIntegrityVerification: Bool
    public var maximumQualificationAgeSeconds: TimeInterval

    public init(
        policyID: String,
        pdkDigest: String,
        requiredAxes: [ElectricalSignoffAnalysisAxis] = ElectricalSignoffAnalysisAxis.allCases.filter { $0 != .aggregate },
        requiredCornerIDs: [String],
        minimumQualificationLevel: ToolQualificationLevel? = nil,
        requireIndependentOracle: Bool = true,
        requireProcessQualificationEvidence: Bool = false,
        requireArtifactHashes: Bool = true,
        requireArtifactIntegrityVerification: Bool = true,
        maximumQualificationAgeSeconds: TimeInterval = 30 * 24 * 60 * 60,
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.policyID = policyID
        self.pdkDigest = pdkDigest
        self.requiredAxes = requiredAxes
        self.requiredCornerIDs = requiredCornerIDs
        self.minimumQualificationLevel = minimumQualificationLevel
            ?? (requireIndependentOracle ? .oracleChecked : .corpusChecked)
        self.requireIndependentOracle = requireIndependentOracle
        self.requireProcessQualificationEvidence = requireProcessQualificationEvidence
        self.requireArtifactHashes = requireArtifactHashes
        self.requireArtifactIntegrityVerification = requireArtifactIntegrityVerification
        self.maximumQualificationAgeSeconds = maximumQualificationAgeSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case policyID
        case pdkDigest
        case requiredAxes
        case requiredCornerIDs
        case minimumQualificationLevel
        case requireIndependentOracle
        case requireProcessQualificationEvidence
        case requireArtifactHashes
        case requireArtifactIntegrityVerification
        case maximumQualificationAgeSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            policyID: container.decode(String.self, forKey: .policyID),
            pdkDigest: container.decode(String.self, forKey: .pdkDigest),
            requiredAxes: container.decode([ElectricalSignoffAnalysisAxis].self, forKey: .requiredAxes),
            requiredCornerIDs: container.decode([String].self, forKey: .requiredCornerIDs),
            minimumQualificationLevel: container.decode(ToolQualificationLevel.self, forKey: .minimumQualificationLevel),
            requireIndependentOracle: container.decode(Bool.self, forKey: .requireIndependentOracle),
            requireProcessQualificationEvidence: container.decodeIfPresent(Bool.self, forKey: .requireProcessQualificationEvidence) ?? false,
            requireArtifactHashes: container.decode(Bool.self, forKey: .requireArtifactHashes),
            requireArtifactIntegrityVerification: container.decode(Bool.self, forKey: .requireArtifactIntegrityVerification),
            maximumQualificationAgeSeconds: container.decode(TimeInterval.self, forKey: .maximumQualificationAgeSeconds),
            schemaVersion: container.decode(Int.self, forKey: .schemaVersion)
        )
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ElectricalSignoffReleaseGateError.invalidPolicy("unsupported release gate schema version \(schemaVersion)")
        }
        guard !policyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !pdkDigest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ElectricalSignoffReleaseGateError.invalidPolicy("policy ID and PDK digest are required")
        }
        guard !requiredAxes.isEmpty,
              requiredAxes.allSatisfy({ $0 != .aggregate }),
              Set(requiredAxes).count == requiredAxes.count else {
            throw ElectricalSignoffReleaseGateError.invalidPolicy("required axes must be unique and cannot contain aggregate")
        }
        guard !requiredCornerIDs.isEmpty,
              requiredCornerIDs.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              Set(requiredCornerIDs).count == requiredCornerIDs.count else {
            throw ElectricalSignoffReleaseGateError.invalidPolicy("required corner IDs must be unique and non-empty")
        }
        if requireIndependentOracle && minimumQualificationLevel < .oracleChecked {
            throw ElectricalSignoffReleaseGateError.invalidPolicy(
                "independent oracle policy requires at least oracleChecked qualification"
            )
        }
        guard maximumQualificationAgeSeconds.isFinite, maximumQualificationAgeSeconds > 0 else {
            throw ElectricalSignoffReleaseGateError.invalidPolicy("maximum qualification age must be positive")
        }
    }
}
