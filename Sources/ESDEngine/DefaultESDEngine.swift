import Foundation
import CircuiteFoundation
import ElectricalSignoffCore

public struct DefaultESDEngine: ESDExecuting {
    private struct NetDescriptor {
        var kind: ElectricalTopology.NetKind
        var domainID: String?
    }

    private struct DomainNetKey: Hashable {
        var domainID: String
        var netID: String
    }

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
            guard input.topology.nets.contains(where: {
                $0.kind == .power && $0.domainID != nil
            }) else {
                throw ElectricalSignoffError.insufficientTopology(
                    "ESD analysis requires at least one domain-bound power rail"
                )
            }
        } catch {
            return try support.blockedEnvelope(request: request, axis: axis, error: error, startedAt: startedAt)
        }

        let findings = analyze(input: input)
        let coveredEntities = input.topology.domains
            .filter { $0.nominalVoltageV > 0 }
            .map { "domain:\($0.id)" }
            + input.topology.nets
            .filter { $0.kind == .power && $0.domainID != nil }
            .map { "power-net:\($0.id)" }
            + input.topology.esdClamps.map { "clamp:\($0.id)" }
        let payload = ElectricalSignoffPayload(
            violationCount: findings.count,
            worstMetric: Double(findings.count),
            metricUnit: "count",
            axis: axis,
            metrics: [ElectricalSignoffPayload.Metric(name: "esd-violations", value: Double(findings.count), unit: "count", limit: 0, passed: findings.isEmpty)],
            findings: findings,
            repairCandidates: repairs(from: findings),
            provenance: support.provenance(from: input),
            analysisCoverage: .init(
                expectedEntityIDs: coveredEntities,
                analyzedEntityIDs: coveredEntities
            ),
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
        var netByID: [String: NetDescriptor] = [:]
        netByID.reserveCapacity(topology.nets.count)
        var powerNetIDsByDomain: [String: [String]] = [:]
        powerNetIDsByDomain.reserveCapacity(topology.domains.count)
        for net in topology.nets {
            netByID[net.id] = NetDescriptor(kind: net.kind, domainID: net.domainID)
            if net.kind == .power, let domainID = net.domainID {
                powerNetIDsByDomain[domainID, default: []].append(net.id)
            }
        }
        var maximumVoltageByDomain: [String: Double] = [:]
        maximumVoltageByDomain.reserveCapacity(topology.domains.count)
        for domain in topology.domains {
            maximumVoltageByDomain[domain.id] = domain.maximumVoltageV
        }
        var protectedDomainNetKeys: Set<DomainNetKey> = []
        protectedDomainNetKeys.reserveCapacity(topology.esdClamps.count)
        for clamp in topology.esdClamps {
            protectedDomainNetKeys.insert(
                DomainNetKey(domainID: clamp.domainID, netID: clamp.protectedNetID)
            )
        }
        var stressCurrentByNet: [String: Double] = [:]
        stressCurrentByNet.reserveCapacity(topology.loads.count)
        for load in topology.loads {
            stressCurrentByNet[load.netID, default: 0] +=
                load.staticCurrentA + load.dynamicCurrentA * condition.activityScale
        }
        var findings: [ElectricalSignoffPayload.Finding] = []
        for domain in topology.domains where domain.nominalVoltageV > 0 {
            let protectedNetIDs = powerNetIDsByDomain[domain.id] ?? []
            if protectedNetIDs.isEmpty {
                findings.append(finding(
                    code: "electrical.esd.domain-power-rail-missing",
                    entity: domain.id,
                    message: "The voltage domain has no extracted power rail to protect.",
                    actions: ["extract_domain_power_rail", "repair_power_domain_annotation"]
                ))
            }
            for netID in protectedNetIDs {
                if !protectedDomainNetKeys.contains(
                    DomainNetKey(domainID: domain.id, netID: netID)
                ) {
                    findings.append(finding(
                        code: "electrical.esd.clamp-missing",
                        entity: netID,
                        message: "No extracted ESD clamp protects the power-domain rail.",
                        actions: ["add_domain_clamp", "connect_existing_clamp", "review_esd_power_intent"]
                    ))
                }
            }
        }
        for clamp in topology.esdClamps {
            guard maximumVoltageByDomain[clamp.domainID] != nil,
                  netByID[clamp.protectedNetID] != nil,
                  netByID[clamp.groundNetID] != nil else {
                findings.append(finding(
                    code: "electrical.esd.path-reference-invalid",
                    entity: clamp.id,
                    message: "The ESD clamp references a missing domain or net.",
                    actions: ["repair_esd_connectivity", "re-run_topology_extraction"]
                ))
                continue
            }
            guard let protectedNet = netByID[clamp.protectedNetID],
            protectedNet.kind == .power,
            protectedNet.domainID == clamp.domainID else {
                findings.append(finding(
                    code: "electrical.esd.protected-net-invalid",
                    entity: clamp.id,
                    message: "The ESD clamp must protect a power rail in its declared voltage domain.",
                    actions: ["repair_clamp_domain_binding", "connect_clamp_to_power_rail"]
                ))
                continue
            }
            guard let groundNet = netByID[clamp.groundNetID],
            groundNet.kind == .ground || groundNet.kind == .substrate else {
                findings.append(finding(
                    code: "electrical.esd.ground-path-invalid",
                    entity: clamp.id,
                    message: "The ESD clamp discharge path must terminate at a ground or substrate net.",
                    actions: ["connect_clamp_to_ground", "correct_discharge_net_kind"]
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
            if let maximumVoltage = maximumVoltageByDomain[clamp.domainID],
               clamp.triggerVoltageV >= maximumVoltage * condition.supplyVoltageScale {
                findings.append(finding(
                    code: "electrical.esd.trigger-too-high",
                    entity: clamp.id,
                    message: "The ESD clamp trigger voltage does not protect the domain maximum voltage.",
                    observed: clamp.triggerVoltageV,
                    limit: maximumVoltage,
                    actions: ["select_lower_trigger_clamp", "correct_domain_voltage"]
                ))
            }
            let stressCurrent = stressCurrentByNet[clamp.protectedNetID, default: 0]
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
