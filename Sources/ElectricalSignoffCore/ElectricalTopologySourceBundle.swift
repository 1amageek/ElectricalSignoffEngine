import Foundation
import LogicIR
import PowerIntent
import PDKCore
import PhysicalDesignCore
import PEXCore
import XcircuitePackage

public struct ElectricalTopologySourceBundle: Sendable, Hashable {
    public var request: ElectricalSignoffRequest
    public var design: LogicDesignSnapshot
    public var physicalDesign: PhysicalDesignSnapshot
    public var powerIntent: PowerIntentDesign?
    public var pdk: PDKManifest
    public var parasitic: ParasiticIR?
    public var profile: ElectricalTopologyExtractionProfile
    public var processRules: ElectricalProcessRuleSet?
    public var sourceReferences: [XcircuiteFileReference]

    public init(
        request: ElectricalSignoffRequest,
        design: LogicDesignSnapshot,
        physicalDesign: PhysicalDesignSnapshot,
        powerIntent: PowerIntentDesign?,
        pdk: PDKManifest,
        parasitic: ParasiticIR?,
        profile: ElectricalTopologyExtractionProfile,
        processRules: ElectricalProcessRuleSet? = nil,
        sourceReferences: [XcircuiteFileReference]
    ) {
        self.request = request
        self.design = design
        self.physicalDesign = physicalDesign
        self.powerIntent = powerIntent
        self.pdk = pdk
        self.parasitic = parasitic
        self.profile = profile
        self.processRules = processRules
        self.sourceReferences = sourceReferences
    }
}
