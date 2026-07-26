public protocol ElectricalSignoffCommandRunning: Sendable {
    func run(arguments: [String]) async -> Int
}
