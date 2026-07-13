import Foundation
import ElectricalSignoffCore

public enum ElectricalSignoffEngineAPI {
    public static let contractVersion = 1
    public static let supportedAxes = ElectricalSignoffAnalysisAxis.allCases.filter { $0 != .aggregate }
    public static let capabilitySnapshot = ElectricalSignoffCapabilitySnapshot()
}
