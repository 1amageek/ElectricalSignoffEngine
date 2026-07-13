import Foundation
import ElectricalSignoffCore
import ToolQualification
import XcircuitePackage

public struct DefaultElectricalSignoffProcessQualificationArtifactVerifier: ElectricalSignoffProcessQualificationArtifactVerifying, Sendable {
    private let foundationArtifactBridge: ElectricalSignoffFoundationArtifactBridge

    public init(
        foundationArtifactBridge: ElectricalSignoffFoundationArtifactBridge = ElectricalSignoffFoundationArtifactBridge()
    ) {
        self.foundationArtifactBridge = foundationArtifactBridge
    }

    public func verify(
        _ request: ElectricalSignoffProcessQualificationRequest,
        projectRoot: URL
    ) -> [ElectricalSignoffProcessQualificationArtifactIntegrityIssue] {
        let groups: [(String, [ToolEvidence])] = [
            ("corpus", request.processEvidence.corpusEvidence),
            ("oracle", request.processEvidence.oracleEvidence),
            ("health", request.processEvidence.healthEvidence),
            ("approval", request.processEvidence.approvalEvidence),
        ]
        var artifacts: [(category: String, reference: XcircuiteFileReference)] = []
        for (category, evidence) in groups {
            for item in evidence {
                if let artifact = item.artifact {
                    artifacts.append((category: category, reference: artifact))
                }
            }
        }
        artifacts.append(contentsOf: request.processEvidence.evidenceArtifacts.map {
            (category: "evidence", reference: $0)
        })

        var verifiedReferencesByPath: [String: XcircuiteFileReference] = [:]
        var issues: [ElectricalSignoffProcessQualificationArtifactIntegrityIssue] = []
        for item in artifacts {
            if let existing = verifiedReferencesByPath[item.reference.path] {
                if existing != item.reference {
                    issues.append(ElectricalSignoffProcessQualificationArtifactIntegrityIssue(
                        category: item.category,
                        integrity: XcircuiteFileReferenceIntegrity(
                            status: .invalidPath,
                            path: item.reference.path,
                            expectedSHA256: item.reference.sha256,
                            expectedByteCount: item.reference.byteCount,
                            message: "Conflicting process qualification artifact references share one path."
                        )
                    ))
                }
                continue
            }
            verifiedReferencesByPath[item.reference.path] = item.reference
            do {
                try foundationArtifactBridge.validate(
                    item.reference,
                    relativeTo: projectRoot,
                    verifyIntegrity: true
                )
            } catch let error as ElectricalSignoffFoundationArtifactBridgeError {
                issues.append(ElectricalSignoffProcessQualificationArtifactIntegrityIssue(
                    category: item.category,
                    integrity: integrity(for: item.reference, error: error)
                ))
                continue
            } catch {
                issues.append(ElectricalSignoffProcessQualificationArtifactIntegrityIssue(
                    category: item.category,
                    integrity: XcircuiteFileReferenceIntegrity(
                        status: .unreadableArtifact,
                        path: item.reference.path,
                        expectedSHA256: item.reference.sha256,
                        expectedByteCount: item.reference.byteCount,
                        message: error.localizedDescription
                    )
                ))
                continue
            }

            if item.category == "approval",
               let approvalIssue = verifyApproval(
                   item.reference,
                   request: request,
                   projectRoot: projectRoot
               ) {
                issues.append(approvalIssue)
            }
        }
        return issues
    }

    private func verifyApproval(
        _ reference: XcircuiteFileReference,
        request: ElectricalSignoffProcessQualificationRequest,
        projectRoot: URL
    ) -> ElectricalSignoffProcessQualificationArtifactIntegrityIssue? {
        let url: URL
        do {
            url = try foundationArtifactBridge.resolveURL(
                for: reference,
                relativeTo: projectRoot
            )
        } catch {
            return semanticIssue(
                reference,
                message: "Approval evidence path could not be resolved: \(error.localizedDescription)"
            )
        }
        do {
            let record = try JSONDecoder().decode(
                XcircuiteApprovalRecord.self,
                from: Data(contentsOf: url)
            )
            guard record.runID == request.qualificationReport.runID,
                  record.stageID == ElectricalSignoffProcessQualificationRequest.requiredApprovalStageID,
                  record.verdict == .approved,
                  record.reviewerKind == .human,
                  !record.reviewer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return semanticIssue(
                    reference,
                    message: "Approval evidence must be an approved human decision for the process qualification run and stage."
                )
            }
            return nil
        } catch {
            return semanticIssue(
                reference,
                message: "Approval evidence is not a decodable XcircuiteApprovalRecord: \(error.localizedDescription)"
            )
        }
    }

    private func semanticIssue(
        _ reference: XcircuiteFileReference,
        message: String
    ) -> ElectricalSignoffProcessQualificationArtifactIntegrityIssue {
        ElectricalSignoffProcessQualificationArtifactIntegrityIssue(
            category: "approval",
            integrity: XcircuiteFileReferenceIntegrity(
                status: .unreadableArtifact,
                path: reference.path,
                expectedSHA256: reference.sha256,
                expectedByteCount: reference.byteCount,
                message: message
            )
        )
    }

    private func integrity(
        for reference: XcircuiteFileReference,
        error: ElectricalSignoffFoundationArtifactBridgeError
    ) -> XcircuiteFileReferenceIntegrity {
        let status: XcircuiteFileReferenceIntegrityStatus
        switch error {
        case .invalidReference:
            status = .invalidPath
        case .missingArtifact:
            status = .missingArtifact
        case .notRegularFile, .unreadable:
            status = .unreadableArtifact
        case .digestMismatch:
            status = .sha256Mismatch
        case .byteCountMismatch:
            status = .byteCountMismatch
        case .missingDigest:
            status = .missingDigest
        case .missingByteCount:
            status = .missingByteCount
        }
        return XcircuiteFileReferenceIntegrity(
            status: status,
            path: reference.path,
            expectedSHA256: reference.sha256,
            expectedByteCount: reference.byteCount,
            message: error.localizedDescription
        )
    }
}
