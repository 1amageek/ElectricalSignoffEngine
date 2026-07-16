import Foundation
import CryptoKit
import CircuiteFoundation
import LogicIR
import PowerIntent
import PDKCore
import PhysicalDesignCore
import PEXCore
import PEXParsers

public actor LocalElectricalTopologySourceLoader: ElectricalTopologySourceLoading {
    public let projectRoot: URL
    public let verifyIntegrity: Bool
    private let foundationArtifactBridge = ElectricalArtifactAccess()

    public init(projectRoot: URL, verifyIntegrity: Bool = true) {
        self.projectRoot = projectRoot.standardizedFileURL
        self.verifyIntegrity = verifyIntegrity
    }

    public func load(request: ElectricalSignoffRequest) async throws -> ElectricalTopologySourceBundle {
        try request.validate()
        guard let profileReference = request.topologyProfileArtifact else {
            throw ElectricalSignoffError.insufficientTopology(
                "canonical extraction requires topologyProfileArtifact with electrical characterization rules"
            )
        }

        let references = try uniqueReferences(for: request, profileReference: profileReference)
        for reference in references {
            try verify(reference)
        }

        let designReference = try request.materializedArtifact(
            for: request.design.artifact,
            role: "design"
        )
        let designData = try read(designReference, source: "design")
        let physicalData = try read(request.physicalDesign.layoutArtifact, source: "physical-design")
        let pdkData = try read(request.pdk.manifest, source: "pdk")
        let profileData = try read(profileReference, source: "topology-profile")
        guard let processRuleReference = request.processRuleArtifact else {
            throw ElectricalSignoffError.insufficientTopology(
                "canonical extraction requires a PDK-scoped processRuleArtifact"
            )
        }
        let processRuleData = try read(processRuleReference, source: "process-rules")

        guard designReference.format == .json else {
            throw ElectricalSignoffError.unsupportedSourceFormat(
                source: "design",
                format: designReference.format.rawValue
            )
        }
        guard request.physicalDesign.layoutArtifact.format == .json else {
            throw ElectricalSignoffError.unsupportedSourceFormat(
                source: "physical-design",
                format: request.physicalDesign.layoutArtifact.format.rawValue
            )
        }
        guard request.pdk.manifest.format == .json else {
            throw ElectricalSignoffError.unsupportedSourceFormat(
                source: "pdk",
                format: request.pdk.manifest.format.rawValue
            )
        }

        let design: LogicDesignSnapshot
        do {
            design = try LogicDesignSnapshotCodec.decode(designData)
        } catch {
            throw ElectricalSignoffError.malformedTopology("design snapshot decode failed: \(error.localizedDescription)")
        }
        let physicalDesign: PhysicalDesignSnapshot
        do {
            physicalDesign = try PhysicalDesignJSONCodec().decode(PhysicalDesignSnapshot.self, from: physicalData)
        } catch {
            throw ElectricalSignoffError.malformedTopology("physical design snapshot decode failed: \(error.localizedDescription)")
        }
        let pdk: PDKManifest
        do {
            pdk = try PDKManifestCodec.decode(data: pdkData)
        } catch {
            throw ElectricalSignoffError.malformedTopology("PDK manifest decode failed: \(error.localizedDescription)")
        }
        let profile: ElectricalTopologyExtractionProfile
        do {
            profile = try JSONDecoder().decode(ElectricalTopologyExtractionProfile.self, from: profileData)
        } catch {
            throw ElectricalSignoffError.malformedTopology("topology extraction profile decode failed: \(error.localizedDescription)")
        }
        let processRules: ElectricalProcessRuleSet
        do {
            processRules = try JSONDecoder().decode(ElectricalProcessRuleSet.self, from: processRuleData)
        } catch {
            throw ElectricalSignoffError.malformedTopology("process rule set decode failed: \(error.localizedDescription)")
        }

        let powerIntent = try loadPowerIntent(request: request)
        let parasitic = try loadParasitic(request: request)
        try validateSourceIdentity(
            request: request,
            design: design,
            physicalDesign: physicalDesign,
            pdk: pdk,
            powerIntent: powerIntent,
            profile: profile,
            processRules: processRules
        )

        return ElectricalTopologySourceBundle(
            request: request,
            design: design,
            physicalDesign: physicalDesign,
            powerIntent: powerIntent,
            pdk: pdk,
            parasitic: parasitic,
            profile: profile,
            processRules: processRules,
            sourceReferences: references
        )
    }

    private func verify(_ reference: ArtifactReference) throws {
        do {
            try foundationArtifactBridge.validate(
                reference,
                relativeTo: projectRoot,
                verifyIntegrity: verifyIntegrity
            )
        } catch let error as ElectricalArtifactAccessError {
            throw electricalError(for: reference, error: error)
        } catch {
            throw ElectricalSignoffError.artifactIntegrity(
                path: reference.path,
                status: "unreadable-artifact",
                message: error.localizedDescription
            )
        }
    }

    private func read(_ reference: ArtifactReference, source: String) throws -> Data {
        guard reference.format == .json else {
            throw ElectricalSignoffError.unsupportedSourceFormat(
                source: source,
                format: reference.format.rawValue
            )
        }
        let url: URL
        do {
            url = try foundationArtifactBridge.resolveURL(
                for: reference,
                relativeTo: projectRoot
            )
        } catch {
            throw ElectricalSignoffError.artifactIntegrity(
                path: reference.path,
                status: "invalid-path",
                message: error.localizedDescription
            )
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw ElectricalSignoffError.malformedTopology("\(source) artifact read failed: \(error.localizedDescription)")
        }
    }

    private func loadPowerIntent(request: ElectricalSignoffRequest) throws -> PowerIntentDesign? {
        guard let powerIntent = request.powerIntent else {
            return nil
        }
        let reference = try request.materializedArtifact(for: powerIntent.artifact, role: "power-intent")
        let data = try read(reference, source: "power-intent")
        do {
            return try JSONDecoder().decode(PowerIntentDesign.self, from: data)
        } catch let directError {
            do {
                let payload = try JSONDecoder().decode(PowerIntentParsingPayload.self, from: data)
                guard let intent = payload.intent else {
                    throw ElectricalSignoffError.malformedTopology("power-intent payload contains no parsed design")
                }
                return intent
            } catch {
                throw ElectricalSignoffError.malformedTopology(
                    "power-intent decode failed: \(directError.localizedDescription)"
                )
            }
        }
    }

    private func loadParasitic(request: ElectricalSignoffRequest) throws -> ParasiticIR? {
        guard let reference = request.parasitics else {
            return nil
        }
        switch reference.format {
        case .json:
            let data = try read(reference, source: "parasitic")
            do {
                return try JSONDecoder().decode(ParasiticIR.self, from: data)
            } catch {
                throw ElectricalSignoffError.malformedTopology(
                    "canonical ParasiticIR decode failed: \(error.localizedDescription)"
                )
            }
        case .spef:
            let url = try resolve(reference, source: "parasitic")
            let raw = PEXRawOutput(
                format: .spef,
                fileURLs: [url],
                metadata: ["source": "electrical-signoff"]
            )
            let context = PEXParseContext(
                cornerID: PEXCornerID(request.configuration.operatingCondition.pdkCornerID),
                runID: deterministicPEXRunID(for: request.runID),
                topCell: request.physicalDesign.topCell,
                technology: nil,
                options: .default
            )
            do {
                let ir = try SPEFPEXParser().parse(raw, context: context)
                let validation = ParasiticIRValidator().validate(ir)
                guard validation.isValid else {
                    throw ElectricalSignoffError.malformedTopology(
                        "SPEF lowered to invalid ParasiticIR: \(validation.errors.map { String(describing: $0) }.joined(separator: "; "))"
                    )
                }
                return ir
            } catch let error as ElectricalSignoffError {
                throw error
            } catch {
                throw ElectricalSignoffError.malformedTopology(
                    "SPEF parse or lowering failed: \(error.localizedDescription)"
                )
            }
        default:
            throw ElectricalSignoffError.unsupportedSourceFormat(
                source: "parasitic",
                format: reference.format.rawValue
            )
        }
    }

    private func resolve(_ reference: ArtifactReference, source: String) throws -> URL {
        do {
            return try foundationArtifactBridge.resolveURL(
                for: reference,
                relativeTo: projectRoot
            )
        } catch {
            throw ElectricalSignoffError.artifactIntegrity(
                path: reference.path,
                status: "invalid-path",
                message: "\(source) artifact path could not be resolved: \(error.localizedDescription)"
            )
        }
    }

    private func validateSourceIdentity(
        request: ElectricalSignoffRequest,
        design: LogicDesignSnapshot,
        physicalDesign: PhysicalDesignSnapshot,
        pdk: PDKManifest,
        powerIntent: PowerIntentDesign?,
        profile: ElectricalTopologyExtractionProfile,
        processRules: ElectricalProcessRuleSet
    ) throws {
        let designDigest = try LogicDesignSnapshotCodec.digest(design)
        guard design.designDigest?.caseInsensitiveCompare(request.design.designDigest) == .orderedSame,
              designDigest.caseInsensitiveCompare(request.design.designDigest) == .orderedSame else {
            throw ElectricalSignoffError.digestMismatch(
                kind: "design",
                expected: request.design.designDigest,
                actual: design.designDigest ?? designDigest
            )
        }
        guard physicalDesign.topCell == request.physicalDesign.topCell else {
            throw ElectricalSignoffError.malformedTopology(
                "physical top cell \(physicalDesign.topCell) does not match request \(request.physicalDesign.topCell)"
            )
        }
        guard pdkIdentityMatches(request: request, pdk: pdk) else {
            throw ElectricalSignoffError.digestMismatch(
                kind: "PDK",
                expected: request.pdk.digest,
                actual: request.pdk.manifest.sha256
            )
        }
        guard profile.schemaVersion == ElectricalTopologyExtractionProfile.currentSchemaVersion else {
            throw ElectricalSignoffError.schemaVersionUnsupported(profile.schemaVersion)
        }
        guard processRules.schemaVersion == ElectricalProcessRuleSet.currentSchemaVersion else {
            throw ElectricalSignoffError.schemaVersionUnsupported(processRules.schemaVersion)
        }
        guard processRules.pdkDigest.caseInsensitiveCompare(request.pdk.digest) == .orderedSame,
              processRules.processID == request.pdk.processID,
              processRules.pdkVersion == request.pdk.version else {
            throw ElectricalSignoffError.digestMismatch(
                kind: "process rules",
                expected: request.pdk.digest,
                actual: processRules.pdkDigest
            )
        }
        let manifestCornerIDs = Set(pdk.corners.map(\.cornerID))
        guard !manifestCornerIDs.isEmpty else {
            throw ElectricalSignoffError.insufficientTopology("PDK manifest contains no declared electrical corners")
        }
        guard Set(processRules.cornerRules.map(\.cornerID)).count == processRules.cornerRules.count,
              processRules.cornerRules.allSatisfy({ manifestCornerIDs.contains($0.cornerID) }) else {
            throw ElectricalSignoffError.insufficientTopology("process rules are outside the declared PDK corner scope")
        }
        for condition in request.configuration.operatingConditions {
            guard processRules.ruleSet(for: condition.pdkCornerID) != nil else {
                throw ElectricalSignoffError.insufficientTopology(
                    "no process rule exists for PDK corner \(condition.pdkCornerID)"
                )
            }
        }
        if let powerIntent {
            guard let reference = request.powerIntent,
                  reference.designDigest == request.design.designDigest else {
                throw ElectricalSignoffError.digestMismatch(
                    kind: "power-intent design",
                    expected: request.design.designDigest,
                    actual: request.powerIntent?.designDigest ?? "missing"
                )
            }
            guard !powerIntent.domains.isEmpty || !powerIntent.supplySets.isEmpty else {
                throw ElectricalSignoffError.insufficientTopology("power-intent artifact contains no domains or supply sets")
            }
        }
    }

    private func pdkIdentityMatches(request: ElectricalSignoffRequest, pdk: PDKManifest) -> Bool {
        request.pdk.manifest.sha256.caseInsensitiveCompare(request.pdk.digest) == .orderedSame
            && pdk.processID == request.pdk.processID
            && pdk.version == request.pdk.version
    }

    private func electricalError(
        for reference: ArtifactReference,
        error: ElectricalArtifactAccessError
    ) -> ElectricalSignoffError {
        let status: String
        switch error {
        case .invalidReference:
            status = "invalid-location"
        case .missingArtifact:
            status = "missing-file"
        case .notRegularFile:
            status = "not-regular-file"
        case .integrityFailure:
            status = "integrity-failure"
        }
        return ElectricalSignoffError.artifactIntegrity(
            path: reference.path,
            status: status,
            message: error.localizedDescription
        )
    }

    private func uniqueReferences(
        for request: ElectricalSignoffRequest,
        profileReference: ArtifactReference
    ) throws -> [ArtifactReference] {
        var references = request.inputs
        references.append(try request.materializedArtifact(for: request.design.artifact, role: "design"))
        references.append(request.physicalDesign.layoutArtifact)
        references.append(request.pdk.manifest)
        if let powerIntent = request.powerIntent {
            references.append(try request.materializedArtifact(for: powerIntent.artifact, role: "power-intent"))
        }
        if let parasitics = request.parasitics {
            references.append(parasitics)
        }
        references.append(profileReference)
        if let processRuleArtifact = request.processRuleArtifact {
            references.append(processRuleArtifact)
        }

        var referencesByPath: [String: ArtifactReference] = [:]
        var unique: [ArtifactReference] = []
        for reference in references {
            if let existing = referencesByPath[reference.path] {
                guard compatibleArtifactReferences(existing, reference) else {
                    throw ElectricalSignoffError.conflictingArtifactReferences(path: reference.path)
                }
                continue
            }
            referencesByPath[reference.path] = reference
            unique.append(reference)
        }
        return unique
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

    private func deterministicPEXRunID(for runID: String) -> PEXRunID {
        let digest = SHA256.hash(data: Data(runID.utf8)).map { String(format: "%02x", $0) }.joined()
        let uuidText = [
            String(digest.prefix(8)),
            String(digest.dropFirst(8).prefix(4)),
            "4\(String(digest.dropFirst(12).prefix(3)))",
            "8\(String(digest.dropFirst(15).prefix(3)))",
            String(digest.dropFirst(18).prefix(12)),
        ].joined(separator: "-")
        if let uuid = UUID(uuidString: uuidText) {
            return PEXRunID(uuid)
        }
        return PEXRunID(UUID())
    }
}
