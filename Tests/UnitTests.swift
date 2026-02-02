import XCTest
import Foundation

// MARK: - Unit Tests

/// Unit tests for business logic that doesn't require the gh CLI.
/// These tests recreate minimal versions of the types to test the logic.
final class UnitTests: XCTestCase {

    // MARK: - CI Status Tests

    func testCIStatusFromEmptyChecks() {
        XCTAssertEqual(CIStatus.from(checks: nil), .unknown)
        XCTAssertEqual(CIStatus.from(checks: []), .unknown)
    }

    func testCIStatusSuccess() {
        let checks = [
            StatusCheck(conclusion: "SUCCESS", state: nil),
            StatusCheck(conclusion: "SUCCESS", state: nil)
        ]
        XCTAssertEqual(CIStatus.from(checks: checks), .success)
    }

    func testCIStatusSuccessWithState() {
        let checks = [
            StatusCheck(conclusion: nil, state: "SUCCESS"),
            StatusCheck(conclusion: nil, state: "SUCCESS")
        ]
        XCTAssertEqual(CIStatus.from(checks: checks), .success)
    }

    func testCIStatusFailure() {
        let checks = [
            StatusCheck(conclusion: "SUCCESS", state: nil),
            StatusCheck(conclusion: "FAILURE", state: nil)
        ]
        XCTAssertEqual(CIStatus.from(checks: checks), .failure)
    }

    func testCIStatusFailureWithState() {
        let checks = [
            StatusCheck(conclusion: nil, state: "FAILURE")
        ]
        XCTAssertEqual(CIStatus.from(checks: checks), .failure)
    }

    func testCIStatusPending() {
        let checks = [
            StatusCheck(conclusion: "SUCCESS", state: nil),
            StatusCheck(conclusion: nil, state: "PENDING")
        ]
        XCTAssertEqual(CIStatus.from(checks: checks), .pending)
    }

    func testCIStatusFailureTakesPrecedence() {
        // If there's any failure, status should be failure regardless of pending
        let checks = [
            StatusCheck(conclusion: "FAILURE", state: nil),
            StatusCheck(conclusion: nil, state: "PENDING")
        ]
        XCTAssertEqual(CIStatus.from(checks: checks), .failure)
    }

    // MARK: - Review Status Tests

    func testReviewStatusApproved() {
        XCTAssertEqual(ReviewStatus.from(decision: "APPROVED"), .approved)
    }

    func testReviewStatusChangesRequested() {
        XCTAssertEqual(ReviewStatus.from(decision: "CHANGES_REQUESTED"), .changesRequested)
    }

    func testReviewStatusPending() {
        XCTAssertEqual(ReviewStatus.from(decision: "REVIEW_REQUIRED"), .pending)
    }

    func testReviewStatusUnknown() {
        XCTAssertEqual(ReviewStatus.from(decision: nil), .unknown)
        XCTAssertEqual(ReviewStatus.from(decision: "SOME_OTHER_VALUE"), .unknown)
    }

    // MARK: - Bot Detection Tests

    func testIsRealUserExcludesSelf() {
        XCTAssertFalse(isRealUser("myuser", excludingUsername: "myuser"))
        XCTAssertFalse(isRealUser("MyUser", excludingUsername: "myuser"))
        XCTAssertFalse(isRealUser("MYUSER", excludingUsername: "myuser"))
    }

    func testIsRealUserExcludesBotSuffix() {
        XCTAssertFalse(isRealUser("dependabot[bot]", excludingUsername: "me"))
        XCTAssertFalse(isRealUser("github-actions[bot]", excludingUsername: "me"))
        XCTAssertFalse(isRealUser("some-bot", excludingUsername: "me"))
        XCTAssertFalse(isRealUser("SOME-BOT", excludingUsername: "me"))
    }

    func testIsRealUserExcludesCommonBots() {
        XCTAssertFalse(isRealUser("dependabot", excludingUsername: "me"))
        XCTAssertFalse(isRealUser("renovate", excludingUsername: "me"))
        XCTAssertFalse(isRealUser("codecov", excludingUsername: "me"))
        XCTAssertFalse(isRealUser("github-actions", excludingUsername: "me"))
        XCTAssertFalse(isRealUser("mergify", excludingUsername: "me"))
        XCTAssertFalse(isRealUser("semantic-release", excludingUsername: "me"))
        XCTAssertFalse(isRealUser("vercel", excludingUsername: "me"))
        XCTAssertFalse(isRealUser("netlify", excludingUsername: "me"))
    }

    func testIsRealUserAcceptsRealUsers() {
        XCTAssertTrue(isRealUser("john-doe", excludingUsername: "me"))
        XCTAssertTrue(isRealUser("alice123", excludingUsername: "me"))
        XCTAssertTrue(isRealUser("developer", excludingUsername: "me"))
    }

