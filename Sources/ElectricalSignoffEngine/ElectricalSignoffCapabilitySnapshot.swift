import Foundation
import ElectricalSignoffCore

public struct ElectricalSignoffCapabilitySnapshot: Sendable, Hashable, Codable {
    public var schemaVersion: Int
    public var engineID: String
    public var supportedAxes: [ElectricalSignoffAnalysisAxis]
    public var nativeTopologyFormats: [String]
    public var externalAdapterBoundary: String
    public var validationScope: String
    public var limitations: [String]

    public init(
        schemaVersion: Int = 1,
        engineID: String = "ElectricalSignoffEngine",
        supportedAxes: [ElectricalSignoffAnalysisAxis],
        nativeTopologyFormats: [String] = ["JSON"],
        externalAdapterBoundary: String = "ExternalElectricalSignoffRunning",
        validationScope: String = "native-fixture-corpus",
        limitations: [String] = [
            "Native analysis requires a verified extracted electrical topology or a verified JSON source bundle.",
            "GDSII and OASIS bytes are not interpreted as electrical semantics by this package.",
            "Multiple operating conditions are evaluated sequentially and retained as raw results.",
            "Tool trust is evaluated by ToolQualification from retained corpus and oracle observations."
        ]
    ) {
        self.schemaVersion = schemaVersion
        self.engineID = engineID
        self.supportedAxes = supportedAxes
        self.nativeTopologyFormats = nativeTopologyFormats
        self.externalAdapterBoundary = externalAdapterBoundary
        self.validationScope = validationScope
        self.limitations = limitations
    }
}
