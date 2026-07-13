import Foundation

public struct ElectricalTopologyExtractionProfile: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public struct NetRule: Sendable, Hashable, Codable {
        public var netID: String
        public var kind: ElectricalTopology.NetKind
        public var nominalVoltageV: Double?
        public var domainID: String?

        public init(
            netID: String,
            kind: ElectricalTopology.NetKind,
            nominalVoltageV: Double? = nil,
            domainID: String? = nil
        ) {
            self.netID = netID
            self.kind = kind
            self.nominalVoltageV = nominalVoltageV
            self.domainID = domainID
        }
    }

    public struct SourceRule: Sendable, Hashable, Codable {
        public var id: String
        public var netID: String
        public var nodeID: String
        public var voltageV: Double
        public var maxCurrentA: Double

        public init(id: String, netID: String, nodeID: String, voltageV: Double, maxCurrentA: Double) {
            self.id = id
            self.netID = netID
            self.nodeID = nodeID
            self.voltageV = voltageV
            self.maxCurrentA = maxCurrentA
        }
    }

    public struct LoadRule: Sendable, Hashable, Codable {
        public var id: String
        public var deviceType: String?
        public var netID: String
        public var staticCurrentA: Double
        public var dynamicCurrentA: Double
        public var activityFactor: Double
        public var domainID: String?

        public init(
            id: String,
            deviceType: String? = nil,
            netID: String,
            staticCurrentA: Double,
            dynamicCurrentA: Double = 0,
            activityFactor: Double = 1,
            domainID: String? = nil
        ) {
            self.id = id
            self.deviceType = deviceType
            self.netID = netID
            self.staticCurrentA = staticCurrentA
            self.dynamicCurrentA = dynamicCurrentA
            self.activityFactor = activityFactor
            self.domainID = domainID
        }
    }

    public struct LayerRule: Sendable, Hashable, Codable {
        public var layer: Int
        public var widthMicron: Double
        public var thicknessMicron: Double
        public var resistanceOhmPerMicron: Double

        public init(layer: Int, widthMicron: Double, thicknessMicron: Double, resistanceOhmPerMicron: Double) {
            self.layer = layer
            self.widthMicron = widthMicron
            self.thicknessMicron = thicknessMicron
            self.resistanceOhmPerMicron = resistanceOhmPerMicron
        }
    }

    public struct ViaRule: Sendable, Hashable, Codable {
        public var resistanceOhm: Double
        public var cutAreaSquareMicron: Double
        public var count: Int

        public init(resistanceOhm: Double, cutAreaSquareMicron: Double, count: Int = 1) {
            self.resistanceOhm = resistanceOhm
            self.cutAreaSquareMicron = cutAreaSquareMicron
            self.count = count
        }
    }

    public struct DeviceRule: Sendable, Hashable, Codable {
        public var master: String
        public var model: String
        public var domainID: String?
        public var maxTerminalVoltageV: Double?
        public var isDriver: Bool
        public var wellID: String?

        public init(
            master: String,
            model: String,
            domainID: String? = nil,
            maxTerminalVoltageV: Double? = nil,
            isDriver: Bool = false,
            wellID: String? = nil
        ) {
            self.master = master
            self.model = model
            self.domainID = domainID
            self.maxTerminalVoltageV = maxTerminalVoltageV
            self.isDriver = isDriver
            self.wellID = wellID
        }
    }

    public var schemaVersion: Int
    public var connectivityToleranceMicron: Double
    public var netRules: [NetRule]
    public var sourceRules: [SourceRule]
    public var loadRules: [LoadRule]
    public var layerRules: [LayerRule]
    public var viaRule: ViaRule
    public var deviceRules: [DeviceRule]
    public var domains: [ElectricalTopology.Domain]
    public var activityVectors: [ElectricalTopology.ActivityVector]
    public var esdClamps: [ElectricalTopology.ESDClamp]
    public var wells: [ElectricalTopology.Well]
    public var substrateContacts: [ElectricalTopology.SubstrateContact]
    public var agingModels: [ElectricalTopology.AgingModel]
    public var rules: ElectricalTopology.RuleSet

    public init(
        connectivityToleranceMicron: Double = 0.5,
        netRules: [NetRule] = [],
        sourceRules: [SourceRule] = [],
        loadRules: [LoadRule] = [],
        layerRules: [LayerRule] = [],
        viaRule: ViaRule = ViaRule(resistanceOhm: 0.01, cutAreaSquareMicron: 1),
        deviceRules: [DeviceRule] = [],
        domains: [ElectricalTopology.Domain] = [],
        activityVectors: [ElectricalTopology.ActivityVector] = [],
        esdClamps: [ElectricalTopology.ESDClamp] = [],
        wells: [ElectricalTopology.Well] = [],
        substrateContacts: [ElectricalTopology.SubstrateContact] = [],
        agingModels: [ElectricalTopology.AgingModel] = [],
        rules: ElectricalTopology.RuleSet,
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.connectivityToleranceMicron = connectivityToleranceMicron
        self.netRules = netRules
        self.sourceRules = sourceRules
        self.loadRules = loadRules
        self.layerRules = layerRules
        self.viaRule = viaRule
        self.deviceRules = deviceRules
        self.domains = domains
        self.activityVectors = activityVectors
        self.esdClamps = esdClamps
        self.wells = wells
        self.substrateContacts = substrateContacts
        self.agingModels = agingModels
        self.rules = rules
    }
}
