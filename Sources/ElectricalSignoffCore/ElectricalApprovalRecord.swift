import Foundation

/// Domain approval evidence decoded by electrical qualification checks.
public struct ElectricalApprovalRecord: Sendable, Hashable, Codable {
    public enum Verdict: String, Sendable, Hashable, Codable {
        case approved
        case rejected
    }

    public enum ReviewerKind: String, Sendable, Hashable, Codable {
        case human
        case agent
        case cli
        case system
    }

    public var runID: String
    public var stageID: String
    public var verdict: Verdict
    public var reviewer: String
    public var reviewerKind: ReviewerKind
    public var note: String
    public var createdAt: Date

    public init(
        runID: String,
        stageID: String,
        verdict: Verdict,
        reviewer: String,
        reviewerKind: ReviewerKind,
        note: String = "",
        createdAt: Date = Date()
    ) {
        self.runID = runID
        self.stageID = stageID
        self.verdict = verdict
        self.reviewer = reviewer
        self.reviewerKind = reviewerKind
        self.note = note
        self.createdAt = createdAt
    }
}
