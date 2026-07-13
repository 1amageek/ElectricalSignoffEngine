import Foundation
import CircuiteFoundation
import ElectricalSignoffCore

public struct DefaultESDEngine: ESDExecuting {
    public let support: ElectricalSignoffExecutionSupport

    public init(support: ElectricalSignoffExecutionSupport = ElectricalSignoffExecutionSupport()) {
        self.support = support
    }

    public func execute(
        _ request: ElectricalSignoffRequest
    ) async throws -> ElectricalSignoffResult {
        let axis: ElectricalSignoffAnalysisAxis = .esd
        let startedAt = support.clock.now
        let input: ElectricalSignoffInput
        do {
            input = try await support.load(request: request)
            guard !input.topology.domains.isEmpty else {
                throw ElectricalSignoffError.insufficientTopology("ESD analysis requires extracted voltage domains")
            }
        } catch {
            return try support.blockedEnvelope(request: request, axis: axis, error: error, startedAt: startedAt)
        }

        let findings = analyze(input: input)
        let payload = ElectricalSignoffPayload(
            violationCount: findings.count,
            worstMetric: Double(findings.count),
            metricUnit: "count",
            axis: axis,
            metrics: [ElectricalSignoffPayload.Metric(name: "esd-violations", value: Double(findings.count), unit: "count", limit: 0, passed: findings.isEmpty)],
            findings: findings,
            repairCandidates: repairs(from: findings),
            provenance: support.provenance(from: input),
            cornerID: input.request.configuration.operatingCondition.id
        )
        do {
            return try await support.completedEnvelope(request: request, axis: axis, payload: payload, startedAt: startedAt)
        } catch {
            return try support.failedEnvelope(request: request, axis: axis, error: error, startedAt: startedAt)
        }
    }

    private func analyze(input: ElectricalSignoffInput) -> [ElectricalSignoffPayload.Finding] {
        let topology = input.topology
        let condition = input.request.configuration.operatingCondition
        let rules = topology.rules(for: condition)
        let netIDs = Set(topology.nets.map(\.id))
        let domainIDs = Set(topology.domains.map(\.id))
        var findings: [ElectricalSignoffPayload.Finding] = []
        for domain in topology.domains {
            let protectedNets = topology.nets.filter { $0.domainID == domain.id && $0.kind == .power }
            for net in protectedNets {
                let clamps = topology.esdClamps.filter { $0.domainID == domain.id && $0.protectedNetID == net.id }
                if clamps.isEmpty {
                    findings.append(finding(
                        code: "electrical.esd.clamp-missing",
                        entity: net.id,
                        message: "No extracted ESD clamp protects the power-domain rail.",
                        actions: ["add_domain_clamp", "connect_existing_clamp", "review_esd_power_intent"]
                    ))
                }
            }
        }
        for clamp in topology.esdClamps {
            guard domainIDs.contains(clamp.domainID), netIDs.contains(clamp.protectedNetID), netIDs.contains(clamp.groundNetID) else {
                findings.append(finding(
                    code: "electrical.esd.path-reference-invalid",
                    entity: clamp.id,
                    message: "The ESD clamp references a missing domain or net.",
                    actions: ["repair_esd_connectivity", "re-run_topology_extraction"]
                ))
                continue
            }
            if clamp.resistanceOhm < rules.minimumESDResistanceOhm {
                findings.append(finding(
                    code: "electrical.esd.resistance-too-low",
                    entity: clamp.id,
                    message: "The extracted ESD path resistance is below the declared process floor.",
                    observed: clamp.resistanceOhm,
                    limit: rules.minimumESDResistanceOhm,
                    actions: ["review_clamp_model", "check_short_path", "verify_pdk_esd_rule"]
                ))
            }
            let domain = topology.domains.first { $0.id == clamp.domainID }
            if let domain, clamp.triggerVoltageV >= domain.maximumVoltageV * condition.supplyVoltageScale {
                findings.append(finding(
                    code: "electrical.esd.trigger-too-high",
                    entity: clamp.id,
                    message: "The ESD clamp trigger voltage does not protect the domain maximum voltage.",
                    observed: clamp.triggerVoltageV,
                    limit: domain.maximumVoltageV,
                    actions: ["select_lower_trigger_clamp", "correct_domain_voltage"]
                ))
            }
            let stressCurrent = topology.loads
                .filter { $0.netID == clamp.protectedNetID }
                .reduce(0) { partial, load in
                    partial + load.staticCurrentA + load.dynamicCurrentA * condition.activityScale
                }
            if stressCurrent > clamp.maximumCurrentA {
                findings.append(finding(
                    code: "electrical.esd.current-capacity",
                    entity: clamp.id,
                    message: "The extracted clamp current capacity is below the declared stress current.",
                    observed: stressCurrent,
                    limit: clamp.maximumCurrentA,
                    actions: ["increase_clamp_current_capacity", "add_parallel_clamp", "reduce_esd_stress"]
                ))
            }
        }
        return findings
    }

    private func finding(code: String, entity: String, message: String, actions: [String]) -> ElectricalSignoffPayload.Finding {
        ElectricalSignoffPayload.Finding(code: code, severity: .error, message: message, entity: entity, suggestedActions: actions)
    }

    private func finding(code: String, entity: String, message: String, observed: Double, limit: Double, actions: [String]) -> ElectricalSignoffPayload.Finding {
        ElectricalSignoffPayload.Finding(code: code, severity: .error, message: message, entity: entity, observedValue: observed, limitValue: limit, suggestedActions: actions)
    }

    private func repairs(from findings: [ElectricalSignoffPayload.Finding]) -> [ElectricalSignoffPayload.RepairCandidate] {
        findings.enumerated().map { index, finding in
            ElectricalSignoffPayload.RepairCandidate(candidateID: "repair-esd-\(index + 1)", kind: finding.code, entity: finding.entity ?? "unknown", rationale: finding.message, actions: finding.suggestedActions)
        }
    }
}
