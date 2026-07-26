import Foundation
import Testing
@testable import ElectricalSignoffCore
@testable import PowerIntegrityEngine

@Suite("Electrical signoff performance regressions")
struct PerformanceRegressionTests {
    @Test("power solver scales across independent rails", .timeLimit(.minutes(1)))
    func powerSolverScalesAcrossIndependentRails() throws {
        let topology = makeIndependentRailTopology(count: 8_000)
        let startedAt = ContinuousClock.now

        let solution = try PowerIntegrityNetworkSolver().solve(
            topology: topology,
            dynamic: true,
            activityScale: 1.5
        )

        let elapsed = startedAt.duration(to: .now)
        let repeatedSolution = try PowerIntegrityNetworkSolver().solve(
            topology: topology,
            dynamic: true,
            activityScale: 1.5
        )
        print("PowerIntegrityNetworkSolver 8,000-rail elapsed: \(elapsed)")
        #expect(elapsed < Duration.seconds(5))
        #expect(repeatedSolution == solution)
        #expect(solution.nodeVoltages.count == 16_000)
        #expect(solution.segmentCurrentsA.count == 8_000)
        #expect(solution.viaCurrentsA.count == 8_000)
        #expect(solution.sourceCurrentsA.count == 8_000)
        #expect(abs((solution.nodeVoltages["load-7999"] ?? 0) - 0.999125) < 1e-12)
    }

    @Test("topology validator scales across well contacts", .timeLimit(.minutes(1)))
    func topologyValidatorScalesAcrossWellContacts() throws {
        let topology = makeWellContactTopology(count: 8_000)
        let startedAt = ContinuousClock.now

        try ElectricalTopologyValidator().validate(topology)

        let elapsed = startedAt.duration(to: .now)
        print("ElectricalTopologyValidator 8,000-contact elapsed: \(elapsed)")
        #expect(elapsed < Duration.seconds(1))
    }

    private func makeIndependentRailTopology(count: Int) -> ElectricalTopology {
        var nodes: [ElectricalTopology.Node] = []
        var nets: [ElectricalTopology.Net] = []
        var segments: [ElectricalTopology.Segment] = []
        var vias: [ElectricalTopology.Via] = []
        var sources: [ElectricalTopology.Source] = []
        var loads: [ElectricalTopology.Load] = []
        nodes.reserveCapacity(count * 2)
        nets.reserveCapacity(count)
        segments.reserveCapacity(count)
        vias.reserveCapacity(count)
        sources.reserveCapacity(count)
        loads.reserveCapacity(count)

        for index in 0..<count {
            let netID = "rail-\(index)"
            let sourceNodeID = "source-\(index)"
            let loadNodeID = "load-\(index)"
            nodes.append(.init(id: sourceNodeID, netID: netID))
            nodes.append(.init(id: loadNodeID, netID: netID))
            nets.append(.init(id: netID, kind: .power, nominalVoltageV: 1))
            segments.append(.init(
                id: "segment-\(index)",
                netID: netID,
                fromNodeID: sourceNodeID,
                toNodeID: loadNodeID,
                resistanceOhm: 0.05,
                widthMicron: 1,
                thicknessMicron: 1,
                layer: "M1"
            ))
            vias.append(.init(
                id: "via-\(index)",
                netID: netID,
                nodeID: loadNodeID,
                resistanceOhm: 0.01,
                cutAreaSquareMicron: 1
            ))
            sources.append(.init(
                id: "source-\(index)",
                netID: netID,
                nodeID: sourceNodeID,
                voltageV: 1,
                maxCurrentA: 1
            ))
            loads.append(.init(
                id: "load-\(index)",
                netID: netID,
                nodeID: loadNodeID,
                staticCurrentA: 0.01,
                dynamicCurrentA: 0.01,
                activityFactor: 0.5
            ))
        }

        return ElectricalTopology(
            designDigest: "performance-design",
            pdkDigest: "performance-pdk",
            layoutDigest: "performance-layout",
            topCell: "performance_top",
            nodes: nodes,
            nets: nets,
            segments: segments,
            vias: vias,
            sources: sources,
            loads: loads,
            rules: defaultRules
        )
    }

    private func makeWellContactTopology(count: Int) -> ElectricalTopology {
        let wells = (0..<count).map { index in
            ElectricalTopology.Well(
                id: "well-\(index)",
                domainID: "core",
                type: "nwell",
                areaSquareMicron: 10,
                spacingToOppositeWellMicron: 2,
                requiredSpacingMicron: 1,
                substrateContactIDs: ["contact-\(index)"]
            )
        }
        let contacts = (0..<count).map { index in
            ElectricalTopology.SubstrateContact(
                id: "contact-\(index)",
                wellID: "well-\(index)",
                netID: "VSS",
                areaSquareMicron: 1
            )
        }
        return ElectricalTopology(
            designDigest: "performance-design",
            pdkDigest: "performance-pdk",
            layoutDigest: "performance-layout",
            topCell: "performance_top",
            nodes: [],
            nets: [.init(id: "VSS", kind: .ground, nominalVoltageV: 0, domainID: "core")],
            segments: [],
            sources: [],
            loads: [],
            domains: [
                .init(id: "core", nominalVoltageV: 1, maximumVoltageV: 1.1, minimumVoltageV: 0.9)
            ],
            wells: wells,
            substrateContacts: contacts,
            rules: defaultRules
        )
    }

    private var defaultRules: ElectricalTopology.RuleSet {
        .init(
            maximumIRDropV: 0.1,
            maximumCurrentDensityAperSquareMicron: 1,
            maximumViaCurrentDensityAperSquareMicron: 1,
            minimumESDResistanceOhm: 0
        )
    }
}
