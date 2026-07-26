import Foundation
import CircuiteFoundation
import ElectricalSignoffCore

public struct DefaultPowerIntegrityEngine: PowerIntegrityAnalyzing {
    public let support: ElectricalSignoffExecutionSupport
    public let solver: PowerIntegrityNetworkSolver

    public init(
        support: ElectricalSignoffExecutionSupport = ElectricalSignoffExecutionSupport(),
        solver: PowerIntegrityNetworkSolver = PowerIntegrityNetworkSolver()
    ) {
        self.support = support
        self.solver = solver
    }

    public func execute(
        _ request: ElectricalSignoffRequest
    ) async throws -> ElectricalSignoffResult {
        let axis: ElectricalSignoffAnalysisAxis = .powerIntegrity
        let startedAt = support.clock.now
        let input: ElectricalSignoffInput
        do {
            input = try await support.load(request: request)
            guard request.parasitics != nil else {
                throw ElectricalSignoffError.missingParasitics
            }
            guard !input.topology.segments.isEmpty, !input.topology.sources.isEmpty, !input.topology.loads.isEmpty else {
                throw ElectricalSignoffError.insufficientTopology("power integrity requires extracted segments, sources and loads")
            }
        } catch {
            return try support.blockedEnvelope(request: request, axis: axis, error: error, startedAt: startedAt)
        }

        let vectorScale = input.topology.activityVectors.map(\.peakScale).max() ?? 1
        let condition = input.request.configuration.operatingCondition
        let rules = input.topology.rules(for: condition)
        let activityScale = max(0, vectorScale * condition.activityScale)
        let staticSolution: PowerIntegrityNetworkSolver.Solution
        let dynamicSolution: PowerIntegrityNetworkSolver.Solution
        do {
            staticSolution = try solver.solve(
                topology: input.topology,
                dynamic: false,
                activityScale: 0,
                voltageScale: condition.supplyVoltageScale
            )
            dynamicSolution = try solver.solve(
                topology: input.topology,
                dynamic: true,
                activityScale: activityScale,
                voltageScale: condition.supplyVoltageScale
            )
        } catch {
            return try support.blockedEnvelope(request: request, axis: axis, error: error, startedAt: startedAt)
        }

        let staticDrop = worstDrop(topology: input.topology, solution: staticSolution)
        let dynamicDrop = worstDrop(topology: input.topology, solution: dynamicSolution)
        let segmentDensity = worstSegmentDensity(topology: input.topology, solution: dynamicSolution)
        let viaDensity = worstViaDensity(topology: input.topology, solution: dynamicSolution)
        var findings: [ElectricalSignoffPayload.Finding] = []
        var repairs: [ElectricalSignoffPayload.RepairCandidate] = []

        if staticDrop.value > rules.maximumIRDropV {
            findings.append(finding(
                code: "electrical.ir.static-drop",
                entity: staticDrop.netID,
                message: "Static IR drop exceeds the declared process limit.",
                observed: staticDrop.value,
                limit: rules.maximumIRDropV,
                actions: ["increase_power_grid_width", "add_parallel_power_path", "reduce_static_load"]
            ))
            repairs.append(repair(
                id: "repair-static-ir-\(staticDrop.netID)",
                kind: "power-grid-strengthening",
                entity: staticDrop.netID,
                rationale: "Reduce the worst static voltage drop on the extracted rail.",
                actions: ["add_parallel_segment", "increase_segment_width", "add_source_via"]
            ))
        }
        if dynamicDrop.value > rules.maximumIRDropV {
            findings.append(finding(
                code: "electrical.ir.dynamic-drop",
                entity: dynamicDrop.netID,
                message: "Dynamic IR drop exceeds the declared process limit.",
                observed: dynamicDrop.value,
                limit: rules.maximumIRDropV,
                actions: ["reduce_switching_activity", "add_local_decoupling", "strengthen_power_grid"]
            ))
            repairs.append(repair(
                id: "repair-dynamic-ir-\(dynamicDrop.netID)",
                kind: "activity-or-grid-reduction",
                entity: dynamicDrop.netID,
                rationale: "Reduce the peak activity-induced voltage drop.",
                actions: ["add_local_decoupling", "split_high_activity_loads", "increase_grid_capacity"]
            ))
        }
        if segmentDensity.value > rules.maximumCurrentDensityAperSquareMicron {
            findings.append(finding(
                code: "electrical.em.segment-density",
                entity: segmentDensity.segmentID,
                message: "Segment current density exceeds the declared electromigration limit.",
                observed: segmentDensity.value,
                limit: rules.maximumCurrentDensityAperSquareMicron,
                actions: ["increase_wire_width", "add_parallel_wire", "reduce_current_demand"]
            ))
            repairs.append(repair(
                id: "repair-em-\(segmentDensity.segmentID)",
                kind: "wire-width-increase",
                entity: segmentDensity.segmentID,
                rationale: "Reduce current density on the failing power segment.",
                actions: ["increase_width", "add_parallel_segment"]
            ))
        }
        if viaDensity.value > rules.maximumViaCurrentDensityAperSquareMicron {
            findings.append(finding(
                code: "electrical.em.via-density",
                entity: viaDensity.viaID,
                message: "Via current density exceeds the declared electromigration limit.",
                observed: viaDensity.value,
                limit: rules.maximumViaCurrentDensityAperSquareMicron,
                actions: ["add_via_array", "increase_via_cut_area", "reduce_via_current"]
            ))
            repairs.append(repair(
                id: "repair-via-em-\(viaDensity.viaID)",
                kind: "via-array-increase",
                entity: viaDensity.viaID,
                rationale: "Spread current across additional or larger via cuts.",
                actions: ["add_parallel_vias", "increase_cut_count"]
            ))
        }
        for segment in input.topology.segments {
            if let currentLimit = segment.currentLimitA,
               let current = dynamicSolution.segmentCurrentsA[segment.id],
               current > currentLimit {
                findings.append(finding(
                    code: "electrical.em.segment-current-limit",
                    entity: segment.id,
                    message: "Segment current exceeds the declared process current limit.",
                    observed: current,
                    limit: currentLimit,
                    actions: ["increase_wire_width", "add_parallel_wire", "reduce_current_demand"]
                ))
                repairs.append(repair(
                    id: "repair-segment-current-\(segment.id)",
                    kind: "segment-current-limit",
                    entity: segment.id,
                    rationale: "Keep extracted segment current within the process limit.",
                    actions: ["increase_width", "add_parallel_segment"]
                ))
            }
        }
        for via in input.topology.vias {
            if let currentLimit = via.currentLimitA,
               let current = dynamicSolution.viaCurrentsA[via.id],
               current > currentLimit {
                findings.append(finding(
                    code: "electrical.em.via-current-limit",
                    entity: via.id,
                    message: "Via current exceeds the declared process current limit.",
                    observed: current,
                    limit: currentLimit,
                    actions: ["add_via_array", "increase_via_cut_area", "reduce_via_current"]
                ))
                repairs.append(repair(
                    id: "repair-via-current-\(via.id)",
                    kind: "via-current-limit",
                    entity: via.id,
                    rationale: "Keep extracted via current within the process limit.",
                    actions: ["add_parallel_vias", "increase_cut_count"]
                ))
            }
        }
        for source in input.topology.sources {
            if let current = dynamicSolution.sourceCurrentsA[source.id],
               current > source.maxCurrentA {
                findings.append(finding(
                    code: "electrical.em.source-current-limit",
                    entity: source.id,
                    message: "Source current exceeds the declared source capacity.",
                    observed: current,
                    limit: source.maxCurrentA,
                    actions: ["increase_source_capacity", "add_parallel_source", "reduce_current_demand"]
                ))
                repairs.append(repair(
                    id: "repair-source-current-\(source.id)",
                    kind: "source-capacity-increase",
                    entity: source.id,
                    rationale: "Keep extracted source current within the declared source capacity.",
                    actions: ["increase_source_capacity", "add_parallel_source", "reduce_current_demand"]
                ))
            }
        }

        let metrics = [
            ElectricalSignoffPayload.Metric(name: "static-ir-drop", value: staticDrop.value, unit: "V", limit: rules.maximumIRDropV, passed: staticDrop.value <= rules.maximumIRDropV),
            ElectricalSignoffPayload.Metric(name: "dynamic-ir-drop", value: dynamicDrop.value, unit: "V", limit: rules.maximumIRDropV, passed: dynamicDrop.value <= rules.maximumIRDropV),
            ElectricalSignoffPayload.Metric(name: "segment-current-density", value: segmentDensity.value, unit: "A/um^2", limit: rules.maximumCurrentDensityAperSquareMicron, passed: segmentDensity.value <= rules.maximumCurrentDensityAperSquareMicron),
            ElectricalSignoffPayload.Metric(name: "via-current-density", value: viaDensity.value, unit: "A/um^2", limit: rules.maximumViaCurrentDensityAperSquareMicron, passed: viaDensity.value <= rules.maximumViaCurrentDensityAperSquareMicron),
        ]
        let payload = ElectricalSignoffPayload(
            violationCount: findings.count,
            worstMetric: metrics.map(\.value).max(),
            metricUnit: "mixed",
            axis: axis,
            metrics: metrics,
            findings: findings,
            repairCandidates: repairs,
            provenance: support.provenance(from: input),
            analysisCoverage: .init(
                expectedEntityIDs:
                    input.topology.segments.map { "segment:\($0.id)" }
                    + input.topology.vias.map { "via:\($0.id)" }
                    + input.topology.sources.map { "source:\($0.id)" }
                    + input.topology.loads.map { "load:\($0.id)" },
                analyzedEntityIDs:
                    input.topology.segments.map { "segment:\($0.id)" }
                    + input.topology.vias.map { "via:\($0.id)" }
                    + input.topology.sources.map { "source:\($0.id)" }
                    + input.topology.loads.map { "load:\($0.id)" }
            ),
            cornerID: input.request.configuration.operatingCondition.id
        )
        do {
            return try await support.completedEnvelope(request: request, axis: axis, payload: payload, startedAt: startedAt)
        } catch {
            return try support.failedEnvelope(request: request, axis: axis, error: error, startedAt: startedAt)
        }
    }

