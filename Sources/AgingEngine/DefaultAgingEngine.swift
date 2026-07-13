import Foundation
import CircuiteFoundation
import ElectricalSignoffCore

public struct DefaultAgingEngine: AgingAnalyzing {
    public let support: ElectricalSignoffExecutionSupport

    public init(support: ElectricalSignoffExecutionSupport = ElectricalSignoffExecutionSupport()) {
        self.support = support
    }

    public func execute(
        _ request: ElectricalSignoffRequest
    ) async throws -> ElectricalSignoffResult {
        let axis: ElectricalSignoffAnalysisAxis = .aging
        let startedAt = support.clock.now
        let input: ElectricalSignoffInput
        do {
            input = try await support.load(request: request)
            guard !input.topology.agingModels.isEmpty else {
                throw ElectricalSignoffError.insufficientTopology("aging analysis requires NBTI, HCI or TDDB model declarations")
            }
        } catch {
            return try support.blockedEnvelope(request: request, axis: axis, error: error, startedAt: startedAt)
        }

        let result = analyze(input: input)
        let payload = ElectricalSignoffPayload(
            violationCount: result.findings.count,
            worstMetric: result.minimumLifetime,
            metricUnit: "hours",
            axis: axis,
            metrics: [ElectricalSignoffPayload.Metric(name: "minimum-lifetime", value: result.minimumLifetime, unit: "hours", limit: input.request.configuration.minimumLifetimeHours, passed: result.minimumLifetime >= input.request.configuration.minimumLifetimeHours)],
            findings: result.findings,
            repairCandidates: repairs(from: result.findings),
            provenance: support.provenance(from: input),
            cornerID: input.request.configuration.operatingCondition.id
        )
        do {
            return try await support.completedEnvelope(request: request, axis: axis, payload: payload, startedAt: startedAt)
        } catch {
            return try support.failedEnvelope(request: request, axis: axis, error: error, startedAt: startedAt)
        }
    }

    private struct Result: Sendable {
        var minimumLifetime: Double
        var findings: [ElectricalSignoffPayload.Finding]
    }

    private func analyze(input: ElectricalSignoffInput) -> Result {
        let topology = input.topology
        let condition = input.request.configuration.operatingCondition
        let netByID = Dictionary(uniqueKeysWithValues: topology.nets.map { ($0.id, $0) })
        var minimumLifetime = Double.greatestFiniteMagnitude
        var findings: [ElectricalSignoffPayload.Finding] = []
        for model in topology.agingModels {
            let device = topology.devices.first { $0.id == model.deviceID }
            let voltage = (device?.terminals.values.compactMap { netByID[$0]?.nominalVoltageV }.max() ?? model.referenceVoltageV)
                * condition.supplyVoltageScale
            let voltageRatio = max(0.01, voltage / max(model.referenceVoltageV, 0.001))
            let temperatureFactor = exp(max(0, condition.temperatureC - model.referenceTemperatureC) * max(model.tddbCoefficient, 0) / 100)
            let nbtiFactor = pow(voltageRatio, max(model.nbtiCoefficient, 0))
            let hciFactor = pow(max(model.dutyCycle, 0.001), max(model.hciCoefficient, 0))
            let stress = max(1, nbtiFactor * hciFactor * temperatureFactor)
            let lifetime = model.lifetimeHoursAtReference / stress
            minimumLifetime = min(minimumLifetime, lifetime)
            if lifetime < input.request.configuration.minimumLifetimeHours {
                findings.append(ElectricalSignoffPayload.Finding(
                    code: "electrical.aging.lifetime",
                    severity: .error,
                    message: "The projected device lifetime is below the declared signoff requirement.",
                    entity: model.deviceID,
                    observedValue: lifetime,
                    limitValue: input.request.configuration.minimumLifetimeHours,
                    suggestedActions: ["reduce_device_voltage", "reduce_duty_cycle", "increase_device_area", "select_reliability_model"]
                ))
            }
        }
        if minimumLifetime == Double.greatestFiniteMagnitude {
            minimumLifetime = 0
        }
        return Result(minimumLifetime: minimumLifetime, findings: findings)
    }

    private func repairs(from findings: [ElectricalSignoffPayload.Finding]) -> [ElectricalSignoffPayload.RepairCandidate] {
        findings.enumerated().map { index, finding in
            ElectricalSignoffPayload.RepairCandidate(candidateID: "repair-aging-\(index + 1)", kind: finding.code, entity: finding.entity ?? "unknown", rationale: finding.message, actions: finding.suggestedActions)
        }
    }
}
