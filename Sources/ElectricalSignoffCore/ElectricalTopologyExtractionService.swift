import Foundation

public struct ElectricalTopologyExtractionService: Sendable {
    public let sourceLoader: any ElectricalTopologySourceLoading
    public let extractor: any ElectricalTopologyExtracting

    public init(
        sourceLoader: any ElectricalTopologySourceLoading,
        extractor: any ElectricalTopologyExtracting = NativeElectricalTopologyExtractor()
    ) {
        self.sourceLoader = sourceLoader
        self.extractor = extractor
    }

    public init(projectRoot: URL, verifyIntegrity: Bool = true) {
        self.init(
            sourceLoader: LocalElectricalTopologySourceLoader(
                projectRoot: projectRoot,
                verifyIntegrity: verifyIntegrity
            )
        )
    }

    public func extract(request: ElectricalSignoffRequest) async throws -> ElectricalTopology {
        let sources = try await sourceLoader.load(request: request)
        return try extractor.extract(sources)
    }
}