    // MARK: - JSON Decoding Tests

    func testPullRequestDecoding() throws {
        let json = """
        {
            "number": 123,
            "title": "Fix bug",
            "url": "https://github.com/owner/repo/pull/123",
            "updatedAt": "2024-01-15T10:30:00Z",
            "createdAt": "2024-01-14T09:00:00Z",
            "isDraft": false,
            "repository": {"nameWithOwner": "owner/repo"}
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let pr = try decoder.decode(PullRequest.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(pr.number, 123)
        XCTAssertEqual(pr.title, "Fix bug")
        XCTAssertEqual(pr.url, "https://github.com/owner/repo/pull/123")
        XCTAssertEqual(pr.isDraft, false)
        XCTAssertEqual(pr.repository.nameWithOwner, "owner/repo")
        XCTAssertEqual(pr.id, "owner/repo#123")
    }

    func testPullRequestDecodingWithOptionalFields() throws {
        let json = """
        {
            "number": 456,
            "title": "Add feature",
            "url": "https://github.com/owner/repo/pull/456",
            "updatedAt": "2024-01-15T10:30:00Z",
            "repository": {"nameWithOwner": "owner/repo"}
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let pr = try decoder.decode(PullRequest.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(pr.number, 456)
        XCTAssertNil(pr.createdAt)
        XCTAssertEqual(pr.isDraft, false) // defaults to false
    }

    func testReviewRequestDecoding() throws {
        let json = """
        {
            "number": 789,
            "title": "Review this",
            "url": "https://github.com/owner/repo/pull/789",
            "updatedAt": "2024-01-15T10:30:00Z",
            "author": {"login": "contributor"},
            "repository": {"nameWithOwner": "owner/repo"}
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let review = try decoder.decode(ReviewRequest.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(review.number, 789)
        XCTAssertEqual(review.author.login, "contributor")
        XCTAssertEqual(review.id, "owner/repo#789")
    }

    func testNotificationDecoding() throws {
        let json = """
        {
            "reason": "review_requested",
            "title": "PR needs review",
            "url": "https://api.github.com/repos/owner/repo/pulls/123",
            "repo_url": "https://github.com/owner/repo",
            "updated_at": "2024-01-15T10:30:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let notification = try decoder.decode(GitHubNotification.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(notification.reason, "review_requested")
        XCTAssertEqual(notification.title, "PR needs review")
        XCTAssertEqual(notification.repoUrl, "https://github.com/owner/repo")
    }

    func testIssueDecoding() throws {
        let json = """
        {
            "number": 42,
            "title": "Bug report",
            "url": "https://github.com/owner/repo/issues/42",
            "commentsCount": 5,
            "updatedAt": "2024-01-15T10:30:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let issue = try decoder.decode(Issue.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(issue.number, 42)
        XCTAssertEqual(issue.commentsCount, 5)
        XCTAssertEqual(issue.id, "https://github.com/owner/repo/issues/42")
    }
}

// MARK: - Test Support Types
// Minimal recreations of the main types for testing logic

private struct StatusCheck {
    let conclusion: String?
    let state: String?
}

private enum CIStatus: Equatable {
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

private enum ReviewStatus: Equatable {
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

private func isRealUser(_ login: String, excludingUsername: String) -> Bool {
    let lowercased = login.lowercased()

    // Exclude self
    if lowercased == excludingUsername.lowercased() {
        return false
    }

    // Exclude bots (usernames ending with [bot] or -bot)
    if lowercased.hasSuffix("[bot]") || lowercased.hasSuffix("-bot") {
        return false
    }

    // Exclude common bot patterns
    let botPatterns = ["dependabot", "renovate", "codecov", "github-actions", "mergify", "semantic-release", "vercel", "netlify"]
    if botPatterns.contains(where: { lowercased.contains($0) }) {
        return false
    }

    return true
}

// MARK: - Model Types for JSON Decoding Tests

private struct Repository: Codable {
    let nameWithOwner: String
}

private struct Author: Codable {
    let login: String
}

private struct PullRequest: Codable {
    var id: String { "\(repository.nameWithOwner)#\(number)" }

    let number: Int
    let title: String
    let url: String
    let updatedAt: Date
    let createdAt: Date?
    let isDraft: Bool
    let repository: Repository

    enum CodingKeys: String, CodingKey {
        case number, title, url, updatedAt, createdAt, isDraft, repository
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
    }
}

private struct ReviewRequest: Codable {
    var id: String { "\(repository?.nameWithOwner ?? "unknown")#\(number)" }

    let number: Int
    let title: String
    let url: String
    let updatedAt: Date
    let author: Author
    let repository: Repository?
}

private struct GitHubNotification: Codable {
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

private struct Issue: Codable {
    var id: String { url }

    let number: Int
    let title: String
    let url: String
    let commentsCount: Int
    let updatedAt: Date
}
