import Foundation
import LogicIR
import PowerIntent
import PDKCore
import PhysicalDesignCore
import PEXCore

public struct NativeElectricalTopologyExtractor: ElectricalTopologyExtracting {
    private struct Point: Sendable {
        var x: Double
        var y: Double
    }

    private struct NodeBuilder: Sendable {
        var nodes: [String: ElectricalTopology.Node] = [:]
        var points: [String: Point] = [:]
        let tolerance: Double

        mutating func add(id: String, netID: String, point: Point? = nil) {
            if nodes[id] == nil {
                nodes[id] = ElectricalTopology.Node(id: id, netID: netID, xMicron: point?.x, yMicron: point?.y)
                if let point {
                    points[id] = point
                }
            }
        }

        mutating func resolve(netID: String, point: Point, fallbackID: String) -> String {
            let candidates = points.compactMap { id, candidate -> (String, Double)? in
                guard nodes[id]?.netID == netID else {
                    return nil
                }
                let distance = hypot(candidate.x - point.x, candidate.y - point.y)
                return distance <= tolerance ? (id, distance) : nil
            }
            if let nearest = candidates.min(by: { lhs, rhs in
                lhs.1 == rhs.1 ? lhs.0 < rhs.0 : lhs.1 < rhs.1
            }) {
                return nearest.0
            }
            add(id: fallbackID, netID: netID, point: point)
            return fallbackID
        }

        func nodeID(cellID: String, pinName: String, netID: String) -> String? {
            let prefix = "pin:"
            return nodes.values
                .filter { $0.netID == netID && $0.id.hasPrefix(prefix) }
                .filter { $0.id.contains(":\(cellID):\(pinName)") }
                .map(\.id)
                .sorted()
                .first
        }
    }

    public init() {}

