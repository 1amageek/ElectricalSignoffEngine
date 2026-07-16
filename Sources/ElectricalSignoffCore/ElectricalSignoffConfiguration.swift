import Foundation

public struct ElectricalSignoffConfiguration: Sendable, Hashable, Codable {
    public var operatingConditions: [ElectricalOperatingCondition]
    public var minimumLifetimeHours: Double
    public var requiredAxes: [ElectricalSignoffAnalysisAxis]

    public var operatingCondition: ElectricalOperatingCondition {
        operatingConditions.first ?? .typical
    }

    public init(
        minimumLifetimeHours: Double = 87_600,
        requiredAxes: [ElectricalSignoffAnalysisAxis] = ElectricalSignoffAnalysisAxis.allCases.filter { $0 != .aggregate },
        operatingConditions: [ElectricalOperatingCondition] = [.typical]
    ) {
        self.operatingConditions = operatingConditions
        self.minimumLifetimeHours = minimumLifetimeHours
        self.requiredAxes = requiredAxes
    }

    public func validate() throws {
        guard !operatingConditions.isEmpty else {
            throw ElectricalSignoffError.invalidConfiguration("at least one operating condition is required")
        }
        var conditionIDs = Set<String>()
        for condition in operatingConditions {
            guard !condition.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !condition.pdkCornerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ElectricalSignoffError.invalidConfiguration("operating condition identifiers are required")
            }
            guard conditionIDs.insert(condition.id).inserted else {
                throw ElectricalSignoffError.invalidConfiguration("operating condition identifiers must be unique")
            }
            guard condition.temperatureC.isFinite,
                  condition.supplyVoltageScale.isFinite,
                  condition.supplyVoltageScale > 0,
                  condition.activityScale.isFinite,
                  condition.activityScale >= 0 else {
                throw ElectricalSignoffError.invalidConfiguration("operating condition values are invalid")
            }
        }
        guard minimumLifetimeHours.isFinite, minimumLifetimeHours > 0 else {
            throw ElectricalSignoffError.invalidConfiguration("minimum lifetime must be positive")
        }
        guard !requiredAxes.isEmpty,
              Set(requiredAxes).count == requiredAxes.count,
              requiredAxes.allSatisfy({ $0 != .aggregate }) else {
            throw ElectricalSignoffError.invalidConfiguration(
                "required axes must be non-empty, unique and cannot contain aggregate"
            )
        }
    }
}
