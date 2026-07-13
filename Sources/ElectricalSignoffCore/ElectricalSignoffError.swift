import Foundation
import XcircuitePackage

public enum ElectricalSignoffError: Error, Sendable, Hashable, Codable, LocalizedError {
    case missingTopologyArtifact
    case unsupportedTopologyFormat(String)
    case unsupportedSourceFormat(source: String, format: String)
    case artifactIntegrity(path: String, status: XcircuiteFileReferenceIntegrityStatus, message: String)
    case malformedTopology(String)
    case schemaVersionUnsupported(Int)
    case digestMismatch(kind: String, expected: String, actual: String)
    case missingParasitics
    case insufficientTopology(String)
    case invalidConfiguration(String)
    case invalidRequest(String)
    case conflictingArtifactReferences(path: String)
    case invalidExecutionResult(String)
    case artifactPersistence(String)

    public var errorDescription: String? {
        switch self {
        case .missingTopologyArtifact:
            return "No JSON electrical topology artifact was provided."
        case let .unsupportedTopologyFormat(format):
            return "Electrical topology format is unsupported: \(format)."
        case let .unsupportedSourceFormat(source, format):
            return "Electrical topology source \(source) has unsupported format: \(format)."
        case let .artifactIntegrity(path, _, message):
            return "Artifact integrity check failed for \(path): \(message)"
        case let .malformedTopology(message):
            return "Electrical topology is malformed: \(message)"
        case let .schemaVersionUnsupported(version):
            return "Electrical topology schema version \(version) is unsupported."
        case let .digestMismatch(kind, expected, actual):
            return "Electrical topology \(kind) digest mismatch: expected \(expected), actual \(actual)."
        case .missingParasitics:
            return "Extracted parasitic data is required for electrical signoff."
        case let .insufficientTopology(message):
            return "Electrical topology does not contain sufficient extracted semantics: \(message)"
        case let .invalidConfiguration(message):
            return "Electrical signoff configuration is invalid: \(message)"
        case let .invalidRequest(message):
            return "Electrical signoff request is invalid: \(message)"
        case let .conflictingArtifactReferences(path):
            return "Electrical signoff request contains conflicting artifact references for \(path)."
        case let .invalidExecutionResult(message):
            return "Electrical signoff execution returned an invalid result: \(message)"
        case let .artifactPersistence(message):
            return "Electrical signoff artifact persistence failed: \(message)"
        }
    }
}