    public func extract(_ sources: ElectricalTopologySourceBundle) throws -> ElectricalTopology {
        try validateProfile(sources.profile)
        guard !sources.pdk.processID.isEmpty, !sources.pdk.version.isEmpty else {
            throw ElectricalSignoffError.insufficientTopology("PDK identity is required for canonical extraction")
        }
        guard let processRules = sources.processRules else {
            throw ElectricalSignoffError.insufficientTopology(
                "canonical extraction requires PDK-scoped process rules"
            )
        }
        try validateProcessRules(processRules, sources: sources)
        guard let gateDesign = sources.design.gate else {
            throw ElectricalSignoffError.insufficientTopology(
                "canonical extraction requires a gate-level LogicDesignSnapshot"
            )
        }
        guard let gateModule = gateDesign.modules.first(where: { $0.name == gateDesign.topModuleName })
                ?? gateDesign.modules.first else {
            throw ElectricalSignoffError.insufficientTopology("gate-level design contains no top module")
        }

        let profile = sources.profile
        guard let defaultRules = processRules.ruleSet(for: sources.request.configuration.operatingCondition.pdkCornerID) else {
            throw ElectricalSignoffError.insufficientTopology(
                "no process rule exists for PDK corner \(sources.request.configuration.operatingCondition.pdkCornerID)"
            )
        }
        let rulesByCorner = Dictionary(uniqueKeysWithValues: processRules.cornerRules.map { ($0.cornerID, $0.rules) })
        let physical = sources.physicalDesign
        guard physical.unitsPerMicron > 0 else {
            throw ElectricalSignoffError.malformedTopology("physical design unitsPerMicron must be positive")
        }
        let unitsPerMicron = physical.unitsPerMicron
        let powerIntentSupplyNets = Set(sources.powerIntent?.supplySets.flatMap(\.supplyNets) ?? [])
        var powerIntentDomains: [String: String] = [:]
        for domain in sources.powerIntent?.domains ?? [] {
            guard let netID = domain.primarySupplyNet else {
                continue
            }
            powerIntentDomains[netID] = domain.id
        }
        let profileNetRules = Dictionary(uniqueKeysWithValues: profile.netRules.map { ($0.netID, $0) })
        let profileDeviceRules = Dictionary(uniqueKeysWithValues: profile.deviceRules.map { ($0.master, $0) })
        let profileLayerRules = Dictionary(uniqueKeysWithValues: profile.layerRules.map { ($0.layer, $0) })
        let pdkDeviceRules = sources.pdk.devices.reduce(into: [String: PDKDeviceDefinition]()) { result, device in
            result[device.deviceID] = device
            for alias in device.aliases {
                result[alias] = device
            }
        }

        let physicalNetIDs = Set(physical.nets.map(\.id))
        let gateNetIDs = Set(gateModule.nets.map(\.name))
        let profileNetIDs = Set(profile.netRules.map(\.netID))
        let netIDs = physicalNetIDs.union(gateNetIDs).union(profileNetIDs).union(powerIntentSupplyNets)
        guard !netIDs.isEmpty else {
            throw ElectricalSignoffError.insufficientTopology("logic and physical sources contain no nets")
        }

        var nodeBuilder = NodeBuilder(tolerance: profile.connectivityToleranceMicron)
        var physicalPinByCellAndName: [String: String] = [:]
        for pin in physical.pins {
            guard let netID = pin.netID else {
                continue
            }
            let nodeID = "pin:\(pin.cellID ?? "top"):\(pin.name):\(pin.id)"
            let point = Point(
                x: Double(pin.x) / Double(unitsPerMicron),
                y: Double(pin.y) / Double(unitsPerMicron)
            )
            nodeBuilder.add(id: nodeID, netID: netID, point: point)
            if let cellID = pin.cellID {
                physicalPinByCellAndName["\(cellID):\(pin.name)"] = nodeID
            }
        }

        var segments: [ElectricalTopology.Segment] = []
        let totalRouteLengthByNet = totalRouteLengths(physical: physical, unitsPerMicron: unitsPerMicron)
        let parasiticResistanceByNet = (sources.parasitic?.nets ?? []).reduce(into: [String: Double]()) { result, net in
            result[net.name.value] = net.totalResistanceOhm
        }
        for route in physical.routes {
            for routeSegment in route.segments {
                guard routeSegment.x1 != routeSegment.x2 || routeSegment.y1 != routeSegment.y2 else {
                    throw ElectricalSignoffError.malformedTopology("route segment \(routeSegment.id) has zero length")
                }
                guard let layerRule = profileLayerRules[routeSegment.layer] else {
                    throw ElectricalSignoffError.insufficientTopology(
                        "no electrical layer rule exists for physical layer \(routeSegment.layer)"
                    )
                }
                let start = Point(
                    x: Double(routeSegment.x1) / Double(unitsPerMicron),
                    y: Double(routeSegment.y1) / Double(unitsPerMicron)
                )
                let end = Point(
                    x: Double(routeSegment.x2) / Double(unitsPerMicron),
                    y: Double(routeSegment.y2) / Double(unitsPerMicron)
                )
                let fromNodeID = nodeBuilder.resolve(
                    netID: route.netID,
                    point: start,
                    fallbackID: "route:\(route.id):\(routeSegment.id):from"
                )
                let toNodeID = nodeBuilder.resolve(
                    netID: route.netID,
                    point: end,
                    fallbackID: "route:\(route.id):\(routeSegment.id):to"
                )
                let length = hypot(end.x - start.x, end.y - start.y)
                let resistance = parasiticResistanceByNet[route.netID].map { totalResistance in
                    let totalLength = max(totalRouteLengthByNet[route.netID] ?? length, length)
                    return totalResistance * length / totalLength
                } ?? layerRule.resistanceOhmPerMicron * length
                guard resistance > 0 else {
                    throw ElectricalSignoffError.insufficientTopology(
                        "route \(routeSegment.id) has no positive resistance from PEX or layer rules"
                    )
                }
                segments.append(ElectricalTopology.Segment(
                    id: routeSegment.id,
                    netID: route.netID,
                    fromNodeID: fromNodeID,
                    toNodeID: toNodeID,
                    resistanceOhm: resistance,
                    widthMicron: layerRule.widthMicron,
                    thicknessMicron: layerRule.thicknessMicron,
                    layer: "\(routeSegment.layer)"
                ))
            }
        }

        var vias: [ElectricalTopology.Via] = []
        for via in physical.vias {
            let point = Point(
                x: Double(via.x) / Double(unitsPerMicron),
                y: Double(via.y) / Double(unitsPerMicron)
            )
            let nodeID = nodeBuilder.resolve(
                netID: via.netID,
                point: point,
                fallbackID: "via:\(via.id)"
            )
            vias.append(ElectricalTopology.Via(
                id: via.id,
                netID: via.netID,
                nodeID: nodeID,
                resistanceOhm: profile.viaRule.resistanceOhm,
                cutAreaSquareMicron: profile.viaRule.cutAreaSquareMicron,
                count: profile.viaRule.count
            ))
        }

        var devices: [ElectricalTopology.Device] = []
        var devicePinNodes: [(device: GateCell, pin: GatePin, nodeID: String)] = []
        for cell in gateModule.cells {
            let physicalCell = physical.cells.first { physicalCell in
                physicalCell.id == cell.instanceName || physicalCell.id == cell.id
            }
            let rule = profileDeviceRules[cell.type]
                ?? pdkDeviceRules[cell.type].map { device in
                    ElectricalTopologyExtractionProfile.DeviceRule(master: cell.type, model: device.modelName)
                }
                ?? ElectricalTopologyExtractionProfile.DeviceRule(master: cell.type, model: cell.type)
            var terminals: [String: String] = [:]
            for pin in cell.pins {
                guard let netID = pin.netID else {
                    continue
                }
                let nodeID = physicalPinByCellAndName["\(cell.instanceName):\(pin.name)"]
                    ?? physicalPinByCellAndName["\(cell.id):\(pin.name)"]
                    ?? "gate-pin:\(cell.id):\(pin.name)"
                nodeBuilder.add(id: nodeID, netID: netID)
                terminals[pin.name] = netID
                devicePinNodes.append((cell, pin, nodeID))
            }
            devices.append(ElectricalTopology.Device(
                id: cell.id,
                model: rule.model,
                terminals: terminals,
                domainID: rule.domainID,
                maxTerminalVoltageV: rule.maxTerminalVoltageV,
                isDriver: rule.isDriver,
                wellID: rule.wellID,
                widthMicron: physicalCell.map { Double($0.width) / Double(unitsPerMicron) },
                lengthMicron: physicalCell.map { Double($0.height) / Double(unitsPerMicron) }
            ))
        }
        guard !devices.isEmpty else {
            throw ElectricalSignoffError.insufficientTopology("gate-level top module contains no cells")
        }

        let loadRulesByNet = Dictionary(grouping: profile.loadRules, by: \.netID)
        var loads: [ElectricalTopology.Load] = []
        for entry in devicePinNodes where entry.pin.direction != .output {
            guard let netID = entry.pin.netID else {
                continue
            }
            for rule in loadRulesByNet[netID] ?? [] {
                guard rule.deviceType == nil || rule.deviceType == entry.device.type else {
                    continue
                }
                loads.append(ElectricalTopology.Load(
                    id: "\(rule.id):\(entry.device.id):\(entry.pin.name)",
                    netID: netID,
                    nodeID: entry.nodeID,
                    staticCurrentA: rule.staticCurrentA,
                    dynamicCurrentA: rule.dynamicCurrentA,
                    activityFactor: rule.activityFactor,
                    domainID: rule.domainID
                ))
            }
        }
        guard !profile.loadRules.isEmpty else {
            throw ElectricalSignoffError.insufficientTopology(
                "electrical extraction profile contains no load characterization rules"
            )
        }
        guard !loads.isEmpty else {
            throw ElectricalSignoffError.insufficientTopology(
                "electrical extraction profile does not match any connected gate pins"
            )
        }

        guard !profile.sourceRules.isEmpty else {
            throw ElectricalSignoffError.insufficientTopology(
                "electrical extraction profile contains no source characterization rules"
            )
        }
        let sourceResult = try makeSources(profile: profile, nodes: nodeBuilder.nodes)
        let domains = try makeDomains(profile: profile, powerIntent: sources.powerIntent)
        let powerIntentDigest: String?
        if let powerIntent = sources.request.powerIntent {
            powerIntentDigest = try sources.request
                .materializedArtifact(for: powerIntent.artifact, role: "power-intent")
                .sha256
        } else {
            powerIntentDigest = nil
        }
        let nets = netIDs.sorted().map { netID in
            let rule = profileNetRules[netID]
            let domainID = rule?.domainID ?? powerIntentDomains[netID]
            let nominalVoltage = rule?.nominalVoltageV ?? domains.first(where: { $0.id == domainID })?.nominalVoltageV
            return ElectricalTopology.Net(
                id: netID,
                kind: rule?.kind ?? inferredNetKind(netID: netID, powerIntentSupplyNets: powerIntentSupplyNets),
                nominalVoltageV: nominalVoltage,
                domainID: domainID
            )
        }

        let topology = ElectricalTopology(
            designDigest: sources.request.design.designDigest,
            pdkDigest: sources.request.pdk.digest,
            layoutDigest: sources.request.physicalDesign.layoutDigest,
            topCell: sources.request.physicalDesign.topCell,
            parasiticDigest: sources.request.parasitics?.sha256,
            nodes: nodeBuilder.nodes.values.sorted { $0.id < $1.id },
            nets: nets,
            devices: devices.sorted { $0.id < $1.id },
            segments: segments.sorted { $0.id < $1.id },
            vias: vias.sorted { $0.id < $1.id },
            sources: sourceResult.sorted { $0.id < $1.id },
            loads: loads.sorted { $0.id < $1.id },
            activityVectors: profile.activityVectors,
            domains: domains,
            esdClamps: profile.esdClamps,
            wells: profile.wells,
            substrateContacts: profile.substrateContacts,
            agingModels: profile.agingModels,
            rules: defaultRules,
            powerIntentDigest: powerIntentDigest,
            rulesByCorner: rulesByCorner
        )
        try ElectricalTopologyValidator().validate(topology)
        return topology
    }

