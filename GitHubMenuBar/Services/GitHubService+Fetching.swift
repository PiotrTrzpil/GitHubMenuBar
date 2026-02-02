import Foundation

// MARK: - Data Fetching

extension GitHubService {
    func fetchUsername() async throws -> String {
        let data = try await runGH(["api", "user", "--jq", ".login"])
        guard let username = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw GitHubError.parseError("Could not parse username")
        }
        return username
    }

    func fetchMyPRs(mergedDays: Int) async throws -> (open: [PullRequest], merged: [PullRequest], closed: [PullRequest]) {
        let since = Calendar.current.date(byAdding: .day, value: -mergedDays, to: Date()) ?? Date()
        let sinceStr = iso8601Formatter.string(from: since).prefix(10) // YYYY-MM-DD

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
            "--json", "number,title,url,repository,updatedAt,closedAt",
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

        // Enrich merged PRs and filter to only those with external activity
        merged = await enrichMergedPRs(merged)
        merged = merged.filter { $0.hasExternalActivity == true }

        // Filter out merged PRs from closed list
        let mergedNumbers = Set(merged.map { $0.number })
        closed = closed.filter { !mergedNumbers.contains($0.number) }

        return (open, merged, closed)
    }

    func fetchReviewRequests() async throws -> [ReviewRequest] {
        try await runGHJSON([
            "search", "prs",
            "--review-requested", "@me",
            "--state", "open",
            "--json", "number,title,url,author,updatedAt,repository"
        ], as: [ReviewRequest].self)
    }

    func fetchNotifications(hours: Int) async throws -> [GitHubNotification] {
        let since = Calendar.current.date(byAdding: .hour, value: -hours, to: Date()) ?? Date()
        let sinceStr = iso8601Formatter.string(from: since)

        let jqFilter = """
        .[] | select(.updated_at > "\(sinceStr)") | {reason, title: .subject.title, url: .subject.url, repo_url: .repository.html_url, updated_at: .updated_at}
        """

        let data = try await runGH(["api", "notifications", "--jq", jqFilter])

        // Parse line-delimited JSON
        let lines = String(data: data, encoding: .utf8)?.split(separator: "\n") ?? []
        return lines.compactMap { line in
            guard let lineData = line.data(using: .utf8) else { return nil }
            return try? decoder.decode(GitHubNotification.self, from: lineData)
        }
    }

    func fetchMyIssues(hours: Int) async throws -> [Issue] {
        let since = Calendar.current.date(byAdding: .hour, value: -hours, to: Date()) ?? Date()

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
