import Foundation

public enum ElectricalSignoffAnalysisAxis: String, Sendable, Hashable, Codable, CaseIterable {
    case powerIntegrity = "power-integrity"
    case erc
    case esd
    case latchUp = "latch-up"
    case aging
    case aggregate
}
