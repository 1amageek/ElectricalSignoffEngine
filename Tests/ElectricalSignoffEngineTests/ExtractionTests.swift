import Foundation
import Testing
import CircuiteFoundation
import LogicIR
import PowerIntent
import PDKCore
import PhysicalDesignCore
import PEXCore
@testable import ElectricalSignoffCore

@Suite("Electrical topology extraction")
struct ExtractionTests {
    @Test("native extractor binds logic pins to routed physical topology", .timeLimit(.minutes(1)))
    func nativeExtractorBindsSourceArtifacts() throws {
        let fixture = try ExtractionFixture.make()
        let topology = try NativeElectricalTopologyExtractor().extract(fixture.sources)

        #expect(topology.topCell == "top")
        #expect(topology.designDigest == fixture.request.design.designDigest)
        #expect(topology.nets.first(where: { $0.id == "VDD" })?.kind == .power)
        #expect(topology.segments.count == 2)
        #expect(topology.sources.count == 2)
        #expect(topology.loads.count == 1)
        #expect(topology.loads[0].nodeID == "pin:U1:VDD:p-vdd")
        #expect(topology.devices.first?.model == "INV_MODEL")
    }

    @Test("missing characterization blocks extraction instead of inventing current", .timeLimit(.minutes(1)))
    func missingCharacterizationBlocksExtraction() throws {
        let fixture = try ExtractionFixture.make()
        var sources = fixture.sources
        sources.profile.sourceRules = []

        #expect(throws: ElectricalSignoffError.self) {
            _ = try NativeElectricalTopologyExtractor().extract(sources)
        }
    }

    @Test("local source loader verifies and decodes extraction inputs", .timeLimit(.minutes(1)))
    func localSourceLoaderDecodesInputs() async throws {
        let fixture = try ExtractionFixture.make()
        let root = URL(filePath: NSTemporaryDirectory()).appending(path: "electrical-extraction-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let designReference = try ExtractionFixture.write(
            data: try LogicDesignSnapshotCodec.encode(fixture.sources.design),
            path: "design.json",
            kind: .netlist,
            root: root,
            artifactID: "design"
        )
        let physicalReference = try ExtractionFixture.write(
            data: try PhysicalDesignJSONCodec().encode(fixture.sources.physicalDesign),
            path: "physical.json",
            kind: .layout,
            root: root,
            artifactID: "physical"
        )
        let pdkReference = try ExtractionFixture.write(
            data: try PDKManifestCodec.encode(fixture.sources.pdk),
            path: "pdk.json",
            kind: .technology,
            root: root,
            artifactID: "pdk"
        )
        let processRules = ElectricalProcessRuleSet(
            pdkDigest: pdkReference.digest.hexadecimalValue,
            processID: "fixture",
            pdkVersion: "1",
            cornerRules: fixture.sources.processRules?.cornerRules ?? []
        )
        let processRuleReference = try ExtractionFixture.write(
            data: try JSONEncoder().encode(processRules),
            path: "process-rules.json",
            kind: .technology,
            root: root,
            artifactID: "process-rules"
        )
        let powerIntent = PowerIntentDesign(
            format: .upf,
            domains: [PowerDomain(id: "core", name: "core", primarySupplyNet: "VDD")],
            supplySets: [PowerSupplySet(id: "core-supply", name: "core-supply", supplyNets: ["VDD", "VSS"])]
        )
        let powerIntentReference = try ExtractionFixture.write(
            data: try JSONEncoder().encode(powerIntent),
            path: "power-intent.json",
            kind: .powerIntent,
            root: root,
            artifactID: "power-intent"
        )
        let parasitic = ParasiticIR(
            version: ParasiticIR.currentVersion,
            cornerID: "typical",
            units: .canonical,
            nets: [],
            elements: [],
            metadata: [:]
        )
        let parasiticReference = try ExtractionFixture.write(
            data: try JSONEncoder().encode(parasitic),
            path: "parasitics.json",
            kind: .parasitics,
            root: root,
            artifactID: "parasitics"
        )
        let profileReference = try ExtractionFixture.write(
            data: try JSONEncoder().encode(fixture.sources.profile),
            path: "topology-profile.json",
            kind: .other,
            root: root,
            artifactID: "topology-profile"
        )
        let request = ElectricalSignoffRequest(
            runID: fixture.request.runID,
            inputs: [designReference, powerIntentReference],
            design: LogicDesignReference(
                artifact: designReference,
                topDesignName: "top",
                designDigest: fixture.request.design.designDigest
            ),
            physicalDesign: PhysicalDesignReference(
                layoutArtifact: physicalReference,
                topCell: "top",
                layoutDigest: fixture.request.physicalDesign.layoutDigest
            ),
            pdk: PDKReference(
                manifest: pdkReference,
                processID: "fixture",
                version: "1",
                digest: pdkReference.digest.hexadecimalValue
            ),
            powerIntent: PowerIntentReference(
                artifact: powerIntentReference,
                designDigest: fixture.request.design.designDigest
            ),
            parasitics: parasiticReference,
            topologyProfileArtifact: profileReference,
            processRuleArtifact: processRuleReference
        )

        let loaded = try await LocalElectricalTopologySourceLoader(projectRoot: root).load(request: request)
        let topology = try NativeElectricalTopologyExtractor().extract(loaded)
        #expect(topology.designDigest == request.design.designDigest)
        #expect(topology.segments.count == 2)
        #expect(loaded.sourceReferences.count == 7)
        #expect(topology.parasiticDigest == parasiticReference.digest.hexadecimalValue)
        #expect(topology.powerIntentDigest == powerIntentReference.digest.hexadecimalValue)

        let spef = """
        *SPEF \"IEEE 1481-1998\"
        *DESIGN \"top\"
        *DIVIDER /
        *DELIMITER :
        *BUS_DELIMITER [ ]
        *T_UNIT 1 NS
        *C_UNIT 1 PF
        *R_UNIT 1 OHM
        *L_UNIT 1 HENRY

        *D_NET VDD 0.150000
        *CONN
        *I top:VDD I
        *CAP
        1 VDD:1 0.100000
        *RES
        1 VDD:1 VDD:2 10.0000
        *END
        """
        let spefReference = try ExtractionFixture.write(
            data: Data(spef.utf8),
            path: "parasitics.spef",
            kind: .parasitics,
            format: .spef,
            root: root,
            artifactID: "parasitics-spef"
        )
        var spefRequest = request
        spefRequest.parasitics = spefReference
        let spefLoaded = try await LocalElectricalTopologySourceLoader(projectRoot: root).load(request: spefRequest)
        #expect(spefLoaded.parasitic?.nets.first?.name.value == "VDD")
        #expect(spefLoaded.parasitic?.nets.first?.totalResistanceOhm == 10)
    }
}