    private struct Drop: Sendable {
        var netID: String
        var value: Double
    }

    private struct Density: Sendable {
        var segmentID: String
        var viaID: String
        var value: Double
    }

    private func worstDrop(topology: ElectricalTopology, solution: PowerIntegrityNetworkSolver.Solution) -> Drop {
        var sourceVoltageByNet: [String: Double] = [:]
        sourceVoltageByNet.reserveCapacity(topology.sources.count)
        for source in topology.sources {
            sourceVoltageByNet[source.netID] = max(
                sourceVoltageByNet[source.netID, default: 0],
                source.voltageV
            )
        }
        var minimumVoltageByNet: [String: Double] = [:]
        minimumVoltageByNet.reserveCapacity(topology.nets.count)
        for node in topology.nodes {
            guard let voltage = solution.nodeVoltages[node.id] else {
                continue
            }
            minimumVoltageByNet[node.netID] = min(
                minimumVoltageByNet[node.netID, default: voltage],
                voltage
            )
        }
        var worst = Drop(netID: "unknown", value: 0)
        for net in topology.nets {
            let source = (sourceVoltageByNet[net.id] ?? net.nominalVoltageV ?? 0) * solution.voltageScale
            let minimum = minimumVoltageByNet[net.id] ?? source
            let drop = max(0, source - minimum)
            if drop > worst.value {
                worst = Drop(netID: net.id, value: drop)
            }
        }
        return worst
    }

