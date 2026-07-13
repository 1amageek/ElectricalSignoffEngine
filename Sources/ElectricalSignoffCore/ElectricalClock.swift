import Foundation

public protocol ElectricalClock: Sendable {
    var now: Date { get }
}

public struct SystemElectricalClock: ElectricalClock {
    public init() {}

    public var now: Date { Date() }
}

public struct FixedElectricalClock: ElectricalClock {
    public let now: Date

    public init(now: Date) {
        self.now = now
    }
}
