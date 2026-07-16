import Foundation

public struct ElectricalArtifactNamespace: Sendable, Hashable, Codable {
    public static let electricalSignoff = ElectricalArtifactNamespace(
        validatedSegments: [.electricalSignoff]
    )

    public let segments: [ElectricalArtifactPathSegment]

    public init(segments: [ElectricalArtifactPathSegment]) throws {
        guard !segments.isEmpty else {
            throw ElectricalArtifactStoreError.invalidNamespace("")
        }
        self.segments = segments
    }

    public init(validating path: String) throws {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty, !components.contains(where: { $0.isEmpty }) else {
            throw ElectricalArtifactStoreError.invalidNamespace(path)
        }
        do {
            segments = try components.map {
                try ElectricalArtifactPathSegment(validating: String($0))
            }
        } catch {
            throw ElectricalArtifactStoreError.invalidNamespace(path)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(validating: container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(relativePath)
    }

    public var relativePath: String {
        segments.map(\.rawValue).joined(separator: "/")
    }

    private init(validatedSegments: [ElectricalArtifactPathSegment]) {
        segments = validatedSegments
    }
}