    private func worstSegmentDensity(topology: ElectricalTopology, solution: PowerIntegrityNetworkSolver.Solution) -> Density {
        var worst = Density(segmentID: "none", viaID: "", value: 0)
        for segment in topology.segments {
            let density = (solution.segmentCurrentsA[segment.id] ?? 0)
                / (segment.widthMicron * segment.thicknessMicron)
            if density > worst.value {
                worst = Density(segmentID: segment.id, viaID: "", value: density)
            }
        }
        return worst
    }

    private func worstViaDensity(topology: ElectricalTopology, solution: PowerIntegrityNetworkSolver.Solution) -> Density {
        var worst = Density(segmentID: "", viaID: "none", value: 0)
        for via in topology.vias {
            let density = (solution.viaCurrentsA[via.id] ?? 0)
                / (via.cutAreaSquareMicron * Double(via.count))
            if density > worst.value {
                worst = Density(segmentID: "", viaID: via.id, value: density)
            }
        }
        return worst
    }

    private func finding(
        code: String,
        entity: String,
        message: String,
        observed: Double,
        limit: Double,
        actions: [String]
    ) -> ElectricalSignoffPayload.Finding {
        ElectricalSignoffPayload.Finding(
            code: code,
            severity: .error,
            message: message,
            entity: entity,
            observedValue: observed,
            limitValue: limit,
            suggestedActions: actions
        )
    }

    private func repair(id: String, kind: String, entity: String, rationale: String, actions: [String]) -> ElectricalSignoffPayload.RepairCandidate {
        ElectricalSignoffPayload.RepairCandidate(candidateID: id, kind: kind, entity: entity, rationale: rationale, actions: actions)
    }
}