    private func validateProfile(_ profile: ElectricalTopologyExtractionProfile) throws {
        guard profile.schemaVersion == ElectricalTopologyExtractionProfile.currentSchemaVersion else {
            throw ElectricalSignoffError.schemaVersionUnsupported(profile.schemaVersion)
        }
        guard profile.connectivityToleranceMicron.isFinite,
              profile.connectivityToleranceMicron >= 0 else {
            throw ElectricalSignoffError.malformedTopology("connectivity tolerance must be non-negative")
        }
        guard Set(profile.netRules.map(\.netID)).count == profile.netRules.count,
              Set(profile.sourceRules.map(\.id)).count == profile.sourceRules.count,
              Set(profile.loadRules.map(\.id)).count == profile.loadRules.count,
              Set(profile.layerRules.map(\.layer)).count == profile.layerRules.count,
              Set(profile.deviceRules.map(\.master)).count == profile.deviceRules.count,
              profile.netRules.allSatisfy({ nonEmpty($0.netID) }),
              profile.sourceRules.allSatisfy({ nonEmpty($0.id) && nonEmpty($0.netID) && nonEmpty($0.nodeID) }),
              profile.loadRules.allSatisfy({ nonEmpty($0.id) && nonEmpty($0.netID) }),
              profile.layerRules.allSatisfy({ $0.layer >= 0 }),
              profile.deviceRules.allSatisfy({ nonEmpty($0.master) && nonEmpty($0.model) }) else {
            throw ElectricalSignoffError.malformedTopology("extraction profile identifiers must be unique")
        }
        guard profile.netRules.allSatisfy({
            $0.nominalVoltageV.map({ $0.isFinite }) ?? true
        }), profile.sourceRules.allSatisfy({
            $0.voltageV.isFinite && $0.maxCurrentA.isFinite && $0.maxCurrentA >= 0
        }), profile.loadRules.allSatisfy({
            $0.staticCurrentA.isFinite && $0.staticCurrentA >= 0
                && $0.dynamicCurrentA.isFinite && $0.dynamicCurrentA >= 0
                && $0.activityFactor.isFinite && $0.activityFactor >= 0 && $0.activityFactor <= 1
        }) else {
            throw ElectricalSignoffError.malformedTopology("extraction profile electrical values are invalid")
        }
        for layer in profile.layerRules {
            guard layer.widthMicron.isFinite, layer.widthMicron > 0,
                  layer.thicknessMicron.isFinite, layer.thicknessMicron > 0,
                  layer.resistanceOhmPerMicron.isFinite, layer.resistanceOhmPerMicron > 0 else {
                throw ElectricalSignoffError.malformedTopology("layer \(layer.layer) has invalid electrical geometry")
            }
        }
        guard profile.viaRule.resistanceOhm.isFinite, profile.viaRule.resistanceOhm > 0,
              profile.viaRule.cutAreaSquareMicron.isFinite, profile.viaRule.cutAreaSquareMicron > 0,
              profile.viaRule.count > 0 else {
            throw ElectricalSignoffError.malformedTopology("via rule has invalid electrical geometry")
        }
        guard profile.deviceRules.allSatisfy({
            ($0.domainID.map({ nonEmpty($0) }) ?? true)
                && ($0.wellID.map({ nonEmpty($0) }) ?? true)
                && ($0.maxTerminalVoltageV.map({ $0.isFinite && $0 >= 0 }) ?? true)
        }), profile.activityVectors.allSatisfy({
            nonEmpty($0.id) && $0.weight.isFinite && $0.weight >= 0
                && $0.peakScale.isFinite && $0.peakScale >= 0
        }), Set(profile.activityVectors.map(\.id)).count == profile.activityVectors.count else {
            throw ElectricalSignoffError.malformedTopology("extraction profile device or activity characterization is invalid")
        }
        guard validRules(profile.rules) else {
            throw ElectricalSignoffError.malformedTopology("extraction profile rule limits are invalid")
        }
    }

