import Foundation

public struct ElectricalTopology: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public struct Node: Sendable, Hashable, Codable {
        public var id: String
        public var netID: String
        public var xMicron: Double?
        public var yMicron: Double?

        public init(id: String, netID: String, xMicron: Double? = nil, yMicron: Double? = nil) {
            self.id = id
            self.netID = netID
            self.xMicron = xMicron
            self.yMicron = yMicron
        }
    }

    public enum NetKind: String, Sendable, Hashable, Codable {
        case power
        case ground
        case signal
        case clock
        case analog
        case substrate
        case unknown
    }

    public struct Net: Sendable, Hashable, Codable {
        public var id: String
        public var kind: NetKind
        public var nominalVoltageV: Double?
        public var domainID: String?
        public var maxVoltageV: Double?
        public var minVoltageV: Double?
        public var requiresPowerDomainIDs: [String]

        public init(
            id: String,
            kind: NetKind = .unknown,
            nominalVoltageV: Double? = nil,
            domainID: String? = nil,
            maxVoltageV: Double? = nil,
            minVoltageV: Double? = nil,
            requiresPowerDomainIDs: [String] = []
        ) {
            self.id = id
            self.kind = kind
            self.nominalVoltageV = nominalVoltageV
            self.domainID = domainID
            self.maxVoltageV = maxVoltageV
            self.minVoltageV = minVoltageV
            self.requiresPowerDomainIDs = requiresPowerDomainIDs
        }
    }

    public struct Device: Sendable, Hashable, Codable {
        public var id: String
        public var model: String
        public var terminals: [String: String]
        public var domainID: String?
        public var maxTerminalVoltageV: Double?
        public var isDriver: Bool
        public var wellID: String?
        public var widthMicron: Double?
        public var lengthMicron: Double?

        public init(
            id: String,
            model: String,
            terminals: [String: String],
            domainID: String? = nil,
            maxTerminalVoltageV: Double? = nil,
            isDriver: Bool = false,
            wellID: String? = nil,
            widthMicron: Double? = nil,
            lengthMicron: Double? = nil
        ) {
            self.id = id
            self.model = model
            self.terminals = terminals
            self.domainID = domainID
            self.maxTerminalVoltageV = maxTerminalVoltageV
            self.isDriver = isDriver
            self.wellID = wellID
            self.widthMicron = widthMicron
            self.lengthMicron = lengthMicron
        }
    }

    public struct Segment: Sendable, Hashable, Codable {
        public var id: String
        public var netID: String
        public var fromNodeID: String
        public var toNodeID: String
        public var resistanceOhm: Double
        public var currentA: Double
        public var widthMicron: Double
        public var thicknessMicron: Double
        public var currentLimitA: Double?
        public var layer: String

        public init(
            id: String,
            netID: String,
            fromNodeID: String,
            toNodeID: String,
            resistanceOhm: Double,
            currentA: Double = 0,
            widthMicron: Double,
            thicknessMicron: Double,
            currentLimitA: Double? = nil,
            layer: String
        ) {
            self.id = id
            self.netID = netID
            self.fromNodeID = fromNodeID
            self.toNodeID = toNodeID
            self.resistanceOhm = resistanceOhm
            self.currentA = currentA
            self.widthMicron = widthMicron
            self.thicknessMicron = thicknessMicron
            self.currentLimitA = currentLimitA
            self.layer = layer
        }
    }

    public struct Via: Sendable, Hashable, Codable {
        public var id: String
        public var netID: String
        public var nodeID: String
        public var resistanceOhm: Double
        public var currentA: Double
        public var cutAreaSquareMicron: Double
        public var currentLimitA: Double?
        public var count: Int

        public init(
            id: String,
            netID: String,
            nodeID: String,
            resistanceOhm: Double,
            currentA: Double = 0,
            cutAreaSquareMicron: Double,
            currentLimitA: Double? = nil,
            count: Int = 1
        ) {
            self.id = id
            self.netID = netID
            self.nodeID = nodeID
            self.resistanceOhm = resistanceOhm
            self.currentA = currentA
            self.cutAreaSquareMicron = cutAreaSquareMicron
            self.currentLimitA = currentLimitA
            self.count = count
        }
    }

    public struct Source: Sendable, Hashable, Codable {
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

    public struct Load: Sendable, Hashable, Codable {
        public var id: String
        public var netID: String
        public var nodeID: String
        public var staticCurrentA: Double
        public var dynamicCurrentA: Double
        public var activityFactor: Double
        public var domainID: String?

        public init(
            id: String,
            netID: String,
            nodeID: String,
            staticCurrentA: Double,
            dynamicCurrentA: Double = 0,
            activityFactor: Double = 1,
            domainID: String? = nil
        ) {
            self.id = id
            self.netID = netID
            self.nodeID = nodeID
            self.staticCurrentA = staticCurrentA
            self.dynamicCurrentA = dynamicCurrentA
            self.activityFactor = activityFactor
            self.domainID = domainID
        }
    }

    public struct ActivityVector: Sendable, Hashable, Codable {
        public var id: String
        public var weight: Double
        public var peakScale: Double

        public init(id: String, weight: Double, peakScale: Double) {
            self.id = id
            self.weight = weight
            self.peakScale = peakScale
        }
    }

    public struct Domain: Sendable, Hashable, Codable {
        public var id: String
        public var nominalVoltageV: Double
        public var maximumVoltageV: Double
        public var minimumVoltageV: Double
        public var requiresPowerDomainIDs: [String]

        public init(
            id: String,
            nominalVoltageV: Double,
            maximumVoltageV: Double,
            minimumVoltageV: Double,
            requiresPowerDomainIDs: [String] = []
        ) {
            self.id = id
            self.nominalVoltageV = nominalVoltageV
            self.maximumVoltageV = maximumVoltageV
            self.minimumVoltageV = minimumVoltageV
            self.requiresPowerDomainIDs = requiresPowerDomainIDs
        }
    }

    public struct ESDClamp: Sendable, Hashable, Codable {
        public var id: String
        public var domainID: String
        public var protectedNetID: String
        public var groundNetID: String
        public var triggerVoltageV: Double
        public var maximumCurrentA: Double
        public var resistanceOhm: Double

        public init(
            id: String,
            domainID: String,
            protectedNetID: String,
            groundNetID: String,
            triggerVoltageV: Double,
            maximumCurrentA: Double,
            resistanceOhm: Double
        ) {
            self.id = id
            self.domainID = domainID
            self.protectedNetID = protectedNetID
            self.groundNetID = groundNetID
            self.triggerVoltageV = triggerVoltageV
            self.maximumCurrentA = maximumCurrentA
            self.resistanceOhm = resistanceOhm
        }
    }

    public struct Well: Sendable, Hashable, Codable {
        public var id: String
        public var domainID: String
        public var type: String
        public var areaSquareMicron: Double
        public var spacingToOppositeWellMicron: Double
        public var requiredSpacingMicron: Double
        public var substrateContactIDs: [String]

        public init(
            id: String,
            domainID: String,
            type: String,
            areaSquareMicron: Double,
            spacingToOppositeWellMicron: Double,
            requiredSpacingMicron: Double,
            substrateContactIDs: [String] = []
        ) {
            self.id = id
            self.domainID = domainID
            self.type = type
            self.areaSquareMicron = areaSquareMicron
            self.spacingToOppositeWellMicron = spacingToOppositeWellMicron
            self.requiredSpacingMicron = requiredSpacingMicron
            self.substrateContactIDs = substrateContactIDs
        }
    }

    public struct SubstrateContact: Sendable, Hashable, Codable {
        public var id: String
        public var wellID: String
        public var netID: String
        public var areaSquareMicron: Double

        public init(id: String, wellID: String, netID: String, areaSquareMicron: Double) {
            self.id = id
            self.wellID = wellID
            self.netID = netID
            self.areaSquareMicron = areaSquareMicron
        }
    }

    public struct AgingModel: Sendable, Hashable, Codable {
        public var deviceID: String
        public var nbtiCoefficient: Double
        public var hciCoefficient: Double
        public var tddbCoefficient: Double
        public var dutyCycle: Double
        public var lifetimeHoursAtReference: Double
        public var referenceTemperatureC: Double
        public var referenceVoltageV: Double

        public init(
            deviceID: String,
            nbtiCoefficient: Double,
            hciCoefficient: Double,
            tddbCoefficient: Double,
            dutyCycle: Double,
            lifetimeHoursAtReference: Double,
            referenceTemperatureC: Double,
            referenceVoltageV: Double
        ) {
            self.deviceID = deviceID
            self.nbtiCoefficient = nbtiCoefficient
            self.hciCoefficient = hciCoefficient
            self.tddbCoefficient = tddbCoefficient
            self.dutyCycle = dutyCycle
            self.lifetimeHoursAtReference = lifetimeHoursAtReference
            self.referenceTemperatureC = referenceTemperatureC
            self.referenceVoltageV = referenceVoltageV
        }
    }

    public struct RuleSet: Sendable, Hashable, Codable {
        public var maximumIRDropV: Double
        public var maximumCurrentDensityAperSquareMicron: Double
        public var maximumViaCurrentDensityAperSquareMicron: Double
        public var minimumESDResistanceOhm: Double

        public init(
            maximumIRDropV: Double,
            maximumCurrentDensityAperSquareMicron: Double,
            maximumViaCurrentDensityAperSquareMicron: Double,
            minimumESDResistanceOhm: Double
        ) {
            self.maximumIRDropV = maximumIRDropV
            self.maximumCurrentDensityAperSquareMicron = maximumCurrentDensityAperSquareMicron
            self.maximumViaCurrentDensityAperSquareMicron = maximumViaCurrentDensityAperSquareMicron
            self.minimumESDResistanceOhm = minimumESDResistanceOhm
        }
    }

    public var schemaVersion: Int
    public var designDigest: String
    public var pdkDigest: String
    public var layoutDigest: String
    public var topCell: String
    public var parasiticDigest: String?
    public var powerIntentDigest: String?
    public var nodes: [Node]
    public var nets: [Net]
    public var devices: [Device]
    public var segments: [Segment]
    public var vias: [Via]
    public var sources: [Source]
    public var loads: [Load]
    public var activityVectors: [ActivityVector]
    public var domains: [Domain]
    public var esdClamps: [ESDClamp]
    public var wells: [Well]
    public var substrateContacts: [SubstrateContact]
    public var agingModels: [AgingModel]
    public var rules: RuleSet
    public var rulesByCorner: [String: RuleSet]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        designDigest: String,
        pdkDigest: String,
        layoutDigest: String,
        topCell: String,
        parasiticDigest: String? = nil,
        nodes: [Node],
        nets: [Net],
        devices: [Device] = [],
        segments: [Segment],
        vias: [Via] = [],
        sources: [Source],
        loads: [Load],
        activityVectors: [ActivityVector] = [],
        domains: [Domain] = [],
        esdClamps: [ESDClamp] = [],
        wells: [Well] = [],
        substrateContacts: [SubstrateContact] = [],
        agingModels: [AgingModel] = [],
        rules: RuleSet,
        powerIntentDigest: String? = nil,
        rulesByCorner: [String: RuleSet] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.designDigest = designDigest
        self.pdkDigest = pdkDigest
        self.layoutDigest = layoutDigest
        self.topCell = topCell
        self.parasiticDigest = parasiticDigest
        self.powerIntentDigest = powerIntentDigest
        self.nodes = nodes
        self.nets = nets
        self.devices = devices
        self.segments = segments
        self.vias = vias
        self.sources = sources
        self.loads = loads
        self.activityVectors = activityVectors
        self.domains = domains
        self.esdClamps = esdClamps
        self.wells = wells
        self.substrateContacts = substrateContacts
        self.agingModels = agingModels
        self.rules = rules
        self.rulesByCorner = rulesByCorner
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case designDigest
        case pdkDigest
        case layoutDigest
        case topCell
        case parasiticDigest
        case powerIntentDigest
        case nodes
        case nets
        case devices
        case segments
        case vias
        case sources
        case loads
        case activityVectors
        case domains
        case esdClamps
        case wells
        case substrateContacts
        case agingModels
        case rules
        case rulesByCorner
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
        designDigest = try container.decode(String.self, forKey: .designDigest)
        pdkDigest = try container.decode(String.self, forKey: .pdkDigest)
        layoutDigest = try container.decode(String.self, forKey: .layoutDigest)
        topCell = try container.decode(String.self, forKey: .topCell)
        parasiticDigest = try container.decodeIfPresent(String.self, forKey: .parasiticDigest)
        powerIntentDigest = try container.decodeIfPresent(String.self, forKey: .powerIntentDigest)
        nodes = try container.decodeIfPresent([Node].self, forKey: .nodes) ?? []
        nets = try container.decodeIfPresent([Net].self, forKey: .nets) ?? []
        devices = try container.decodeIfPresent([Device].self, forKey: .devices) ?? []
        segments = try container.decodeIfPresent([Segment].self, forKey: .segments) ?? []
        vias = try container.decodeIfPresent([Via].self, forKey: .vias) ?? []
        sources = try container.decodeIfPresent([Source].self, forKey: .sources) ?? []
        loads = try container.decodeIfPresent([Load].self, forKey: .loads) ?? []
        activityVectors = try container.decodeIfPresent([ActivityVector].self, forKey: .activityVectors) ?? []
        domains = try container.decodeIfPresent([Domain].self, forKey: .domains) ?? []
        esdClamps = try container.decodeIfPresent([ESDClamp].self, forKey: .esdClamps) ?? []
        wells = try container.decodeIfPresent([Well].self, forKey: .wells) ?? []
        substrateContacts = try container.decodeIfPresent([SubstrateContact].self, forKey: .substrateContacts) ?? []
        agingModels = try container.decodeIfPresent([AgingModel].self, forKey: .agingModels) ?? []
        rules = try container.decode(RuleSet.self, forKey: .rules)
        rulesByCorner = try container.decodeIfPresent([String: RuleSet].self, forKey: .rulesByCorner) ?? [:]
    }

    public func rules(for condition: ElectricalOperatingCondition) -> RuleSet {
        rulesByCorner[condition.pdkCornerID] ?? rules
    }
}
