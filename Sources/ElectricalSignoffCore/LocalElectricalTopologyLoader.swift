import Foundation
import CircuiteFoundation

public actor LocalElectricalTopologyLoader: ElectricalTopologyLoading {
    public let projectRoot: URL
    public let verifyIntegrity: Bool
    private let foundationArtifactBridge = ElectricalArtifactAccess()

    public init(projectRoot: URL, verifyIntegrity: Bool = true) {
        self.projectRoot = projectRoot.standardizedFileURL
        self.verifyIntegrity = verifyIntegrity
    }

    public func load(request: ElectricalSignoffRequest) async throws -> ElectricalSignoffInput {
        try request.validate()
        let references = try uniqueReferences(for: request)
        for reference in references {
            try verify(reference)
        }

        guard let topologyReference = topologyReference(for: request) else {
            throw ElectricalSignoffError.missingTopologyArtifact
        }
        guard topologyReference.format == .json else {
            throw ElectricalSignoffError.unsupportedTopologyFormat(topologyReference.format.rawValue)
        }

        let topologyURL: URL
        do {
            topologyURL = try foundationArtifactBridge.resolveURL(
                for: topologyReference,
                relativeTo: projectRoot
            )
        } catch {
            throw ElectricalSignoffError.artifactIntegrity(
                path: topologyReference.path,
                status: "invalid-path",
                message: error.localizedDescription
            )
        }

        let data: Data
        do {
            data = try Data(contentsOf: topologyURL)
        } catch {
            throw ElectricalSignoffError.malformedTopology(error.localizedDescription)
        }

        let topology: ElectricalTopology
        do {
            topology = try JSONDecoder().decode(ElectricalTopology.self, from: data)
        } catch {
            throw ElectricalSignoffError.malformedTopology(error.localizedDescription)
        }
        try ElectricalTopologyValidator().validate(topology)
        try validateDigests(topology: topology, request: request)

        return ElectricalSignoffInput(
            request: request,
            topology: topology,
            verifiedReferences: references
        )
    }

    private func uniqueReferences(for request: ElectricalSignoffRequest) throws -> [ArtifactReference] {
        var references: [ArtifactReference] = []
        references.append(contentsOf: request.inputs)
        references.append(try request.materializedArtifact(for: request.design.artifact, role: "design"))
        references.append(request.physicalDesign.layoutArtifact)
        references.append(request.pdk.manifest)
        if let powerIntentReference = try request.powerIntent.map({
            try request.materializedArtifact(for: $0.artifact, role: "power-intent")
        }) {
            references.append(powerIntentReference)
        }
        if let parasitics = request.parasitics {
            references.append(parasitics)
        }
        if let topologyArtifact = request.topologyArtifact {
            references.append(topologyArtifact)
        }
        if let topologyProfileArtifact = request.topologyProfileArtifact {
            references.append(topologyProfileArtifact)
        }
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

    private func topologyReference(for request: ElectricalSignoffRequest) -> ArtifactReference? {
        if let topologyArtifact = request.topologyArtifact {
            return topologyArtifact
        }
        let candidates = request.inputs
        return candidates.first { reference in
            reference.format == .json
                && (reference.path.localizedCaseInsensitiveContains("topology")
                    || reference.artifactID.localizedCaseInsensitiveContains("topology"))
        }
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

    private func validateDigests(topology: ElectricalTopology, request: ElectricalSignoffRequest) throws {
        guard topology.designDigest.caseInsensitiveCompare(request.design.designDigest) == .orderedSame else {
            throw ElectricalSignoffError.digestMismatch(
                kind: "design",
                expected: request.design.designDigest,
                actual: topology.designDigest
            )
        }
        guard topology.layoutDigest.caseInsensitiveCompare(request.physicalDesign.layoutDigest) == .orderedSame else {
            throw ElectricalSignoffError.digestMismatch(
                kind: "layout",
                expected: request.physicalDesign.layoutDigest,
                actual: topology.layoutDigest
            )
        }
        guard topology.pdkDigest.caseInsensitiveCompare(request.pdk.digest) == .orderedSame else {
            throw ElectricalSignoffError.digestMismatch(
                kind: "PDK",
                expected: request.pdk.digest,
                actual: topology.pdkDigest
            )
        }
        if let parasiticDigest = topology.parasiticDigest {
            guard let reference = request.parasitics else {
                throw ElectricalSignoffError.missingParasitics
            }
            guard reference.sha256.caseInsensitiveCompare(parasiticDigest) == .orderedSame else {
                throw ElectricalSignoffError.digestMismatch(
                    kind: "parasitic",
                    expected: parasiticDigest,
                    actual: reference.sha256
                )
            }
        } else if request.parasitics != nil {
            throw ElectricalSignoffError.digestMismatch(
                kind: "parasitic",
                expected: request.parasitics?.sha256 ?? "required",
                actual: "missing-from-topology"
            )
        }
        if let powerIntent = request.powerIntent {
            let powerIntentReference = try request.materializedArtifact(
                for: powerIntent.artifact,
                role: "power-intent"
            )
            guard powerIntent.designDigest.caseInsensitiveCompare(request.design.designDigest) == .orderedSame else {
                throw ElectricalSignoffError.digestMismatch(
                    kind: "power-intent design",
                    expected: request.design.designDigest,
                    actual: powerIntent.designDigest
                )
            }
            guard let topologyPowerIntentDigest = topology.powerIntentDigest else {
                throw ElectricalSignoffError.digestMismatch(
                    kind: "power-intent",
                    expected: powerIntentReference.sha256,
                    actual: "missing-from-topology"
                )
            }
            guard topologyPowerIntentDigest.caseInsensitiveCompare(powerIntentReference.sha256) == .orderedSame else {
                throw ElectricalSignoffError.digestMismatch(
                    kind: "power-intent",
                    expected: topologyPowerIntentDigest,
                    actual: powerIntentReference.sha256
                )
            }
        } else if topology.powerIntentDigest != nil {
            throw ElectricalSignoffError.digestMismatch(
                kind: "power-intent",
                expected: topology.powerIntentDigest ?? "missing",
                actual: "missing-from-request"
            )
        }
    }
}