    private func validateProcessRules(
        _ processRules: ElectricalProcessRuleSet,
        sources: ElectricalTopologySourceBundle
    ) throws {
        guard processRules.schemaVersion == ElectricalProcessRuleSet.currentSchemaVersion else {
            throw ElectricalSignoffError.schemaVersionUnsupported(processRules.schemaVersion)
        }
        guard processRules.pdkDigest.caseInsensitiveCompare(sources.request.pdk.digest) == .orderedSame,
              processRules.processID == sources.request.pdk.processID,
              processRules.pdkVersion == sources.request.pdk.version else {
            throw ElectricalSignoffError.digestMismatch(
                kind: "process rules",
                expected: sources.request.pdk.digest,
                actual: processRules.pdkDigest
            )
        }
        let manifestCornerIDs = Set(sources.pdk.corners.map(\.cornerID))
        guard !manifestCornerIDs.isEmpty else {
            throw ElectricalSignoffError.insufficientTopology("PDK manifest contains no declared electrical corners")
        }
        guard !processRules.cornerRules.isEmpty,
              Set(processRules.cornerRules.map(\.cornerID)).count == processRules.cornerRules.count,
              processRules.cornerRules.allSatisfy({ manifestCornerIDs.contains($0.cornerID) }) else {
            throw ElectricalSignoffError.insufficientTopology("process rules are outside the declared PDK corner scope")
        }
        for condition in sources.request.configuration.operatingConditions {
            guard processRules.ruleSet(for: condition.pdkCornerID) != nil else {
                throw ElectricalSignoffError.insufficientTopology(
                    "no process rule exists for PDK corner \(condition.pdkCornerID)"
                )
            }
        }
    }