private struct ExtractionFixture: Sendable {
    let request: ElectricalSignoffRequest
    let sources: ElectricalTopologySourceBundle

    static func make() throws -> ExtractionFixture {
        let gate = GateDesign(
            topModuleName: "top",
            modules: [GateModule(
                id: "top-module",
                name: "top",
                ports: [],
                cells: [GateCell(
                    id: "U1",
                    type: "INV",
                    instanceName: "U1",
                    pins: [
                        GatePin(id: "U1-VDD", name: "VDD", direction: .input, netID: "VDD"),
                        GatePin(id: "U1-VSS", name: "VSS", direction: .input, netID: "VSS"),
                        GatePin(id: "U1-Y", name: "Y", direction: .output, netID: "Y"),
                    ]
                )],
                nets: [
                    GateNet(id: "VDD", name: "VDD"),
                    GateNet(id: "VSS", name: "VSS"),
                    GateNet(id: "Y", name: "Y"),
                ]
            )]
        )
        let design = try LogicDesignSnapshotCodec.finalized(
            LogicDesignSnapshot(
                rtl: RTLDesign(topModuleName: "top"),
                gate: gate
            )
        )
        let physical = PhysicalDesignSnapshot(
            topCell: "top",
            unitsPerMicron: 1_000,
            cells: [PhysicalDesignSnapshot.Cell(id: "U1", master: "INV", x: 0, y: 0, width: 10_000, height: 10_000, placed: true)],
            pins: [
                PhysicalDesignSnapshot.Pin(id: "p-vdd", cellID: "U1", name: "VDD", x: 0, y: 0, netID: "VDD", direction: "input"),
                PhysicalDesignSnapshot.Pin(id: "p-vss", cellID: "U1", name: "VSS", x: 0, y: 1_000, netID: "VSS", direction: "input"),
                PhysicalDesignSnapshot.Pin(id: "p-y", cellID: "U1", name: "Y", x: 0, y: 2_000, netID: "Y", direction: "output"),
            ],
            nets: [
                PhysicalDesignSnapshot.Net(id: "VDD", pinIDs: ["p-vdd"]),
                PhysicalDesignSnapshot.Net(id: "VSS", pinIDs: ["p-vss"]),
                PhysicalDesignSnapshot.Net(id: "Y", pinIDs: ["p-y"]),
            ],
            routes: [
                PhysicalDesignSnapshot.Route(
                    id: "route-vdd",
                    netID: "VDD",
                    segments: [PhysicalDesignSnapshot.RouteSegment(id: "seg-vdd", layer: 1, x1: 0, y1: 0, x2: 10_000, y2: 0)]
                ),
                PhysicalDesignSnapshot.Route(
                    id: "route-vss",
                    netID: "VSS",
                    segments: [PhysicalDesignSnapshot.RouteSegment(id: "seg-vss", layer: 1, x1: 0, y1: 1_000, x2: 10_000, y2: 1_000)]
                ),
            ]
        )
        let pdk = PDKManifest(
            processID: "fixture",
            version: "1",
            corners: [PDKCornerDefinition(
                cornerID: "typical",
                pvt: PDKPVTCondition(
                    process: PDKProcessCorner(name: "typical", nominal: true),
                    voltage: 1.8,
                    temperatureCelsius: 25
                )
            )]
        )
        let profile = ElectricalTopologyExtractionProfile(
            netRules: [
                .init(netID: "VDD", kind: .power, nominalVoltageV: 1.8, domainID: "core"),
                .init(netID: "VSS", kind: .ground, nominalVoltageV: 0, domainID: "ground"),
                .init(netID: "Y", kind: .signal),
            ],
            sourceRules: [
                .init(id: "source-vdd", netID: "VDD", nodeID: "pin:U1:VDD:p-vdd", voltageV: 1.8, maxCurrentA: 0.1),
                .init(id: "source-vss", netID: "VSS", nodeID: "pin:U1:VSS:p-vss", voltageV: 0, maxCurrentA: 0.1),
            ],
            loadRules: [
                .init(id: "load-vdd", deviceType: "INV", netID: "VDD", staticCurrentA: 0.01, dynamicCurrentA: 0.02),
            ],
            layerRules: [
                .init(layer: 1, widthMicron: 2, thicknessMicron: 0.2, resistanceOhmPerMicron: 0.001),
            ],
            deviceRules: [
                .init(master: "INV", model: "INV_MODEL", domainID: "core", maxTerminalVoltageV: 1.8),
            ],
            domains: [
                .init(id: "core", nominalVoltageV: 1.8, maximumVoltageV: 1.98, minimumVoltageV: 1.62),
                .init(id: "ground", nominalVoltageV: 0, maximumVoltageV: 0.1, minimumVoltageV: -0.1),
            ],
            rules: .init(
                maximumIRDropV: 0.18,
                maximumCurrentDensityAperSquareMicron: 1,
                maximumViaCurrentDensityAperSquareMicron: 1,
                minimumESDResistanceOhm: 1
            )
        )
        let designReference = try ExtractionFixture.reference(path: "design.json", kind: .netlist, format: .json)
        let physicalReference = try ExtractionFixture.reference(path: "physical.json", kind: .layout, format: .json)
        let pdkReference = try ExtractionFixture.reference(path: "pdk.json", kind: .technology, format: .json)
        let request = ElectricalSignoffRequest(
            runID: "extraction-fixture",
            inputs: [designReference],
            design: LogicDesignReference(
                artifact: designReference,
                topDesignName: "top",
                designDigest: design.designDigest ?? ""
            ),
            physicalDesign: PhysicalDesignReference(
                layoutArtifact: physicalReference,
                topCell: "top",
                layoutDigest: "layout-fixture"
            ),
            pdk: PDKReference(
                manifest: pdkReference,
                processID: "fixture",
                version: "1",
                digest: "pdk-fixture"
            ),
            topologyProfileArtifact: try ExtractionFixture.reference(
                path: "topology-profile.json",
                kind: .other,
                format: .json
            ),
            processRuleArtifact: try ExtractionFixture.reference(
                path: "process-rules.json",
                kind: .technology,
                format: .json
            )
        )
        let processRules = ElectricalProcessRuleSet(
            pdkDigest: "pdk-fixture",
            processID: "fixture",
            pdkVersion: "1",
            cornerRules: [ElectricalProcessRuleSet.CornerRule(
                cornerID: "typical",
                rules: profile.rules
            )]
        )
        let sources = ElectricalTopologySourceBundle(
            request: request,
            design: design,
            physicalDesign: physical,
            powerIntent: nil,
            pdk: pdk,
            parasitic: nil,
            profile: profile,
            processRules: processRules,
            sourceReferences: []
        )
        return ExtractionFixture(request: request, sources: sources)
    }

    fileprivate static func write(
        data: Data,
        path: String,
        kind: ArtifactKind,
        format: ArtifactFormat = .json,
        root: URL,
        artifactID: String
    ) throws -> ArtifactReference {
        let url = root.appending(path: path)
        try data.write(to: url)
        let reference = try ArtifactReference(
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
        return reference
    }

    fileprivate static func reference(
        path: String,
        kind: ArtifactKind,
        format: ArtifactFormat
    ) throws -> ArtifactReference {
        try ArtifactReference(
            id: ArtifactID(rawValue: path.replacingOccurrences(of: ".", with: "-")),
            locator: ArtifactLocator(
                location: ArtifactLocation(workspaceRelativePath: path),
                role: .input,
                kind: kind,
                format: format
            ),
            digest: ContentDigest(
                algorithm: .sha256,
                hexadecimalValue: String(repeating: "a", count: 64)
            ),
            byteCount: 1
        )
    }
}
