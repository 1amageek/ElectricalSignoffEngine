import Foundation
import ElectricalSignoffCore
import PowerIntegrityEngine
import ERCEngine
import ESDEngine
import LatchUpEngine
import AgingEngine
import XcircuitePackage

public struct ElectricalSignoffEngine: ElectricalSignoffExecuting {
    public let powerIntegrity: any PowerIntegrityAnalyzing
    public let erc: any ERCExecuting
    public let esd: any ESDExecuting
    public let latchUp: any LatchUpExecuting
    public let aging: any AgingAnalyzing

    public init(
        powerIntegrity: any PowerIntegrityAnalyzing,
        erc: any ERCExecuting,
        esd: any ESDExecuting,
        latchUp: any LatchUpExecuting,
        aging: any AgingAnalyzing
    ) {
        self.powerIntegrity = powerIntegrity
        self.erc = erc
        self.esd = esd
        self.latchUp = latchUp
        self.aging = aging
    }

    public init(support: ElectricalSignoffExecutionSupport = ElectricalSignoffExecutionSupport()) {
        self.init(
            powerIntegrity: DefaultPowerIntegrityEngine(support: support),
            erc: DefaultERCEngine(support: support),
            esd: DefaultESDEngine(support: support),
            latchUp: DefaultLatchUpEngine(support: support),
            aging: DefaultAgingEngine(support: support)
        )
    }

    public func execute(
        _ request: ElectricalSignoffRequest
    ) async throws -> ElectricalSignoffRunResult {
        try await execute(request, axes: request.configuration.requiredAxes)
    }

    public func execute(
        _ request: ElectricalSignoffRequest,
        axes: [ElectricalSignoffAnalysisAxis] = ElectricalSignoffEngineAPI.supportedAxes
    ) async throws -> ElectricalSignoffRunResult {
        try request.validate()
        guard !axes.isEmpty else {
            throw ElectricalSignoffError.invalidConfiguration("at least one analysis axis is required")
        }
        guard axes.allSatisfy({ $0 != .aggregate }) else {
            throw ElectricalSignoffError.invalidConfiguration("aggregate cannot be executed as an individual axis")
        }
        guard Set(axes).count == axes.count else {
            throw ElectricalSignoffError.invalidConfiguration("analysis axes must be unique")
        }
        let uniqueAxes = axes
        var cornerResults: [String: [ElectricalSignoffAnalysisAxis: XcircuiteEngineResultEnvelope<ElectricalSignoffPayload>]] = [:]
        for condition in request.configuration.operatingConditions {
            try Task.checkCancellation()
            var cornerRequest = request
            var cornerConfiguration = request.configuration
            cornerConfiguration.operatingConditions = [condition]
            cornerRequest.configuration = cornerConfiguration
            cornerResults[condition.id] = try await executeSingle(cornerRequest, axes: uniqueAxes)
        }

        var results: [ElectricalSignoffAnalysisAxis: XcircuiteEngineResultEnvelope<ElectricalSignoffPayload>] = [:]
        for axis in uniqueAxes {
            try Task.checkCancellation()
            let candidates = cornerResults.values.compactMap { $0[axis] }
            var worst: XcircuiteEngineResultEnvelope<ElectricalSignoffPayload>?
            for candidate in candidates {
                guard let current = worst else {
                    worst = candidate
                    continue
                }
                if isMoreSevere(candidate, than: current) {
                    worst = candidate
                }
            }
            if let worst {
                results[axis] = worst
            }
        }
        let statuses = cornerResults.values.flatMap { $0.values }.map(\.status)
        let result = ElectricalSignoffRunResult(
            runID: request.runID,
            status: aggregateStatus(statuses),
            axisResults: results,
            cornerResults: cornerResults
        )
        try result.validate()
        return result
    }

    private func executeSingle(
        _ request: ElectricalSignoffRequest,
        axes: [ElectricalSignoffAnalysisAxis]
    ) async throws -> [ElectricalSignoffAnalysisAxis: XcircuiteEngineResultEnvelope<ElectricalSignoffPayload>] {
        var results: [ElectricalSignoffAnalysisAxis: XcircuiteEngineResultEnvelope<ElectricalSignoffPayload>] = [:]
        for axis in axes {
            try Task.checkCancellation()
            let result: XcircuiteEngineResultEnvelope<ElectricalSignoffPayload>
            switch axis {
            case .powerIntegrity:
                result = try await powerIntegrity.execute(request)
            case .erc:
                result = try await erc.execute(request)
            case .esd:
                result = try await esd.execute(request)
            case .latchUp:
                result = try await latchUp.execute(request)
            case .aging:
                result = try await aging.execute(request)
            case .aggregate:
                continue
            }
            guard result.schemaVersion == ElectricalSignoffRequest.currentSchemaVersion,
                  result.runID == request.runID,
                  result.payload.axis == axis,
                  result.payload.cornerID == request.configuration.operatingCondition.id else {
                throw ElectricalSignoffError.invalidExecutionResult(
                    "axis (axis.rawValue) returned mismatched run, schema, axis or corner identity"
                )
            }
            results[axis] = result
        }
        return results
    }

    private func isMoreSevere(
        _ candidate: XcircuiteEngineResultEnvelope<ElectricalSignoffPayload>,
        than current: XcircuiteEngineResultEnvelope<ElectricalSignoffPayload>
    ) -> Bool {
        let candidateRank = statusRank(candidate.status)
        let currentRank = statusRank(current.status)
        if candidateRank != currentRank {
            return candidateRank > currentRank
        }
        if candidate.payload.violationCount != current.payload.violationCount {
            return candidate.payload.violationCount > current.payload.violationCount
        }
        if candidate.payload.findings.count != current.payload.findings.count {
            return candidate.payload.findings.count > current.payload.findings.count
        }
        return (candidate.payload.cornerID ?? "") < (current.payload.cornerID ?? "")
    }

    private func statusRank(_ status: XcircuiteEngineExecutionStatus) -> Int {
        switch status {
        case .completed: return 0
        case .cancelled: return 1
        case .blocked: return 2
        case .failed: return 3
        }
    }

    private func aggregateStatus(_ statuses: some Sequence<XcircuiteEngineExecutionStatus>) -> XcircuiteEngineExecutionStatus {
        let statuses = Array(statuses)
        if statuses.contains(.failed) {
            return .failed
        }
        if statuses.contains(.blocked) {
            return .blocked
        }
        if statuses.contains(.cancelled) {
            return .cancelled
        }
        return .completed
    }
}
