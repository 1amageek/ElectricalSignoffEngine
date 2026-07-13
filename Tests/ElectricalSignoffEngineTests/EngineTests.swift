import Foundation
import Testing
import CircuiteFoundation
import LogicIR
import PDKCore
import PhysicalDesignCore
@testable import ElectricalSignoffCore
@testable import PowerIntegrityEngine
@testable import ERCEngine
@testable import ESDEngine
@testable import LatchUpEngine
@testable import AgingEngine
@testable import ElectricalSignoffEngine

@Suite("ElectricalSignoffEngine native execution")
struct EngineTests {
    @Test("clean extracted topology completes every required axis", .timeLimit(.minutes(1)))
    func cleanTopologyCompletesAllAxes() async throws {
        let fixture = try FixtureProject.make(clean: true)
        let support = ElectricalSignoffExecutionSupport(
            projectRoot: fixture.root,
            clock: FixedElectricalClock(now: Date(timeIntervalSince1970: 1_000))
        )
        let result = try await ElectricalSignoffEngine(support: support).execute(fixture.request)

        #expect(result.status == .completed)
        #expect(Set(result.axisResults.keys) == Set(ElectricalSignoffEngineAPI.supportedAxes))
        for axis in ElectricalSignoffEngineAPI.supportedAxes {
            let axisResult = try #require(result.axisResults[axis])
            #expect(axisResult.status == .completed)
            #expect(axisResult.payload.violationCount == 0)
            #expect(axisResult.payload.provenance?.designDigest == fixture.request.design.designDigest)
            #expect(axisResult.artifacts.count == 1)
            #expect(axisResult.artifacts[0].sha256.count == 64)
        }
    }

    @Test("request configuration selects the default axis set", .timeLimit(.minutes(1)))
    func configurationSelectsRequiredAxes() async throws {
        let fixture = try FixtureProject.make(clean: true)
        var request = fixture.request
        request.configuration = ElectricalSignoffConfiguration(requiredAxes: [.erc])
        let support = ElectricalSignoffExecutionSupport(projectRoot: fixture.root)
        let result = try await ElectricalSignoffEngine(support: support).execute(request)

        #expect(result.status == .completed)
        #expect(Set(result.axisResults.keys) == [.erc])
        #expect(result.axisResults[.erc]?.status == .completed)
    }

    @Test("empty and duplicate axis selections are rejected", .timeLimit(.minutes(1)))
    func invalidAxisSelectionsAreRejected() throws {
        let empty = ElectricalSignoffConfiguration(requiredAxes: [])
        #expect(throws: ElectricalSignoffError.self) {
            try empty.validate()
        }

