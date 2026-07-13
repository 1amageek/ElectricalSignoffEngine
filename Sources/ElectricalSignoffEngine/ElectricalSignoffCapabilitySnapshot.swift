import Foundation
import ElectricalSignoffCore

public struct ElectricalSignoffCapabilitySnapshot: Sendable, Hashable, Codable {
    public var schemaVersion: Int
    public var engineID: String
    public var supportedAxes: [ElectricalSignoffAnalysisAxis]
    public var nativeTopologyFormats: [String]
    public var externalAdapterBoundary: String
    public var qualificationStatus: String
    public var limitations: [String]

    public init(
        schemaVersion: Int = 1,
        engineID: String = "ElectricalSignoffEngine",
        supportedAxes: [ElectricalSignoffAnalysisAxis] = ElectricalSignoffEngineAPI.supportedAxes,
        nativeTopologyFormats: [String] = ["JSON"],
        externalAdapterBoundary: String = "ExternalElectricalSignoffRunning",
        qualificationStatus: String = "not-qualified",
        limitations: [String] = [
            "Native analysis requires a verified extracted electrical topology or a verified JSON source bundle.",
            "GDSII and OASIS bytes are not interpreted as electrical semantics by this package.",
            "Multiple operating conditions are evaluated sequentially and retained; release promotion still requires qualified process rules.",
            "Foundry/process qualification requires an independent process-scoped oracle."
        ]
    ) {
        self.schemaVersion = schemaVersion
        self.engineID = engineID
        self.supportedAxes = supportedAxes
        self.nativeTopologyFormats = nativeTopologyFormats
        self.externalAdapterBoundary = externalAdapterBoundary
        self.qualificationStatus = qualificationStatus
        self.limitations = limitations
    }
}
