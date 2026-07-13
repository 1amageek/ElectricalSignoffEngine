import Foundation

public struct ElectricalTopologyValidator: Sendable {
    public init() {}

    public func validate(_ topology: ElectricalTopology) throws {
        guard topology.schemaVersion == ElectricalTopology.currentSchemaVersion else {
            throw ElectricalSignoffError.schemaVersionUnsupported(topology.schemaVersion)
        }
        guard nonEmpty(topology.designDigest), nonEmpty(topology.pdkDigest), nonEmpty(topology.layoutDigest) else {
            throw ElectricalSignoffError.malformedTopology("design, PDK and layout digests are required")
        }
        guard nonEmpty(topology.topCell) else {
            throw ElectricalSignoffError.malformedTopology("topCell is required")
        }
        guard !topology.nets.isEmpty else {
            throw ElectricalSignoffError.insufficientTopology("at least one electrical net is required")
        }
        let netIDs = Set(topology.nets.map(\.id))
        guard netIDs.count == topology.nets.count else {
            throw ElectricalSignoffError.malformedTopology("net identifiers must be unique")
        }
        guard topology.nets.allSatisfy({ nonEmpty($0.id) }) else {
            throw ElectricalSignoffError.malformedTopology("net identifiers are required")
        }
        let domainIDs = Set(topology.domains.map(\.id))
        guard domainIDs.count == topology.domains.count,
              topology.domains.allSatisfy({ nonEmpty($0.id) }) else {
            throw ElectricalSignoffError.malformedTopology("domain identifiers must be unique and non-empty")
        }
        let nodeIDs = Set(topology.nodes.map(\.id))
        guard nodeIDs.count == topology.nodes.count else {
            throw ElectricalSignoffError.malformedTopology("node identifiers must be unique")
        }
        for node in topology.nodes {
            guard nonEmpty(node.id), nonEmpty(node.netID), netIDs.contains(node.netID) else {
                throw ElectricalSignoffError.malformedTopology("node \(node.id) references an unknown net")
            }
            guard node.xMicron.map({ $0.isFinite }) ?? true,
                  node.yMicron.map({ $0.isFinite }) ?? true else {
                throw ElectricalSignoffError.malformedTopology("node \(node.id) has a non-finite coordinate")
            }
        }
        for device in topology.devices {
            guard nonEmpty(device.id), nonEmpty(device.model), !device.terminals.isEmpty else {
                throw ElectricalSignoffError.malformedTopology("device \(device.id) is missing identity, model or terminals")
            }
            for netID in device.terminals.values where !netIDs.contains(netID) {
                throw ElectricalSignoffError.malformedTopology("device \(device.id) references unknown net \(netID)")
            }
            guard device.domainID.map({ domainIDs.contains($0) }) ?? true,
                  device.maxTerminalVoltageV.map({ $0.isFinite && $0 >= 0 }) ?? true,
                  device.widthMicron.map({ $0.isFinite && $0 > 0 }) ?? true,
                  device.lengthMicron.map({ $0.isFinite && $0 > 0 }) ?? true else {
                throw ElectricalSignoffError.malformedTopology("device \(device.id) has invalid domain or electrical geometry")
            }
        }
        let deviceIDs = Set(topology.devices.map(\.id))
        guard deviceIDs.count == topology.devices.count else {
            throw ElectricalSignoffError.malformedTopology("device identifiers must be unique")
        }
        let segmentIDs = Set(topology.segments.map(\.id))
        guard segmentIDs.count == topology.segments.count else {
            throw ElectricalSignoffError.malformedTopology("segment identifiers must be unique")
        }
        guard topology.segments.allSatisfy({ nonEmpty($0.id) }) else {
            throw ElectricalSignoffError.malformedTopology("segment identifiers are required")
        }
        let viaIDs = Set(topology.vias.map(\.id))
        guard viaIDs.count == topology.vias.count,
              topology.vias.allSatisfy({ nonEmpty($0.id) }) else {
            throw ElectricalSignoffError.malformedTopology("via identifiers must be unique and non-empty")
        }
        let sourceIDs = Set(topology.sources.map(\.id))
        guard sourceIDs.count == topology.sources.count,
              topology.sources.allSatisfy({ nonEmpty($0.id) }) else {
            throw ElectricalSignoffError.malformedTopology("source identifiers must be unique and non-empty")
        }
        let loadIDs = Set(topology.loads.map(\.id))
        guard loadIDs.count == topology.loads.count,
              topology.loads.allSatisfy({ nonEmpty($0.id) }) else {
            throw ElectricalSignoffError.malformedTopology("load identifiers must be unique and non-empty")
        }
        let nodeByID = Dictionary(uniqueKeysWithValues: topology.nodes.map { ($0.id, $0) })
        for segment in topology.segments {
            guard netIDs.contains(segment.netID), nodeIDs.contains(segment.fromNodeID), nodeIDs.contains(segment.toNodeID) else {
                throw ElectricalSignoffError.malformedTopology("segment \(segment.id) references an unknown net or node")
            }
            guard nodeByID[segment.fromNodeID]?.netID == segment.netID,
                  nodeByID[segment.toNodeID]?.netID == segment.netID else {
                throw ElectricalSignoffError.malformedTopology("segment \(segment.id) crosses declared electrical nets")
            }
            guard nonEmpty(segment.layer),
                  segment.resistanceOhm.isFinite, segment.resistanceOhm > 0,
                  segment.widthMicron.isFinite, segment.widthMicron > 0,
                  segment.thicknessMicron.isFinite, segment.thicknessMicron > 0 else {
                throw ElectricalSignoffError.malformedTopology("segment \(segment.id) has non-positive resistance or geometry")
            }
            guard segment.currentA.isFinite, segment.currentA >= 0,
                  segment.currentLimitA.map({ $0.isFinite && $0 >= 0 }) ?? true else {
                throw ElectricalSignoffError.malformedTopology("segment \(segment.id) has a negative current or current limit")
            }
        }
        for via in topology.vias {
            guard netIDs.contains(via.netID), nodeIDs.contains(via.nodeID) else {
                throw ElectricalSignoffError.malformedTopology("via \(via.id) references an unknown net or node")
            }
            guard nodeByID[via.nodeID]?.netID == via.netID else {
                throw ElectricalSignoffError.malformedTopology("via \(via.id) crosses a declared electrical net")
            }
            guard via.resistanceOhm.isFinite, via.resistanceOhm > 0,
                  via.cutAreaSquareMicron.isFinite, via.cutAreaSquareMicron > 0,
                  via.count > 0 else {
                throw ElectricalSignoffError.malformedTopology("via \(via.id) has invalid resistance, area or count")
            }
            guard via.currentA.isFinite, via.currentA >= 0,
                  via.currentLimitA.map({ $0.isFinite && $0 >= 0 }) ?? true else {
                throw ElectricalSignoffError.malformedTopology("via \(via.id) has a negative current or current limit")
            }
        }
        for source in topology.sources {
            guard nonEmpty(source.id),
                  netIDs.contains(source.netID), nodeIDs.contains(source.nodeID),
                  source.voltageV.isFinite, source.maxCurrentA.isFinite, source.maxCurrentA >= 0 else {
                throw ElectricalSignoffError.malformedTopology("source \(source.id) references invalid topology or current")
            }
            guard nodeByID[source.nodeID]?.netID == source.netID else {
                throw ElectricalSignoffError.malformedTopology("source \(source.id) crosses a declared electrical net")
            }
        }
        for load in topology.loads {
            guard nonEmpty(load.id),
                  netIDs.contains(load.netID), nodeIDs.contains(load.nodeID),
                  load.staticCurrentA.isFinite, load.staticCurrentA >= 0,
                  load.dynamicCurrentA.isFinite, load.dynamicCurrentA >= 0 else {
                throw ElectricalSignoffError.malformedTopology("load \(load.id) references invalid topology or current")
            }
            guard nodeByID[load.nodeID]?.netID == load.netID else {
                throw ElectricalSignoffError.malformedTopology("load \(load.id) crosses a declared electrical net")
            }
            guard load.activityFactor.isFinite, load.activityFactor >= 0, load.activityFactor <= 1 else {
                throw ElectricalSignoffError.malformedTopology("load \(load.id) activityFactor must be within [0, 1]")
            }
            guard load.domainID.map({ domainIDs.contains($0) }) ?? true else {
                throw ElectricalSignoffError.malformedTopology("load \(load.id) references an unknown domain")
            }
        }
        for domain in topology.domains {
            guard domain.nominalVoltageV.isFinite,
                  domain.maximumVoltageV.isFinite,
                  domain.minimumVoltageV.isFinite,
                  domain.maximumVoltageV >= domain.minimumVoltageV else {
                throw ElectricalSignoffError.malformedTopology("domain \(domain.id) has invalid voltage limits")
            }
            guard domain.nominalVoltageV >= domain.minimumVoltageV,
                  domain.nominalVoltageV <= domain.maximumVoltageV else {
                throw ElectricalSignoffError.malformedTopology("domain \(domain.id) nominal voltage is outside its declared limits")
            }
            guard domain.requiresPowerDomainIDs.allSatisfy({ domainIDs.contains($0) }) else {
                throw ElectricalSignoffError.malformedTopology("domain \(domain.id) references an unknown prerequisite domain")
            }
        }
        for net in topology.nets {
            guard net.nominalVoltageV.map({ $0.isFinite }) ?? true,
                  net.minVoltageV.map({ $0.isFinite }) ?? true,
                  net.maxVoltageV.map({ $0.isFinite }) ?? true else {
                throw ElectricalSignoffError.malformedTopology("net \(net.id) has a non-finite voltage")
            }
            if let minimum = net.minVoltageV, let maximum = net.maxVoltageV, maximum < minimum {
                throw ElectricalSignoffError.malformedTopology("net \(net.id) has inverted voltage limits")
            }
            if let nominal = net.nominalVoltageV {
                guard net.minVoltageV.map({ nominal >= $0 }) ?? true,
                      net.maxVoltageV.map({ nominal <= $0 }) ?? true else {
                    throw ElectricalSignoffError.malformedTopology("net \(net.id) nominal voltage is outside its declared limits")
                }
            }
            if let domainID = net.domainID, !domainIDs.contains(domainID) {
                throw ElectricalSignoffError.malformedTopology("net \(net.id) references unknown domain \(domainID)")
            }
            guard net.requiresPowerDomainIDs.allSatisfy({ domainIDs.contains($0) }) else {
                throw ElectricalSignoffError.malformedTopology("net \(net.id) references an unknown prerequisite domain")
            }
        }
        guard validRules(topology.rules) else {
            throw ElectricalSignoffError.malformedTopology("rule limits must be non-negative and non-zero where required")
        }
        for (cornerID, rules) in topology.rulesByCorner {
            guard nonEmpty(cornerID), validRules(rules) else {
                throw ElectricalSignoffError.malformedTopology("corner rule limits are invalid")
            }
        }
        let clampIDs = Set(topology.esdClamps.map(\.id))
        guard clampIDs.count == topology.esdClamps.count,
              topology.esdClamps.allSatisfy({ nonEmpty($0.id) }) else {
            throw ElectricalSignoffError.malformedTopology("ESD clamp identifiers must be unique and non-empty")
        }
        for clamp in topology.esdClamps {
            guard domainIDs.contains(clamp.domainID),
                  netIDs.contains(clamp.protectedNetID),
                  netIDs.contains(clamp.groundNetID),
                  clamp.triggerVoltageV.isFinite, clamp.triggerVoltageV >= 0,
                  clamp.maximumCurrentA.isFinite, clamp.maximumCurrentA >= 0,
                  clamp.resistanceOhm.isFinite, clamp.resistanceOhm >= 0 else {
                throw ElectricalSignoffError.malformedTopology("ESD clamp \(clamp.id) has negative electrical limits")
            }
        }
        let activityIDs = Set(topology.activityVectors.map(\.id))
        guard activityIDs.count == topology.activityVectors.count,
              topology.activityVectors.allSatisfy({
                  nonEmpty($0.id) && $0.weight.isFinite && $0.weight >= 0 && $0.peakScale.isFinite && $0.peakScale >= 0
              }) else {
            throw ElectricalSignoffError.malformedTopology("activity vectors must have unique IDs and finite non-negative values")
        }
        let wellIDs = Set(topology.wells.map(\.id))
        guard wellIDs.count == topology.wells.count,
              topology.wells.allSatisfy({ nonEmpty($0.id) && nonEmpty($0.type) }) else {
            throw ElectricalSignoffError.malformedTopology("well identifiers and types must be unique and non-empty")
        }
        for well in topology.wells {
            guard domainIDs.contains(well.domainID),
                  well.areaSquareMicron.isFinite, well.areaSquareMicron > 0,
                  well.spacingToOppositeWellMicron.isFinite, well.spacingToOppositeWellMicron >= 0,
                  well.requiredSpacingMicron.isFinite, well.requiredSpacingMicron >= 0 else {
                throw ElectricalSignoffError.malformedTopology("well \(well.id) has invalid geometry or domain")
            }
        }
        let contactIDs = Set(topology.substrateContacts.map(\.id))
        guard contactIDs.count == topology.substrateContacts.count,
              topology.substrateContacts.allSatisfy({ nonEmpty($0.id) }) else {
            throw ElectricalSignoffError.malformedTopology("substrate contact identifiers must be unique and non-empty")
        }
        for well in topology.wells where !well.substrateContactIDs.allSatisfy({ contactIDs.contains($0) }) {
            throw ElectricalSignoffError.malformedTopology("well \(well.id) references an unknown substrate contact")
        }
        for contact in topology.substrateContacts {
            guard wellIDs.contains(contact.wellID), netIDs.contains(contact.netID),
                  contact.areaSquareMicron.isFinite, contact.areaSquareMicron > 0 else {
                throw ElectricalSignoffError.malformedTopology("substrate contact \(contact.id) has invalid references or area")
            }
        }
        let agingDeviceIDs = topology.agingModels.map(\.deviceID)
        guard Set(agingDeviceIDs).count == agingDeviceIDs.count else {
            throw ElectricalSignoffError.malformedTopology("aging models must contain at most one model per device")
        }
        for model in topology.agingModels {
            guard deviceIDs.contains(model.deviceID),
                  model.nbtiCoefficient.isFinite, model.nbtiCoefficient >= 0,
                  model.hciCoefficient.isFinite, model.hciCoefficient >= 0,
                  model.tddbCoefficient.isFinite, model.tddbCoefficient >= 0,
                  model.dutyCycle.isFinite, model.dutyCycle >= 0,
                  model.dutyCycle <= 1,
                  model.lifetimeHoursAtReference.isFinite,
                  model.lifetimeHoursAtReference > 0,
                  model.referenceTemperatureC.isFinite,
                  model.referenceVoltageV.isFinite,
                  model.referenceVoltageV > 0 else {
                throw ElectricalSignoffError.malformedTopology("aging model \(model.deviceID) has invalid coefficients or reference values")
            }
        }
    }

    private func validRules(_ rules: ElectricalTopology.RuleSet) -> Bool {
        rules.maximumIRDropV.isFinite
            && rules.maximumIRDropV > 0
            && rules.maximumCurrentDensityAperSquareMicron.isFinite
            && rules.maximumCurrentDensityAperSquareMicron > 0
            && rules.maximumViaCurrentDensityAperSquareMicron.isFinite
            && rules.maximumViaCurrentDensityAperSquareMicron > 0
            && rules.minimumESDResistanceOhm.isFinite
            && rules.minimumESDResistanceOhm >= 0
    }

    private func nonEmpty(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