        let duplicate = ElectricalSignoffConfiguration(requiredAxes: [.erc, .erc])
        #expect(throws: ElectricalSignoffError.self) {
            try duplicate.validate()
        }
    }

    @Test("a topology loader does not guess a design artifact as topology", .timeLimit(.minutes(1)))
    func topologyArtifactMustBeExplicitOrNamed() async throws {
        let fixture = try FixtureProject.make(clean: true)
        var request = fixture.request
        request.inputs = []
        request.topologyArtifact = nil

        do {
            _ = try await LocalElectricalTopologyLoader(projectRoot: fixture.root).load(request: request)
            Issue.record("Expected the topology loader to reject an unnamed topology input.")
        } catch let error as ElectricalSignoffError {
            #expect(
                error == .missingTopologyArtifact
                    || error.localizedDescription.contains("design artifact locator")
            )
        } catch {
            Issue.record("Unexpected error: \(error.localizedDescription)")
        }
    }

    @Test("conflicting references for one path are rejected before I/O", .timeLimit(.minutes(1)))
    func conflictingReferencesAreRejected() throws {
        let fixture = try FixtureProject.make(clean: true)
        var request = fixture.request
        let path = fixture.request.topologyArtifact?.path ?? "electrical-topology.json"
        request.inputs.append(try ArtifactReference(
            id: ArtifactID(rawValue: "conflicting"),
            locator: ArtifactLocator(
                location: ArtifactLocation(workspaceRelativePath: path),
                role: .input,
                kind: .report,
                format: .json
            ),
            digest: ContentDigest(
                algorithm: .sha256,
                hexadecimalValue: String(repeating: "f", count: 64)
            ),
            byteCount: 1
        ))

        #expect(throws: ElectricalSignoffError.self) {
            try request.validate()
        }
    }

    @Test("non-finite topology values are rejected", .timeLimit(.minutes(1)))
    func nonFiniteTopologyValuesAreRejected() throws {
        let fixture = try FixtureProject.make(clean: true)
        var topology = try JSONDecoder().decode(
            ElectricalTopology.self,
            from: Data(contentsOf: fixture.root.appending(path: "electrical-topology.json"))
        )
        topology.sources[0].voltageV = .infinity

        #expect(throws: ElectricalSignoffError.self) {
            try ElectricalTopologyValidator().validate(topology)
        }
    }

    @Test("operating condition is retained in the result and changes analysis inputs", .timeLimit(.minutes(1)))
    func operatingConditionIsRetained() async throws {
        let fixture = try FixtureProject.make(clean: true)
        var request = fixture.request
        request.configuration = ElectricalSignoffConfiguration(
            operatingCondition: ElectricalOperatingCondition(
                id: "hot-low-voltage",
                pdkCornerID: "slow",
                temperatureC: 125,
                supplyVoltageScale: 0.9,
                activityScale: 2
            )
        )
        let support = ElectricalSignoffExecutionSupport(projectRoot: fixture.root)
        let result = try await DefaultPowerIntegrityEngine(support: support).execute(request)

        #expect(result.status == .completed)
        #expect(result.payload.cornerID == "hot-low-voltage")
        #expect(result.provenance.producer.identifier == "electrical-signoff.power-integrity")
    }

    @Test("zero activity scale removes dynamic load contribution", .timeLimit(.minutes(1)))
    func zeroActivityScaleRemovesDynamicContribution() async throws {
        let fixture = try FixtureProject.make(clean: true)
        var request = fixture.request
        request.configuration = ElectricalSignoffConfiguration(
            operatingCondition: ElectricalOperatingCondition(
                id: "static-only",
                pdkCornerID: "typical",
                temperatureC: 25,
                supplyVoltageScale: 1,
                activityScale: 0
            )
        )
        let result = try await DefaultPowerIntegrityEngine(
            support: ElectricalSignoffExecutionSupport(projectRoot: fixture.root)
        ).execute(request)

        #expect(result.status == .completed)
        let staticDrop = try #require(result.payload.metrics.first { $0.name == "static-ir-drop" })
        let dynamicDrop = try #require(result.payload.metrics.first { $0.name == "dynamic-ir-drop" })
        #expect(abs(staticDrop.value - dynamicDrop.value) < 1e-12)
    }

    @Test("power integrity reports source capacity violations", .timeLimit(.minutes(1)))
    func sourceCapacityViolationIsReported() async throws {
        let fixture = try FixtureProject.make(clean: true)
        let topologyURL = fixture.root.appending(path: "electrical-topology.json")
        var topology = try JSONDecoder().decode(
            ElectricalTopology.self,
            from: Data(contentsOf: topologyURL)
        )
        topology.sources[0].maxCurrentA = 0.01
        let topologyData = try JSONEncoder().encode(topology)
        try topologyData.write(to: topologyURL, options: [.atomic])

        var request = fixture.request
        let topologyReference = try FixtureProject.write(
            data: topologyData,
            path: "electrical-topology.json",
            kind: .other,
            format: .json,
            root: fixture.root,
            artifactID: "electrical-topology"
        )
        request.inputs = [topologyReference]
        request.inputs.append(try fixture.request.materializedArtifact(
            for: fixture.request.design.artifact,
            role: "design"
        ))
        request.topologyArtifact = topologyReference
        let result = try await DefaultPowerIntegrityEngine(
            support: ElectricalSignoffExecutionSupport(projectRoot: fixture.root)
        ).execute(request)

        #expect(result.status == .completed)
        #expect(result.payload.findings.contains { $0.code == "electrical.em.source-current-limit" })
        #expect(result.payload.repairCandidates.contains { $0.entity == "vdd-source-1" })
    }

    @Test("multi-corner execution retains per-corner evidence and aggregates the worst result", .timeLimit(.minutes(1)))
    func multiCornerExecutionRetainsEvidence() async throws {
        let fixture = try FixtureProject.make(clean: true)
        var request = fixture.request
        request.configuration = ElectricalSignoffConfiguration(
            requiredAxes: [.erc],
            operatingConditions: [
                ElectricalOperatingCondition(
                    id: "nominal",
                    pdkCornerID: "typical",
                    temperatureC: 25,
                    supplyVoltageScale: 1,
                    activityScale: 1
                ),
                ElectricalOperatingCondition(
                    id: "hot-low-voltage",
                    pdkCornerID: "slow",
                    temperatureC: 125,
                    supplyVoltageScale: 0.9,
                    activityScale: 2
                ),
            ]
        )
        let support = ElectricalSignoffExecutionSupport(projectRoot: fixture.root)
        let result = try await ElectricalSignoffEngine(support: support).execute(request)

        #expect(result.status == .completed)
        #expect(Set(result.cornerResults.keys) == Set(["nominal", "hot-low-voltage"]))
        #expect(result.cornerResults["nominal"]?[.erc]?.payload.cornerID == "nominal")
        #expect(result.cornerResults["hot-low-voltage"]?[.erc]?.payload.cornerID == "hot-low-voltage")
        #expect(result.axisResults[.erc]?.payload.cornerID == "hot-low-voltage")
        let artifactPaths = Set(result.cornerResults.values.compactMap { $0[.erc]?.artifacts.first?.path })
        #expect(artifactPaths.count == 2)
    }

    @Test("condition identifiers that sanitize to the same path remain distinct", .timeLimit(.minutes(1)))
    func conditionIdentifierCollisionsAreAvoided() async throws {
        let fixture = try FixtureProject.make(clean: true)
        var request = fixture.request
        request.configuration = ElectricalSignoffConfiguration(
            requiredAxes: [.erc],
            operatingConditions: [
                ElectricalOperatingCondition(
                    id: "corner/a",
                    pdkCornerID: "typical",
                    temperatureC: 25,
                    supplyVoltageScale: 1,
                    activityScale: 1
                ),
                ElectricalOperatingCondition(
                    id: "corner-a",
                    pdkCornerID: "typical",
                    temperatureC: 25,
                    supplyVoltageScale: 1,
                    activityScale: 1
                ),
            ]
        )

        let result = try await ElectricalSignoffEngine(
            support: ElectricalSignoffExecutionSupport(projectRoot: fixture.root)
        ).execute(request)
        let paths = Set(result.cornerResults.values.compactMap { $0[.erc]?.artifacts.first?.path })
        #expect(paths.count == 2)
    }

    @Test("configuration round-trips multiple operating conditions", .timeLimit(.minutes(1)))
    func configurationRoundTripsMultipleConditions() throws {
        let configuration = ElectricalSignoffConfiguration(
            requiredAxes: [.erc],
            operatingConditions: [
                ElectricalOperatingCondition(id: "cold", pdkCornerID: "fast", temperatureC: -20, supplyVoltageScale: 1.1, activityScale: 0.5),
                ElectricalOperatingCondition(id: "hot", pdkCornerID: "slow", temperatureC: 125, supplyVoltageScale: 0.9, activityScale: 2),
            ]
        )
        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(ElectricalSignoffConfiguration.self, from: data)

        #expect(decoded == configuration)
        try decoded.validate()
    }

    @Test("run results decode legacy payloads without corner results", .timeLimit(.minutes(1)))
    func runResultDecodesLegacyShape() throws {
        let legacyJSONText = """
        {
          "schemaVersion": 1,
          "runID": "legacy-run",
          "status": "completed",
          "axisResults": []
        }
        """
        let legacyJSON = Data(legacyJSONText.utf8)
        let result = try JSONDecoder().decode(ElectricalSignoffRunResult.self, from: legacyJSON)

        #expect(result.runID == "legacy-run")
        #expect(result.cornerResults.isEmpty)
    }

    @Test("power integrity computes extracted static and dynamic drop", .timeLimit(.minutes(1)))
    func powerIntegrityComputesDrop() async throws {
        let fixture = try FixtureProject.make(clean: true)
        let support = ElectricalSignoffExecutionSupport(
            projectRoot: fixture.root,
            clock: FixedElectricalClock(now: Date(timeIntervalSince1970: 1_000))
        )
        let result = try await DefaultPowerIntegrityEngine(support: support).execute(fixture.request)

        #expect(result.status == .completed)
        let metricNames = Set(result.payload.metrics.map(\.name))
        #expect(metricNames.contains("static-ir-drop"))
        #expect(metricNames.contains("dynamic-ir-drop"))
        #expect(result.payload.metrics.first(where: { $0.name == "static-ir-drop" })?.value ?? 1 < 0.18)
    }

    @Test("missing parasitic provenance blocks instead of passing", .timeLimit(.minutes(1)))
    func missingParasiticsBlocks() async throws {
        let fixture = try FixtureProject.make(clean: true)
        var request = fixture.request
        request.parasitics = nil
        let support = ElectricalSignoffExecutionSupport(projectRoot: fixture.root)
        let result = try await DefaultPowerIntegrityEngine(support: support).execute(request)

        #expect(result.status == .blocked)
        #expect(result.diagnostics.contains { $0.code.rawValue == "electrical.parasitics.missing" })
    }

    @Test("digest mismatch is a structured blocked diagnostic", .timeLimit(.minutes(1)))
    func digestMismatchBlocks() async throws {
        let fixture = try FixtureProject.make(clean: true)
        var request = fixture.request
        request.pdk.digest = "wrong-pdk-digest"
        let support = ElectricalSignoffExecutionSupport(projectRoot: fixture.root)
        let result = try await DefaultERCEngine(support: support).execute(request)

        #expect(result.status == .blocked)
        #expect(result.diagnostics.first?.code.rawValue == "electrical.input.digest-mismatch")
        #expect(result.diagnostics.first?.suggestedActions.isEmpty == false)
    }

    @Test("request and result payloads round-trip through JSON", .timeLimit(.minutes(1)))
    func contractRoundTrip() throws {
        let fixture = try FixtureProject.make(clean: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let requestData = try encoder.encode(fixture.request)
        let decodedRequest = try JSONDecoder().decode(ElectricalSignoffRequest.self, from: requestData)
        #expect(decodedRequest == fixture.request)

        let payload = ElectricalSignoffPayload(
            violationCount: 1,
            worstMetric: 0.2,
            metricUnit: "V",
            axis: .powerIntegrity,
            findings: [ElectricalSignoffPayload.Finding(code: "test.code", severity: .error, message: "test")]
        )
        let payloadData = try encoder.encode(payload)
        let decodedPayload = try JSONDecoder().decode(ElectricalSignoffPayload.self, from: payloadData)
        #expect(decodedPayload == payload)
    }
}

