import Foundation
import ElectricalSignoffCore
import ToolQualification
import CircuiteFoundation

public struct DefaultElectricalSignoffProcessQualificationArtifactVerifier: ElectricalSignoffProcessQualificationArtifactVerifying, Sendable {
    private let foundationArtifactBridge: ElectricalArtifactAccess

    public init(
        foundationArtifactBridge: ElectricalArtifactAccess = ElectricalArtifactAccess()
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
        var artifacts: [(category: String, reference: ArtifactReference)] = []
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

        var verifiedReferencesByPath: [String: ArtifactReference] = [:]
        var issues: [ElectricalSignoffProcessQualificationArtifactIntegrityIssue] = []
        for item in artifacts {
            if let existing = verifiedReferencesByPath[item.reference.path] {
                if existing != item.reference {
                    issues.append(ElectricalSignoffProcessQualificationArtifactIntegrityIssue(
                        category: item.category,
                        integrity: ArtifactIntegrity(issues: [
                            .invalidLocation("Conflicting process qualification artifact references share one path.")
                        ])
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
            } catch let error as ElectricalArtifactAccessError {
                issues.append(ElectricalSignoffProcessQualificationArtifactIntegrityIssue(
                    category: item.category,
                    integrity: integrity(for: item.reference, error: error)
                ))
                continue
            } catch {
                issues.append(ElectricalSignoffProcessQualificationArtifactIntegrityIssue(
                    category: item.category,
                    integrity: ArtifactIntegrity(issues: [
                        .unreadableFile(error.localizedDescription)
                    ])
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
        _ reference: ArtifactReference,
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
                ElectricalApprovalRecord.self,
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
                message: "Approval evidence is not a decodable ElectricalApprovalRecord: \(error.localizedDescription)"
            )
        }
    }

    private func semanticIssue(
        _ reference: ArtifactReference,
        message: String
    ) -> ElectricalSignoffProcessQualificationArtifactIntegrityIssue {
        ElectricalSignoffProcessQualificationArtifactIntegrityIssue(
            category: "approval",
            integrity: ArtifactIntegrity(issues: [.unreadableFile(message)])
        )
    }

    private func integrity(
        for reference: ArtifactReference,
        error: ElectricalArtifactAccessError
    ) -> ArtifactIntegrity {
        let issue: ArtifactIntegrityIssue
        switch error {
        case .invalidReference:
            issue = .invalidLocation(error.localizedDescription)
        case .missingArtifact:
            issue = .missingFile(reference.path)
        case .notRegularFile:
            issue = .notRegularFile(reference.path)
        case .integrityFailure:
            issue = .unreadableFile(error.localizedDescription)
        }
        return ArtifactIntegrity(issues: [issue])
    }
}
