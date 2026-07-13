import Foundation

public struct ElectricalOperatingCondition: Sendable, Hashable, Codable {
    public var id: String
    public var pdkCornerID: String
    public var temperatureC: Double
    public var supplyVoltageScale: Double
    public var activityScale: Double

    public static let typical = ElectricalOperatingCondition(
        id: "typical",
        pdkCornerID: "typical",
        temperatureC: 25,
        supplyVoltageScale: 1,
        activityScale: 1
    )

    public init(
        id: String,
        pdkCornerID: String,
        temperatureC: Double,
        supplyVoltageScale: Double,
        activityScale: Double
    ) {
        self.id = id
        self.pdkCornerID = pdkCornerID
        self.temperatureC = temperatureC
        self.supplyVoltageScale = supplyVoltageScale
        self.activityScale = activityScale
    }
}
