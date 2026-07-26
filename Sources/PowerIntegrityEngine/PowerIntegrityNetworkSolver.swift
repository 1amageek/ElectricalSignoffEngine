import Foundation
import ElectricalSignoffCore

public struct PowerIntegrityNetworkSolver: Sendable {
    private struct NetNodeKey: Hashable {
        var netID: String
        var nodeID: String
    }

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
        var sourceIndexByNode: [String: Int] = [:]
        sourceIndexByNode.reserveCapacity(topology.sources.count)
        for sourceIndex in topology.sources.indices {
            let source = topology.sources[sourceIndex]
            guard sourceIndexByNode.updateValue(sourceIndex, forKey: source.nodeID) == nil else {
                throw ElectricalSignoffError.insufficientTopology(
                    "power node \(source.nodeID) has multiple independent sources"
                )
            }
        }
        var nodeVoltages: [String: Double] = [:]
        nodeVoltages.reserveCapacity(topology.nodes.count)
        let effectiveVoltageScale = max(0, voltageScale)
        for source in topology.sources {
            nodeVoltages[source.nodeID] = source.voltageV * effectiveVoltageScale
        }

        let effectiveActivityScale = dynamic ? max(0, activityScale) : 0
        var netKindByID: [String: ElectricalTopology.NetKind] = [:]
        netKindByID.reserveCapacity(topology.nets.count)
        for net in topology.nets {
            netKindByID[net.id] = net.kind
        }
        var nodeIndicesByNet: [String: [Int]] = [:]
        nodeIndicesByNet.reserveCapacity(topology.nets.count)
        for nodeIndex in topology.nodes.indices {
            nodeIndicesByNet[topology.nodes[nodeIndex].netID, default: []].append(nodeIndex)
        }
        var segmentIndicesByNet: [String: [Int]] = [:]
        segmentIndicesByNet.reserveCapacity(topology.nets.count)
        for segmentIndex in topology.segments.indices {
            segmentIndicesByNet[topology.segments[segmentIndex].netID, default: []].append(segmentIndex)
        }
        var loadIndicesByNet: [String: [Int]] = [:]
        loadIndicesByNet.reserveCapacity(topology.nets.count)
        for loadIndex in topology.loads.indices {
            loadIndicesByNet[topology.loads[loadIndex].netID, default: []].append(loadIndex)
        }
        let analyzedNetKinds: Set<ElectricalTopology.NetKind> = [.power, .ground, .substrate, .analog]
        for net in topology.nets where analyzedNetKinds.contains(net.kind) {
            let nodeIndices = nodeIndicesByNet[net.id] ?? []
            let unknownNodeIndices = nodeIndices.filter {
                sourceIndexByNode[topology.nodes[$0].id] == nil
            }
            guard !unknownNodeIndices.isEmpty else {
                continue
            }
            var indexByNode: [String: Int] = [:]
            indexByNode.reserveCapacity(unknownNodeIndices.count)
            for (matrixIndex, nodeIndex) in unknownNodeIndices.enumerated() {
                indexByNode[topology.nodes[nodeIndex].id] = matrixIndex
            }
            var matrix = Array(
                repeating: Array(repeating: 0.0, count: unknownNodeIndices.count),
                count: unknownNodeIndices.count
            )
            var rhs = Array(repeating: 0.0, count: unknownNodeIndices.count)

            for segmentIndex in segmentIndicesByNet[net.id] ?? [] {
                let segment = topology.segments[segmentIndex]
                let conductance = 1 / segment.resistanceOhm
                let fromUnknown = indexByNode[segment.fromNodeID]
                let toUnknown = indexByNode[segment.toNodeID]
                let fromSourceIndex = sourceIndexByNode[segment.fromNodeID]
                let toSourceIndex = sourceIndexByNode[segment.toNodeID]
                if let fromIndex = fromUnknown {
                    matrix[fromIndex][fromIndex] += conductance
                    if let toIndex = toUnknown {
                        matrix[fromIndex][toIndex] -= conductance
                    } else if let toSourceIndex {
                        let toSource = topology.sources[toSourceIndex]
                        rhs[fromIndex] += conductance * toSource.voltageV * effectiveVoltageScale
                    }
                }
                if let toIndex = toUnknown {
                    matrix[toIndex][toIndex] += conductance
                    if let fromIndex = fromUnknown {
                        matrix[toIndex][fromIndex] -= conductance
                    } else if let fromSourceIndex {
                        let fromSource = topology.sources[fromSourceIndex]
                        rhs[toIndex] += conductance * fromSource.voltageV * effectiveVoltageScale
                    }
                }
            }

            for loadIndex in loadIndicesByNet[net.id] ?? [] {
                let load = topology.loads[loadIndex]
                guard let index = indexByNode[load.nodeID] else {
                    continue
                }
                let current = load.staticCurrentA + load.dynamicCurrentA * load.activityFactor * effectiveActivityScale
                rhs[index] -= current
            }

            let voltages = try solveLinearSystem(matrix: matrix, rhs: rhs, netID: net.id)
            for nodeIndex in unknownNodeIndices {
                let node = topology.nodes[nodeIndex]
                guard let index = indexByNode[node.id] else {
                    continue
                }
                nodeVoltages[node.id] = voltages[index]
            }
        }

        for node in topology.nodes {
            if let netKind = netKindByID[node.netID],
               analyzedNetKinds.contains(netKind),
               nodeVoltages[node.id] == nil {
                throw ElectricalSignoffError.insufficientTopology(
                    "every extracted power node must be connected to a fixed source"
                )
            }
        }

        var segmentCurrents: [String: Double] = [:]
        segmentCurrents.reserveCapacity(topology.segments.count)
        var segmentCurrentByNode: [String: Double] = [:]
        segmentCurrentByNode.reserveCapacity(topology.nodes.count)
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
            segmentCurrentByNode[segment.fromNodeID, default: 0] += current
            segmentCurrentByNode[segment.toNodeID, default: 0] += current
        }

        var loadCurrentByNode: [String: Double] = [:]
        loadCurrentByNode.reserveCapacity(topology.loads.count)
        var loadCurrentByNetAndNode: [NetNodeKey: Double] = [:]
        loadCurrentByNetAndNode.reserveCapacity(topology.loads.count)
        for load in topology.loads {
            let current = load.staticCurrentA
                + load.dynamicCurrentA * load.activityFactor * effectiveActivityScale
            loadCurrentByNode[load.nodeID, default: 0] += current
            loadCurrentByNetAndNode[
                NetNodeKey(netID: load.netID, nodeID: load.nodeID),
                default: 0
            ] += current
        }

        var viaCurrents: [String: Double] = [:]
        viaCurrents.reserveCapacity(topology.vias.count)
        for via in topology.vias {
            if via.currentA > 0 {
                viaCurrents[via.id] = via.currentA * (dynamic ? max(1, effectiveActivityScale) : 1)
            } else {
                viaCurrents[via.id] = loadCurrentByNetAndNode[
                    NetNodeKey(netID: via.netID, nodeID: via.nodeID),
                    default: 0
                ]
            }
        }

        var sourceCurrents: [String: Double] = [:]
        sourceCurrents.reserveCapacity(topology.sources.count)
        for source in topology.sources {
            sourceCurrents[source.id] =
                segmentCurrentByNode[source.nodeID, default: 0]
                + loadCurrentByNode[source.nodeID, default: 0]
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
