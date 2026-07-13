import Foundation
import XcircuitePackage
import ElectricalSignoffCore

public struct DefaultLatchUpEngine: LatchUpExecuting {
    public let support: ElectricalSignoffExecutionSupport

    public init(support: ElectricalSignoffExecutionSupport = ElectricalSignoffExecutionSupport()) {
        self.support = support
    }

    public func execute(
        _ request: ElectricalSignoffRequest
    ) async throws -> XcircuiteEngineResultEnvelope<ElectricalSignoffPayload> {
        let axis: ElectricalSignoffAnalysisAxis = .latchUp
        let startedAt = support.clock.now
        let input: ElectricalSignoffInput
        do {
            input = try await support.load(request: request)
            guard !input.topology.wells.isEmpty else {
                throw ElectricalSignoffError.insufficientTopology("latch-up analysis requires extracted well regions")
            }
        } catch {
            return support.blockedEnvelope(request: request, axis: axis, error: error, startedAt: startedAt)
        }

        let findings = analyze(input: input)
        let payload = ElectricalSignoffPayload(
            violationCount: findings.count,
            worstMetric: Double(findings.count),
            metricUnit: "count",
            axis: axis,
            metrics: [ElectricalSignoffPayload.Metric(name: "latch-up-violations", value: Double(findings.count), unit: "count", limit: 0, passed: findings.isEmpty)],
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
        let contactByID = Dictionary(uniqueKeysWithValues: topology.substrateContacts.map { ($0.id, $0) })
        let netsByID = Dictionary(uniqueKeysWithValues: topology.nets.map { ($0.id, $0) })
        var findings: [ElectricalSignoffPayload.Finding] = []
        for well in topology.wells {
            if well.spacingToOppositeWellMicron < well.requiredSpacingMicron {
                findings.append(finding(
                    code: "electrical.latch-up.well-spacing",
                    entity: well.id,
                    message: "Well spacing is below the declared latch-up guard distance.",
                    observed: well.spacingToOppositeWellMicron,
                    limit: well.requiredSpacingMicron,
                    actions: ["increase_well_spacing", "add_guard_ring", "review_pdk_latch_up_rule"]
                ))
            }
            let contacts = well.substrateContactIDs.compactMap { contactByID[$0] }
            if contacts.isEmpty {
                findings.append(finding(
                    code: "electrical.latch-up.substrate-contact-missing",
                    entity: well.id,
                    message: "The well has no extracted substrate or well contact.",
                    actions: ["add_substrate_contact", "add_guard_ring", "repair_well_connectivity"]
                ))
            }
            for contact in contacts {
                guard let net = netsByID[contact.netID], net.kind == .ground || net.kind == .substrate else {
                    findings.append(finding(
                        code: "electrical.latch-up.contact-net-invalid",
                        entity: contact.id,
                        message: "The substrate contact is not connected to a ground or substrate net.",
                        actions: ["connect_contact_to_substrate", "correct_net_kind"]
                    ))
                    continue
                }
                if contact.areaSquareMicron <= 0 {
                    findings.append(finding(
                        code: "electrical.latch-up.contact-area-invalid",
                        entity: contact.id,
                        message: "The substrate contact has no positive extracted area.",
                        actions: ["increase_contact_area", "re-run_layout_extraction"]
                    ))
                }
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
            ElectricalSignoffPayload.RepairCandidate(candidateID: "repair-latch-up-\(index + 1)", kind: finding.code, entity: finding.entity ?? "unknown", rationale: finding.message, actions: finding.suggestedActions)
        }
    }
}
