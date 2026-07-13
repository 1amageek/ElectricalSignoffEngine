import Foundation
import XcircuitePackage
import ElectricalSignoffCore

public struct DefaultERCEngine: ERCExecuting {
    public let support: ElectricalSignoffExecutionSupport

    public init(support: ElectricalSignoffExecutionSupport = ElectricalSignoffExecutionSupport()) {
        self.support = support
    }

    public func execute(
        _ request: ElectricalSignoffRequest
    ) async throws -> XcircuiteEngineResultEnvelope<ElectricalSignoffPayload> {
        let axis: ElectricalSignoffAnalysisAxis = .erc
        let startedAt = support.clock.now
        let input: ElectricalSignoffInput
        do {
            input = try await support.load(request: request)
        } catch {
            return support.blockedEnvelope(request: request, axis: axis, error: error, startedAt: startedAt)
        }

        let findings = analyze(input: input)
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
            cornerID: input.request.configuration.operatingCondition.id
        )
        do {
            return try await support.completedEnvelope(request: request, axis: axis, payload: payload, startedAt: startedAt)
        } catch {
            return support.failedEnvelope(request: request, axis: axis, error: error, startedAt: startedAt)
        }
    }

    private func analyze(input: ElectricalSignoffInput) -> [ElectricalSignoffPayload.Finding] {
        let topology = input.topology
        let condition = input.request.configuration.operatingCondition
        let netByID = Dictionary(uniqueKeysWithValues: topology.nets.map { ($0.id, $0) })
        let sourcesByNet = Dictionary(grouping: topology.sources, by: \.netID)
        let driverNets = Set(topology.devices.filter(\.isDriver).flatMap { device in
            device.terminals.values
        })
        var findings: [ElectricalSignoffPayload.Finding] = []

        for (netID, sources) in sourcesByNet where sources.count > 1 {
            findings.append(finding(
                code: "electrical.erc.multiple-drivers",
                entity: netID,
                message: "A power net has multiple independent voltage sources.",
                actions: ["define_source_ownership", "add_power_domain_isolation"]
            ))
        }
        for net in topology.nets {
            let hasDeviceConnection = topology.devices.contains { $0.terminals.values.contains(net.id) }
            let hasLoad = topology.loads.contains { $0.netID == net.id }
            let hasSource = sourcesByNet[net.id]?.isEmpty == false
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
        let domainIDs = Set(topology.domains.map(\.id))
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
                let isPowered = topology.nets.contains {
                    $0.domainID == requiredDomainID && (sourcesByNet[$0.id]?.isEmpty == false)
                }
                if !isPowered {
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
