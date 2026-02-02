import Foundation
import Combine
import AppKit

/// Service for fetching GitHub data using the `gh` CLI
@MainActor
final class GitHubService: ObservableObject {
    static let shared = GitHubService()

    @Published private(set) var state = GitHubState()

    private var refreshTimer: Timer?
    private let refreshInterval: TimeInterval = 5 * 60 // 5 minutes

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private init() {
        startAutoRefresh()
    }

    // MARK: - Auto Refresh

    private func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
            }
        }
    }

    // MARK: - Public API

    func refresh() async {
        state.isLoading = true
        state.error = nil

        do {
            // Fetch username first
            if state.username == nil {
                state.username = try await fetchUsername()
            }

            // Fetch all data concurrently
            async let prsResult = fetchMyPRs()
            async let reviewsResult = fetchReviewRequests()
            async let notificationsResult = fetchNotifications(hours: 24)
            async let issuesResult = fetchMyIssues(hours: 24)

            let (prs, reviews, notifications, issues) = try await (
                prsResult, reviewsResult, notificationsResult, issuesResult
            )

            state.openPRs = prs.open
            state.mergedPRs = prs.merged
            state.closedPRs = prs.closed
            state.reviewRequests = reviews
            state.notifications = notifications
            state.issues = issues
            state.lastUpdated = Date()
            state.error = nil

        } catch {
            state.error = error.localizedDescription
            print("GitHub refresh error: \(error)")
        }

        state.isLoading = false
    }

    func openInBrowser(url: String) {
        guard let url = URL(string: url) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - CLI Execution

    private func runGH(_ arguments: [String]) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["gh"] + arguments

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()

                    if process.terminationStatus != 0 {
                        let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                        continuation.resume(throwing: GitHubError.cliError(errorMessage))
                    } else {
                        continuation.resume(returning: data)
                    }
                } catch {
                    continuation.resume(throwing: GitHubError.processError(error.localizedDescription))
                }
            }
        }
    }

    private func runGHJSON<T: Decodable>(_ arguments: [String], as type: T.Type) async throws -> T {
        let data = try await runGH(arguments)

        // Handle empty response
        if data.isEmpty {
            if T.self == [PullRequest].self {
                return [] as! T
            } else if T.self == [ReviewRequest].self {
                return [] as! T
            }
        }

        return try decoder.decode(T.self, from: data)
    }

    // MARK: - Data Fetching

    private func fetchUsername() async throws -> String {
        let data = try await runGH(["api", "user", "--jq", ".login"])
        guard let username = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw GitHubError.parseError("Could not parse username")
        }
        return username
    }

    private func fetchMyPRs(mergedDays: Int = 3) async throws -> (open: [PullRequest], merged: [PullRequest], closed: [PullRequest]) {
        let since = Calendar.current.date(byAdding: .day, value: -mergedDays, to: Date())!
        let sinceStr = ISO8601DateFormatter().string(from: since).prefix(10) // YYYY-MM-DD

        // Fetch open, merged, and closed PRs concurrently
        async let openTask = runGHJSON([
            "search", "prs",
            "--author", "@me",
            "--state", "open",
            "--json", "number,title,url,updatedAt,createdAt,isDraft,repository"
        ], as: [PullRequest].self)

        async let mergedTask = runGHJSON([
            "search", "prs",
            "--author", "@me",
            "--merged",
            "--merged-at", ">=\(sinceStr)",
            "--json", "number,title,url,repository,updatedAt,mergedAt,additions,deletions",
            "--limit", "50"
        ], as: [PullRequest].self)

        async let closedTask = runGHJSON([
            "search", "prs",
            "--author", "@me",
            "--state", "closed",
            "--closed", ">=\(sinceStr)",
            "--json", "number,title,url,repository,updatedAt,closedAt",
            "--limit", "50"
        ], as: [PullRequest].self)

        var (open, merged, closed) = try await (openTask, mergedTask, closedTask)

        // Enrich open PRs with additional details
        open = await enrichOpenPRs(open)

        // Filter out merged PRs from closed list
        let mergedNumbers = Set(merged.map { $0.number })
        closed = closed.filter { !mergedNumbers.contains($0.number) }

        return (open, merged, closed)
    }

    private func enrichOpenPRs(_ prs: [PullRequest]) async -> [PullRequest] {
        await withTaskGroup(of: PullRequest.self) { group in
            for pr in prs {
                group.addTask {
                    await self.enrichPR(pr)
                }
            }

            var enriched: [PullRequest] = []
            for await pr in group {
                enriched.append(pr)
            }
            return enriched.sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    private func enrichPR(_ pr: PullRequest) async -> PullRequest {
        var enriched = pr

        do {
            let detailsData = try await runGH([
                "pr", "view", String(pr.number),
                "--repo", pr.repository.nameWithOwner,
                "--json", "mergeable,reviewDecision,statusCheckRollup,comments,reviews,reviewRequests"
            ])

            if let details = try? JSONSerialization.jsonObject(with: detailsData) as? [String: Any] {
                enriched.mergeable = details["mergeable"] as? String
                enriched.reviewDecision = details["reviewDecision"] as? String

                // Parse status checks
                if let checksData = details["statusCheckRollup"] as? [[String: Any]] {
                    enriched.statusCheckRollup = checksData.compactMap { check in
                        StatusCheck(
                            status: check["status"] as? String,
                            state: check["state"] as? String,
                            conclusion: check["conclusion"] as? String,
                            name: check["name"] as? String
                        )
                    }
                }

                // Count comments and reviews
                let comments = details["comments"] as? [[String: Any]] ?? []
                let reviews = details["reviews"] as? [[String: Any]] ?? []
                let reviewRequests = details["reviewRequests"] as? [[String: Any]] ?? []

                enriched.commentsCount = comments.count
                enriched.approvalsCount = reviews.filter { ($0["state"] as? String) == "APPROVED" }.count
                enriched.reviewersCount = Set(reviews.compactMap { ($0["author"] as? [String: Any])?["login"] as? String }).count + reviewRequests.count

                // Find failing check name
                if let failingCheck = enriched.statusCheckRollup?.first(where: {
                    $0.conclusion == "FAILURE" || $0.state == "FAILURE"
                }) {
                    enriched.failingCheck = failingCheck.name
                }

                // Compute attention status
                var reasons: [String] = []
                if enriched.mergeable == "CONFLICTING" {
                    reasons.append("conflicts")
                }
                if CIStatus.from(checks: enriched.statusCheckRollup) == .failure {
                    reasons.append("ci_failure")
                }

                enriched.needsAttention = !reasons.isEmpty
                enriched.attentionReasons = reasons
            }
        } catch {
            print("Failed to enrich PR \(pr.number): \(error)")
        }

        return enriched
    }

    private func fetchReviewRequests() async throws -> [ReviewRequest] {
        try await runGHJSON([
            "search", "prs",
            "--review-requested", "@me",
            "--state", "open",
            "--json", "number,title,url,author,updatedAt,repository"
        ], as: [ReviewRequest].self)
    }

    private func fetchNotifications(hours: Int) async throws -> [GitHubNotification] {
        let since = Calendar.current.date(byAdding: .hour, value: -hours, to: Date())!
        let sinceStr = ISO8601DateFormatter().string(from: since)

        let jqFilter = """
        .[] | select(.updated_at > "\(sinceStr)") | {reason, title: .subject.title, url: .subject.url, updated_at: .updated_at}
        """

        let data = try await runGH(["api", "notifications", "--jq", jqFilter])

        // Parse line-delimited JSON
        let lines = String(data: data, encoding: .utf8)?.split(separator: "\n") ?? []
        return lines.compactMap { line in
            guard let lineData = line.data(using: .utf8) else { return nil }
            return try? decoder.decode(GitHubNotification.self, from: lineData)
        }
    }

    private func fetchMyIssues(hours: Int) async throws -> [Issue] {
        let since = Calendar.current.date(byAdding: .hour, value: -hours, to: Date())!

        let issues: [Issue] = try await runGHJSON([
            "search", "issues",
            "--author", "@me",
            "--state", "open",
            "--json", "number,title,url,commentsCount,updatedAt"
        ], as: [Issue].self)

        // Filter to recent activity
        return issues.filter { $0.updatedAt > since }
    }
}

// MARK: - Errors

enum GitHubError: LocalizedError {
    case cliError(String)
    case processError(String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .cliError(let message):
            if message.contains("gh auth") || message.contains("401") {
                return "GitHub authentication required. Run 'gh auth login' in Terminal."
            }
            return "GitHub CLI error: \(message)"
        case .processError(let message):
            return "Process error: \(message)"
        case .parseError(let message):
            return "Parse error: \(message)"
        }
    }
}
