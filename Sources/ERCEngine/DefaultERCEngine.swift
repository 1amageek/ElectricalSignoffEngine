import Foundation
import CircuiteFoundation
import ElectricalSignoffCore

public struct DefaultERCEngine: ERCExecuting {
    private struct NetDescriptor {
        var kind: ElectricalTopology.NetKind
        var nominalVoltageV: Double?
        var domainID: String?
    }

    public let support: ElectricalSignoffExecutionSupport

    public init(support: ElectricalSignoffExecutionSupport = ElectricalSignoffExecutionSupport()) {
        self.support = support
    }

    public func execute(
        _ request: ElectricalSignoffRequest
    ) async throws -> ElectricalSignoffResult {
        let axis: ElectricalSignoffAnalysisAxis = .erc
        let startedAt = support.clock.now
        let input: ElectricalSignoffInput
        do {
            input = try await support.load(request: request)
        } catch {
            return try support.blockedEnvelope(request: request, axis: axis, error: error, startedAt: startedAt)
        }

        let findings = analyze(input: input)
        let coveredEntities =
            input.topology.nets.map { "net:\($0.id)" }
            + input.topology.devices.map { "device:\($0.id)" }
            + input.topology.domains.map { "domain:\($0.id)" }
            + input.topology.sources.map { "source:\($0.id)" }
            + input.topology.loads.map { "load:\($0.id)" }
        let metrics = [
            ElectricalSignoffPayload.Metric(
                name: "erc-violations",
                value: Double(findings.count),
                unit: "count",
                limit: 0,
                passed: findings.isEmpty
            )
        ]
        let payload = ElectricalSignoffPayload(
            violationCount: findings.count,
            worstMetric: Double(findings.count),
            metricUnit: "count",
            axis: axis,
            metrics: metrics,
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
        var netByID: [String: NetDescriptor] = [:]
        netByID.reserveCapacity(topology.nets.count)
        for net in topology.nets {
            netByID[net.id] = NetDescriptor(
                kind: net.kind,
                nominalVoltageV: net.nominalVoltageV,
                domainID: net.domainID
            )
        }
        var sourceCountByNet: [String: Int] = [:]
        sourceCountByNet.reserveCapacity(topology.sources.count)
        for source in topology.sources {
            sourceCountByNet[source.netID, default: 0] += 1
        }
        var connectedNetIDs: Set<String> = []
        var driverNets: Set<String> = []
        for device in topology.devices {
            for netID in device.terminals.values {
                connectedNetIDs.insert(netID)
                if device.isDriver {
                    driverNets.insert(netID)
                }
            }
        }
        var loadNetIDs: Set<String> = []
        loadNetIDs.reserveCapacity(topology.loads.count)
        for load in topology.loads {
            loadNetIDs.insert(load.netID)
        }
        var poweredDomainIDs: Set<String> = []
        poweredDomainIDs.reserveCapacity(topology.domains.count)
        for net in topology.nets where sourceCountByNet[net.id, default: 0] > 0 {
            if let domainID = net.domainID {
                poweredDomainIDs.insert(domainID)
            }
        }
        var findings: [ElectricalSignoffPayload.Finding] = []

        for (netID, sourceCount) in sourceCountByNet where sourceCount > 1 {
            findings.append(finding(
                code: "electrical.erc.multiple-drivers",
                entity: netID,
                message: "A power net has multiple independent voltage sources.",
                actions: ["define_source_ownership", "add_power_domain_isolation"]
            ))
        }
        for net in topology.nets {
            let hasDeviceConnection = connectedNetIDs.contains(net.id)
            let hasLoad = loadNetIDs.contains(net.id)
            let hasSource = sourceCountByNet[net.id, default: 0] > 0
            let hasDriver = driverNets.contains(net.id)
            if (hasDeviceConnection || hasLoad) && !hasSource && !hasDriver {
                findings.append(finding(
                    code: "electrical.erc.floating-net",
                    entity: net.id,
                    message: "The extracted net has consumers but no source or driver.",
                    actions: ["connect_net_to_driver", "add_pull_device", "review_extraction_connectivity"]
                ))
            }
        }
        for device in topology.devices {
            for netID in Set(device.terminals.values) {
                guard let net = netByID[netID] else {
                    continue
                }
                if let maximumVoltage = device.maxTerminalVoltageV,
                   let nominalVoltage = net.nominalVoltageV,
                   nominalVoltage * condition.supplyVoltageScale > maximumVoltage {
                    findings.append(finding(
                        code: "electrical.erc.overstress",
                        entity: "\(device.id):\(netID)",
                        message: "The connected net nominal voltage exceeds the device terminal limit.",
                        actions: ["insert_level_shifter", "change_device_variant", "correct_power_domain_assignment"]
                    ))
                }
                if let deviceDomain = device.domainID,
                   let netDomain = net.domainID,
                   deviceDomain != netDomain,
                   net.kind != .ground,
                   net.kind != .substrate {
                    findings.append(finding(
                        code: "electrical.erc.domain-mismatch",
                        entity: "\(device.id):\(netID)",
                        message: "The device and connected net belong to different voltage domains.",
                        actions: ["insert_domain_isolation", "correct_domain_annotation", "review_power_intent"]
                    ))
                }
            }
        }
        var domainIDs: Set<String> = []
        domainIDs.reserveCapacity(topology.domains.count)
        for domain in topology.domains {
            domainIDs.insert(domain.id)
        }
        for domain in topology.domains {
            for requiredDomainID in domain.requiresPowerDomainIDs {
                guard domainIDs.contains(requiredDomainID) else {
                    findings.append(finding(
                        code: "electrical.erc.sequencing-reference-missing",
                        entity: domain.id,
                        message: "A power sequencing prerequisite is not present in the extracted domain set.",
                        actions: ["add_power_domain", "correct_power_intent_sequence"]
                    ))
                    continue
                }
                if !poweredDomainIDs.contains(requiredDomainID) {
                    findings.append(finding(
                        code: "electrical.erc.sequencing-unpowered",
                        entity: domain.id,
                        message: "A required power sequencing prerequisite has no extracted source.",
                        actions: ["add_domain_source", "review_power_up_sequence"]
                    ))
                }
            }
        }
        return findings
    }

    private func finding(code: String, entity: String, message: String, actions: [String]) -> ElectricalSignoffPayload.Finding {
        ElectricalSignoffPayload.Finding(
            code: code,
            severity: .error,
            message: message,
            entity: entity,
            suggestedActions: actions
        )
    }

    private func repairs(from findings: [ElectricalSignoffPayload.Finding]) -> [ElectricalSignoffPayload.RepairCandidate] {
        findings.enumerated().map { index, finding in
            ElectricalSignoffPayload.RepairCandidate(
                candidateID: "repair-erc-\(index + 1)",
                kind: finding.code,
                entity: finding.entity ?? "unknown",
                rationale: finding.message,
                actions: finding.suggestedActions
            )
        }
    }
}
