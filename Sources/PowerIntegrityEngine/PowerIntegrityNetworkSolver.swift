import Foundation
import ElectricalSignoffCore

public struct PowerIntegrityNetworkSolver: Sendable {
    public struct Solution: Sendable, Hashable, Codable {
        public var nodeVoltages: [String: Double]
        public var segmentCurrentsA: [String: Double]
        public var viaCurrentsA: [String: Double]
        public var sourceCurrentsA: [String: Double]
        public var activityScale: Double
        public var voltageScale: Double

        public init(
            nodeVoltages: [String: Double],
            segmentCurrentsA: [String: Double],
            viaCurrentsA: [String: Double],
            sourceCurrentsA: [String: Double] = [:],
            activityScale: Double,
            voltageScale: Double = 1
        ) {
            self.nodeVoltages = nodeVoltages
            self.segmentCurrentsA = segmentCurrentsA
            self.viaCurrentsA = viaCurrentsA
            self.sourceCurrentsA = sourceCurrentsA
            self.activityScale = activityScale
            self.voltageScale = voltageScale
        }
    }

    public init() {}

    public func solve(
        topology: ElectricalTopology,
        dynamic: Bool,
        activityScale: Double,
        voltageScale: Double = 1
    ) throws -> Solution {
        let sourcesByNode = Dictionary(grouping: topology.sources, by: \.nodeID)
        if let duplicateNode = sourcesByNode.first(where: { $0.value.count > 1 }) {
            throw ElectricalSignoffError.insufficientTopology("power node \(duplicateNode.key) has multiple independent sources")
        }
        let sourceByNode = sourcesByNode.compactMapValues(\.first)
        var nodeVoltages: [String: Double] = [:]
        let effectiveVoltageScale = max(0, voltageScale)
        for source in topology.sources {
            nodeVoltages[source.nodeID] = source.voltageV * effectiveVoltageScale
        }

        let effectiveActivityScale = dynamic ? max(0, activityScale) : 0
        let nodesByNet = Dictionary(grouping: topology.nodes, by: \.netID)
        let analyzedNetKinds: Set<ElectricalTopology.NetKind> = [.power, .ground, .substrate, .analog]
        let analyzedNodeIDs = Set(topology.nodes.filter { node in
            guard let net = topology.nets.first(where: { $0.id == node.netID }) else {
                return false
            }
            return analyzedNetKinds.contains(net.kind)
        }.map(\.id))
        for net in topology.nets where analyzedNetKinds.contains(net.kind) {
            let nodes = nodesByNet[net.id] ?? []
            let unknownNodes = nodes.filter { sourceByNode[$0.id] == nil }
            guard !unknownNodes.isEmpty else {
                continue
            }
            let indexByNode = Dictionary(uniqueKeysWithValues: unknownNodes.enumerated().map { ($1.id, $0) })
            var matrix = Array(repeating: Array(repeating: 0.0, count: unknownNodes.count), count: unknownNodes.count)
            var rhs = Array(repeating: 0.0, count: unknownNodes.count)

            for segment in topology.segments where segment.netID == net.id {
                let conductance = 1 / segment.resistanceOhm
                let fromUnknown = indexByNode[segment.fromNodeID]
                let toUnknown = indexByNode[segment.toNodeID]
                let fromSource = sourceByNode[segment.fromNodeID]
                let toSource = sourceByNode[segment.toNodeID]
                if let fromIndex = fromUnknown {
                    matrix[fromIndex][fromIndex] += conductance
                    if let toIndex = toUnknown {
                        matrix[fromIndex][toIndex] -= conductance
                    } else if let toSource {
                        rhs[fromIndex] += conductance * toSource.voltageV * effectiveVoltageScale
                    }
                }
                if let toIndex = toUnknown {
                    matrix[toIndex][toIndex] += conductance
                    if let fromIndex = fromUnknown {
                        matrix[toIndex][fromIndex] -= conductance
                    } else if let fromSource {
                        rhs[toIndex] += conductance * fromSource.voltageV * effectiveVoltageScale
                    }
                }
            }

            for load in topology.loads where load.netID == net.id {
                guard let index = indexByNode[load.nodeID] else {
                    continue
                }
                let current = load.staticCurrentA + load.dynamicCurrentA * load.activityFactor * effectiveActivityScale
                rhs[index] -= current
            }

            let voltages = try solveLinearSystem(matrix: matrix, rhs: rhs, netID: net.id)
            for node in unknownNodes {
                guard let index = indexByNode[node.id] else {
                    continue
                }
                nodeVoltages[node.id] = voltages[index]
            }
        }

        guard analyzedNodeIDs.isSubset(of: Set(nodeVoltages.keys)) else {
            throw ElectricalSignoffError.insufficientTopology("every extracted power node must be connected to a fixed source")
        }

        var segmentCurrents: [String: Double] = [:]
        for segment in topology.segments {
            let current: Double
            if segment.currentA > 0 {
                current = segment.currentA * (dynamic ? max(1, effectiveActivityScale) : 1)
            } else {
                let fromVoltage = nodeVoltages[segment.fromNodeID] ?? 0
                let toVoltage = nodeVoltages[segment.toNodeID] ?? 0
                current = abs(fromVoltage - toVoltage) / segment.resistanceOhm
            }
            segmentCurrents[segment.id] = current
        }

        var viaCurrents: [String: Double] = [:]
        for via in topology.vias {
            if via.currentA > 0 {
                viaCurrents[via.id] = via.currentA * (dynamic ? max(1, effectiveActivityScale) : 1)
            } else {
                let loadCurrent = topology.loads
                    .filter { $0.netID == via.netID && $0.nodeID == via.nodeID }
                    .reduce(0) { partial, load in
                        partial + load.staticCurrentA + load.dynamicCurrentA * load.activityFactor * effectiveActivityScale
                    }
                viaCurrents[via.id] = loadCurrent
            }
        }

        var sourceCurrents: [String: Double] = [:]
        for source in topology.sources {
            let segmentCurrent = topology.segments
                .filter { segment in
                    segment.fromNodeID == source.nodeID || segment.toNodeID == source.nodeID
                }
                .reduce(0) { partial, segment in
                    partial + (segmentCurrents[segment.id] ?? 0)
                }
            let localLoadCurrent = topology.loads
                .filter { $0.nodeID == source.nodeID }
                .reduce(0) { partial, load in
                    partial + load.staticCurrentA + load.dynamicCurrentA * load.activityFactor * effectiveActivityScale
                }
            sourceCurrents[source.id] = segmentCurrent + localLoadCurrent
        }

        return Solution(
            nodeVoltages: nodeVoltages,
            segmentCurrentsA: segmentCurrents,
            viaCurrentsA: viaCurrents,
            sourceCurrentsA: sourceCurrents,
            activityScale: effectiveActivityScale,
            voltageScale: effectiveVoltageScale
        )
    }

    private func solveLinearSystem(matrix: [[Double]], rhs: [Double], netID: String) throws -> [Double] {
        var matrix = matrix
        var rhs = rhs
        let count = rhs.count
        for pivot in 0..<count {
            var pivotRow = pivot
            for row in (pivot + 1)..<count where abs(matrix[row][pivot]) > abs(matrix[pivotRow][pivot]) {
                pivotRow = row
            }
            guard abs(matrix[pivotRow][pivot]) > 1e-15 else {
                throw ElectricalSignoffError.insufficientTopology("power net \(netID) is singular or floating")
            }
            if pivotRow != pivot {
                matrix.swapAt(pivotRow, pivot)
                rhs.swapAt(pivotRow, pivot)
            }
            let pivotValue = matrix[pivot][pivot]
            for column in pivot..<count {
                matrix[pivot][column] /= pivotValue
            }
            rhs[pivot] /= pivotValue
            for row in 0..<count where row != pivot {
                let factor = matrix[row][pivot]
                guard abs(factor) > 1e-15 else {
                    continue
                }
                for column in pivot..<count {
                    matrix[row][column] -= factor * matrix[pivot][column]
                }
                rhs[row] -= factor * rhs[pivot]
            }
        }
        return rhs
    }
}
