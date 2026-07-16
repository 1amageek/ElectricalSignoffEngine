import Foundation
import ElectricalSignoffCore
import ElectricalSignoffEvidence
import CircuiteFoundation

func makeTestOracleObservation(
    oracleID: String,
    toolVersion: String,
    pdkDigest: String,
    status: ElectricalSignoffExecutionStatus,
    violationCount: Int,
    diagnosticCodes: [String] = [],
    metrics: [ElectricalSignoffPayload.Metric] = []
) throws -> ElectricalSignoffOracleObservation {
    let input = try makeOracleArtifact(
        id: "oracle-input-\(oracleID)",
        path: "observations/oracle-input-\(oracleID).json",
        role: .input
    )
    let output = try makeOracleArtifact(
        id: "oracle-output-\(oracleID)",
        path: "observations/oracle-output-\(oracleID).json",
        role: .output
    )
    return ElectricalSignoffOracleObservation(
        oracleID: oracleID,
        toolVersion: toolVersion,
        pdkDigest: pdkDigest,
        status: status,
        violationCount: violationCount,
        diagnosticCodes: diagnosticCodes,
        metrics: metrics,
        inputArtifacts: [input],
        artifacts: [output],
        evidenceArtifact: output
    )
}

private func makeOracleArtifact(
    id: String,
    path: String,
    role: ArtifactRole
) throws -> ArtifactReference {
    ArtifactReference(
        id: try ArtifactID(rawValue: id),
        locator: ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: path),
            role: role,
            kind: .report,
            format: .json
        ),
        digest: try ContentDigest(
            algorithm: .sha256,
            hexadecimalValue: String(repeating: "d", count: 64)
        ),
        byteCount: 1
    )
}
