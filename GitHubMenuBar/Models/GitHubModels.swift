import Foundation

// MARK: - Pull Request Models

struct PullRequest: Identifiable, Codable, Hashable {
    var id: String { "\(repository.nameWithOwner)#\(number)" }

    let number: Int
    let title: String
    let url: String
    let updatedAt: Date
    let createdAt: Date?
    let isDraft: Bool
    let repository: Repository

    // Enriched fields (from pr view)
    var mergeable: String?
    var reviewDecision: String?
    var statusCheckRollup: [StatusCheck]?
    var needsAttention: Bool?
    var attentionReasons: [String]?
    var commentsCount: Int?
    var approvalsCount: Int?
    var reviewersCount: Int?
    var failingCheck: String?

    // For merged PRs
    var mergedAt: Date?
    var additions: Int?
    var deletions: Int?
    var hasExternalActivity: Bool?

    // For closed PRs
    var closedAt: Date?
    var closedBy: String?

    enum CodingKeys: String, CodingKey {
        case number, title, url, updatedAt, createdAt, isDraft, repository
        case mergeable, reviewDecision, statusCheckRollup
        case needsAttention, attentionReasons
        case commentsCount, approvalsCount, reviewersCount, failingCheck
        case mergedAt, additions, deletions, hasExternalActivity
        case closedAt, closedBy
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        number = try container.decode(Int.self, forKey: .number)
        title = try container.decode(String.self, forKey: .title)
        url = try container.decode(String.self, forKey: .url)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        isDraft = try container.decodeIfPresent(Bool.self, forKey: .isDraft) ?? false
        repository = try container.decode(Repository.self, forKey: .repository)
        mergeable = try container.decodeIfPresent(String.self, forKey: .mergeable)
        reviewDecision = try container.decodeIfPresent(String.self, forKey: .reviewDecision)
        statusCheckRollup = try container.decodeIfPresent([StatusCheck].self, forKey: .statusCheckRollup)
        needsAttention = try container.decodeIfPresent(Bool.self, forKey: .needsAttention)
        attentionReasons = try container.decodeIfPresent([String].self, forKey: .attentionReasons)
        commentsCount = try container.decodeIfPresent(Int.self, forKey: .commentsCount)
        approvalsCount = try container.decodeIfPresent(Int.self, forKey: .approvalsCount)
        reviewersCount = try container.decodeIfPresent(Int.self, forKey: .reviewersCount)
        failingCheck = try container.decodeIfPresent(String.self, forKey: .failingCheck)
        closedAt = try container.decodeIfPresent(Date.self, forKey: .closedAt)
        // gh search prs doesn't have mergedAt, use closedAt as fallback for merged PRs
        mergedAt = try container.decodeIfPresent(Date.self, forKey: .mergedAt) ?? closedAt
        additions = try container.decodeIfPresent(Int.self, forKey: .additions)
        deletions = try container.decodeIfPresent(Int.self, forKey: .deletions)
        hasExternalActivity = try container.decodeIfPresent(Bool.self, forKey: .hasExternalActivity)
        closedBy = try container.decodeIfPresent(String.self, forKey: .closedBy)
    }
}

struct Repository: Codable, Hashable {
    let nameWithOwner: String
}

struct StatusCheck: Codable, Hashable {
    let status: String?
    let state: String?
    let conclusion: String?
    let name: String?
}

struct Author: Codable, Hashable {
    let login: String
}

// MARK: - Review Request

struct ReviewRequest: Identifiable, Codable, Hashable {
    var id: String { "\(repository?.nameWithOwner ?? "unknown")#\(number)" }

    let number: Int
    let title: String
    let url: String
    let updatedAt: Date
    let author: Author
    let repository: Repository?
}

// MARK: - Notification

struct GitHubNotification: Identifiable, Codable, Hashable {
    var id: String { "\(reason)-\(title)-\(updatedAt.timeIntervalSince1970)" }

    let reason: String
    let title: String
    let url: String?
    let repoUrl: String?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case reason, title, url
        case repoUrl = "repo_url"
        case updatedAt = "updated_at"
    }
}

// MARK: - Issue

struct Issue: Identifiable, Codable, Hashable {
    var id: String { url }

    let number: Int
    let title: String
    let url: String
    let commentsCount: Int
    let updatedAt: Date
}

// MARK: - Aggregated State

struct GitHubState {
    var openPRs: [PullRequest] = []
    var mergedPRs: [PullRequest] = []
    var closedPRs: [PullRequest] = []
    var reviewRequests: [ReviewRequest] = []
    var notifications: [GitHubNotification] = []
    var issues: [Issue] = []
    var lastUpdated: Date?
    var isLoading: Bool = false
    var error: String?
    var username: String?

    // PR Preview state
    var previewState = PRPreviewState()

    var needsAttentionCount: Int {
        openPRs.filter { $0.needsAttention == true }.count + reviewRequests.count
    }
}

// MARK: - CI Status

enum CIStatus {
    case success
    case failure
    case pending
    case unknown

    static func from(checks: [StatusCheck]?) -> CIStatus {
        guard let checks = checks, !checks.isEmpty else { return .unknown }

        let hasFailure = checks.contains { $0.conclusion == "FAILURE" || $0.state == "FAILURE" }
        if hasFailure { return .failure }

        let allSuccess = checks.allSatisfy { $0.conclusion == "SUCCESS" || $0.state == "SUCCESS" }
        if allSuccess { return .success }

        return .pending
    }
}

// MARK: - Review Status

enum ReviewStatus {
    case approved
    case changesRequested
    case pending
    case unknown

    static func from(decision: String?) -> ReviewStatus {
        switch decision {
        case "APPROVED": return .approved
        case "CHANGES_REQUESTED": return .changesRequested
        case "REVIEW_REQUIRED": return .pending
        default: return .unknown
        }
    }
}