private struct FixtureProject: Sendable {
    let root: URL
    let request: ElectricalSignoffRequest

    static func make(clean: Bool) throws -> FixtureProject {
        let root = URL(filePath: NSTemporaryDirectory()).appending(path: "electrical-signoff-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let topology = ElectricalTopology(
            designDigest: "design-fixture-v1",
            pdkDigest: "pdk-fixture-v1",
            layoutDigest: "layout-fixture-v1",
            topCell: "fixture_top",
            parasiticDigest: clean ? nil : nil,
            nodes: [
                ElectricalTopology.Node(id: "vdd-source", netID: "VDD"),
                ElectricalTopology.Node(id: "vdd-load", netID: "VDD"),
                ElectricalTopology.Node(id: "vss-source", netID: "VSS"),
            ],
            nets: [
                ElectricalTopology.Net(id: "VDD", kind: .power, nominalVoltageV: 1.8, domainID: "core"),
                ElectricalTopology.Net(id: "VSS", kind: .ground, nominalVoltageV: 0, domainID: "ground"),
            ],
            devices: [
                ElectricalTopology.Device(
                    id: "U1",
                    model: "fixture_cell",
                    terminals: ["VDD": "VDD", "VSS": "VSS"],
                    domainID: "core",
                    maxTerminalVoltageV: 1.8
                ),
            ],
            segments: [
                ElectricalTopology.Segment(
                    id: "vdd-segment-1",
                    netID: "VDD",
                    fromNodeID: "vdd-source",
                    toNodeID: "vdd-load",
                    resistanceOhm: 0.05,
                    currentA: 0,
                    widthMicron: 2,
                    thicknessMicron: 0.2,
                    currentLimitA: 0.1,
                    layer: "M1"
                ),
            ],
            vias: [
                ElectricalTopology.Via(id: "vdd-via-1", netID: "VDD", nodeID: "vdd-load", resistanceOhm: 0.01, currentA: 0, cutAreaSquareMicron: 1, currentLimitA: 0.05),
            ],
            sources: [
                ElectricalTopology.Source(id: "vdd-source-1", netID: "VDD", nodeID: "vdd-source", voltageV: 1.8, maxCurrentA: 0.1),
                ElectricalTopology.Source(id: "vss-source-1", netID: "VSS", nodeID: "vss-source", voltageV: 0, maxCurrentA: 0.1),
            ],
            loads: [
                ElectricalTopology.Load(id: "U1-vdd-load", netID: "VDD", nodeID: "vdd-load", staticCurrentA: 0.02, dynamicCurrentA: 0.01, activityFactor: 1, domainID: "core"),
            ],
            activityVectors: [ElectricalTopology.ActivityVector(id: "peak", weight: 1, peakScale: 1.5)],
            domains: [
                ElectricalTopology.Domain(id: "core", nominalVoltageV: 1.8, maximumVoltageV: 1.98, minimumVoltageV: 1.62),
                ElectricalTopology.Domain(id: "ground", nominalVoltageV: 0, maximumVoltageV: 0.1, minimumVoltageV: -0.1),
            ],
            esdClamps: [
                ElectricalTopology.ESDClamp(id: "clamp-vdd", domainID: "core", protectedNetID: "VDD", groundNetID: "VSS", triggerVoltageV: 1.2, maximumCurrentA: 0.1, resistanceOhm: 5),
            ],
            wells: [
                ElectricalTopology.Well(id: "well-core", domainID: "core", type: "nwell", areaSquareMicron: 100, spacingToOppositeWellMicron: 2, requiredSpacingMicron: 1, substrateContactIDs: ["contact-core"]),
            ],
            substrateContacts: [
                ElectricalTopology.SubstrateContact(id: "contact-core", wellID: "well-core", netID: "VSS", areaSquareMicron: 4),
            ],
            agingModels: [
                ElectricalTopology.AgingModel(deviceID: "U1", nbtiCoefficient: 1, hciCoefficient: 1, tddbCoefficient: 1, dutyCycle: 0.2, lifetimeHoursAtReference: 200_000, referenceTemperatureC: 25, referenceVoltageV: 1.8),
            ],
            rules: ElectricalTopology.RuleSet(maximumIRDropV: 0.18, maximumCurrentDensityAperSquareMicron: 1, maximumViaCurrentDensityAperSquareMicron: 1, minimumESDResistanceOhm: 1)
        )
        let topologyData = try JSONEncoder().encode(topology)
        var topologyReference = try write(
            data: topologyData,
            path: "electrical-topology.json",
            kind: .other,
            format: .json,
            root: root,
            artifactID: "electrical-topology"
        )
        let designReference = try write(data: Data(".subckt fixture_top".utf8), path: "design.spice", kind: .netlist, format: .spice, root: root, artifactID: "design")
        let layoutReference = try write(data: Data("fixture-layout".utf8), path: "layout.gds", kind: .layout, format: .gdsii, root: root, artifactID: "layout")
        let pdkReference = try write(data: Data("fixture-pdk".utf8), path: "pdk.json", kind: .technology, format: .json, root: root, artifactID: "pdk")
        let parasiticReference = try write(data: Data("* fixture SPEF\n".utf8), path: "parasitics.spef", kind: .parasitics, format: .spef, root: root, artifactID: "parasitics")

        var topologyWithDigest = topology
        topologyWithDigest.parasiticDigest = parasiticReference.sha256
        let updatedTopologyData = try JSONEncoder().encode(topologyWithDigest)
        topologyReference = try write(data: updatedTopologyData, path: "electrical-topology.json", kind: .other, format: .json, root: root, artifactID: "electrical-topology")

        let request = ElectricalSignoffRequest(
            runID: "fixture-run",
            inputs: [topologyReference, designReference],
            design: LogicDesignReference(artifact: designReference.locator, topDesignName: "fixture_top", designDigest: topology.designDigest),
            physicalDesign: PhysicalDesignReference(layoutArtifact: layoutReference, topCell: topology.topCell, layoutDigest: topology.layoutDigest),
            pdk: PDKReference(manifest: pdkReference, processID: "fixture", version: "1", digest: topology.pdkDigest),
            parasitics: parasiticReference,
            topologyArtifact: topologyReference
        )
        return FixtureProject(root: root, request: request)
    }

    static func write(
        data: Data,
        path: String,
        kind: ArtifactKind,
        format: ArtifactFormat,
        root: URL,
        artifactID: String
    ) throws -> ArtifactReference {
        let url = root.appending(path: path)
        try data.write(to: url)
        return try ArtifactReference(
            id: ArtifactID(rawValue: artifactID),
            locator: ArtifactLocator(
                location: ArtifactLocation(workspaceRelativePath: path),
                role: .input,
                kind: kind,
                format: format
            ),
            digest: SHA256ContentDigester().digest(data: data, using: .sha256),
            byteCount: UInt64(data.count)
        )
    }
}