    private func totalRouteLengths(
        physical: PhysicalDesignSnapshot,
        unitsPerMicron: Int
    ) -> [String: Double] {
        physical.routes.reduce(into: [String: Double]()) { result, route in
            for segment in route.segments {
                let dx = Double(segment.x2 - segment.x1) / Double(unitsPerMicron)
                let dy = Double(segment.y2 - segment.y1) / Double(unitsPerMicron)
                result[route.netID, default: 0] += hypot(dx, dy)
            }
        }
    }

    private func makeSources(
        profile: ElectricalTopologyExtractionProfile,
        nodes: [String: ElectricalTopology.Node]
    ) throws -> [ElectricalTopology.Source] {
        let values = try profile.sourceRules.map { rule in
            guard let node = nodes[rule.nodeID], node.netID == rule.netID else {
                throw ElectricalSignoffError.insufficientTopology(
                    "source rule \(rule.id) does not resolve to a node on net \(rule.netID)"
                )
            }
            guard rule.maxCurrentA >= 0 else {
                throw ElectricalSignoffError.malformedTopology("source rule \(rule.id) has a negative current limit")
            }
            return ElectricalTopology.Source(
                id: rule.id,
                netID: rule.netID,
                nodeID: rule.nodeID,
                voltageV: rule.voltageV,
                maxCurrentA: rule.maxCurrentA
            )
        }
        return values
    }

    private func makeDomains(
        profile: ElectricalTopologyExtractionProfile,
        powerIntent: PowerIntentDesign?
    ) throws -> [ElectricalTopology.Domain] {
        let domains = profile.domains
        if let powerIntent {
            let known = Set(domains.map(\.id))
            for domain in powerIntent.domains where !known.contains(domain.id) {
                throw ElectricalSignoffError.insufficientTopology(
                    "power-intent domain \(domain.id) has no voltage characterization in the extraction profile"
                )
            }
        }
        return domains.sorted { $0.id < $1.id }
    }

    private func inferredNetKind(
        netID: String,
        powerIntentSupplyNets: Set<String>
    ) -> ElectricalTopology.NetKind {
        let normalized = netID.lowercased()
        if normalized.contains("gnd") || normalized.contains("vss") || normalized.contains("ground") || normalized.contains("substrate") {
            return .ground
        }
        if powerIntentSupplyNets.contains(netID) || normalized.contains("vdd") || normalized.contains("vcc") || normalized.contains("power") {
            return .power
        }
        return .signal
    }

    private func validRules(_ rules: ElectricalTopology.RuleSet) -> Bool {
        rules.maximumIRDropV.isFinite && rules.maximumIRDropV > 0
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
