import Foundation

public struct ElectricalSignoffConfiguration: Sendable, Hashable, Codable {
    public var operatingConditions: [ElectricalOperatingCondition]
    public var minimumLifetimeHours: Double
    public var requiredAxes: [ElectricalSignoffAnalysisAxis]

    public var operatingCondition: ElectricalOperatingCondition {
        get { operatingConditions.first ?? .typical }
        set {
            if operatingConditions.isEmpty {
                operatingConditions = [newValue]
            } else {
                operatingConditions[0] = newValue
            }
        }
    }

    public var temperatureC: Double {
        get { operatingCondition.temperatureC }
        set { operatingCondition.temperatureC = newValue }
    }

    public var dynamicActivityScale: Double {
        get { operatingCondition.activityScale }
        set { operatingCondition.activityScale = newValue }
    }

    public init(
        temperatureC: Double = 25,
        dynamicActivityScale: Double = 1,
        minimumLifetimeHours: Double = 87_600,
        requiredAxes: [ElectricalSignoffAnalysisAxis] = ElectricalSignoffAnalysisAxis.allCases.filter { $0 != .aggregate },
        operatingCondition: ElectricalOperatingCondition? = nil,
        operatingConditions: [ElectricalOperatingCondition]? = nil
    ) {
        let defaultCondition = operatingCondition ?? ElectricalOperatingCondition(
            id: "typical",
            pdkCornerID: "typical",
            temperatureC: temperatureC,
            supplyVoltageScale: 1,
            activityScale: dynamicActivityScale
        )
        if let operatingConditions, !operatingConditions.isEmpty {
            self.operatingConditions = operatingConditions
        } else {
            self.operatingConditions = [defaultCondition]
        }
        self.minimumLifetimeHours = minimumLifetimeHours
        self.requiredAxes = requiredAxes
    }

    private enum CodingKeys: String, CodingKey {
        case operatingCondition
        case operatingConditions
        case temperatureC
        case dynamicActivityScale
        case minimumLifetimeHours
        case requiredAxes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyTemperature = try container.decodeIfPresent(Double.self, forKey: .temperatureC) ?? 25
        let legacyActivity = try container.decodeIfPresent(Double.self, forKey: .dynamicActivityScale) ?? 1
        let legacyCondition = try container.decodeIfPresent(ElectricalOperatingCondition.self, forKey: .operatingCondition)
            ?? ElectricalOperatingCondition(
                id: "typical",
                pdkCornerID: "typical",
                temperatureC: legacyTemperature,
                supplyVoltageScale: 1,
                activityScale: legacyActivity
            )
        let conditions = try container.decodeIfPresent([ElectricalOperatingCondition].self, forKey: .operatingConditions)
        self.init(
            minimumLifetimeHours: try container.decodeIfPresent(Double.self, forKey: .minimumLifetimeHours) ?? 87_600,
            requiredAxes: try container.decodeIfPresent([ElectricalSignoffAnalysisAxis].self, forKey: .requiredAxes)
                ?? ElectricalSignoffAnalysisAxis.allCases.filter { $0 != .aggregate },
            operatingCondition: legacyCondition,
            operatingConditions: conditions
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(operatingCondition, forKey: .operatingCondition)
        try container.encode(operatingConditions, forKey: .operatingConditions)
        try container.encode(operatingCondition.temperatureC, forKey: .temperatureC)
        try container.encode(operatingCondition.activityScale, forKey: .dynamicActivityScale)
        try container.encode(minimumLifetimeHours, forKey: .minimumLifetimeHours)
        try container.encode(requiredAxes, forKey: .requiredAxes)
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
