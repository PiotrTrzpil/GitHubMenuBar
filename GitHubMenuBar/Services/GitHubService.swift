import Foundation
import Combine
import AppKit

/// Known paths where the GitHub CLI binary might be installed
enum GitHubCLI {
    static let possiblePaths = [
        "/opt/homebrew/bin/gh",  // Apple Silicon Homebrew
        "/usr/local/bin/gh",      // Intel Homebrew
        "/run/current-system/sw/bin/gh",  // NixOS
        "/etc/profiles/per-user/\(NSUserName())/bin/gh"  // Nix home-manager
    ]

    /// Find the first available gh binary path
    static var path: String? {
        possiblePaths.first { FileManager.default.fileExists(atPath: $0) }
    }
}

/// Service for fetching GitHub data using the `gh` CLI
@MainActor
final class GitHubService: ObservableObject {
    static let shared = GitHubService()

    @Published private(set) var state = GitHubState()
    @Published private(set) var mutedPRIds: Set<String> = []

    // Tracks when each PR was muted (for auto-unmute feature)
    private var mutedPRTimestamps: [String: Date] = [:]

    private var refreshTimer: Timer?
    private var settingsObserver: NSObjectProtocol?
    private let mutedPRsKey = "mutedPRIds"
    private let mutedTimestampsKey = "mutedPRTimestamps"

    // Auto-unmute settings (all default to true)
    private var autoUnmuteOnActivity: Bool {
        UserDefaults.standard.object(forKey: "autoUnmuteOnActivity") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "autoUnmuteOnActivity")
    }
    private var autoUnmuteOnlyHumans: Bool {
        UserDefaults.standard.object(forKey: "autoUnmuteOnlyHumans") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "autoUnmuteOnlyHumans")
    }
    private var autoUnmuteOnlyMentions: Bool {
        UserDefaults.standard.object(forKey: "autoUnmuteOnlyMentions") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "autoUnmuteOnlyMentions")
    }

    /// Refresh interval in minutes, read from UserDefaults
    private var refreshIntervalMinutes: Int {
        let interval = UserDefaults.standard.integer(forKey: "refreshInterval")
        return interval > 0 ? interval : 5 // Default to 5 minutes
    }

    /// Number of days to show merged PRs, read from UserDefaults
    private var mergedDays: Int {
        let days = UserDefaults.standard.integer(forKey: "mergedDays")
        return days > 0 ? days : 3 // Default to 3 days
    }

    /// Number of hours to show notifications, read from UserDefaults
    private var notificationHours: Int {
        let hours = UserDefaults.standard.integer(forKey: "notificationHours")
        return hours > 0 ? hours : 24 // Default to 24 hours
    }

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private let iso8601Formatter = ISO8601DateFormatter()

    private init() {
        loadMutedPRs()
        startAutoRefresh()
        observeSettingsChanges()
    }

    // MARK: - Muted PRs

    private func loadMutedPRs() {
        if let saved = UserDefaults.standard.array(forKey: mutedPRsKey) as? [String] {
            mutedPRIds = Set(saved)
        }
        if let timestamps = UserDefaults.standard.dictionary(forKey: mutedTimestampsKey) as? [String: Double] {
            mutedPRTimestamps = timestamps.mapValues { Date(timeIntervalSince1970: $0) }
        }
    }

    private func saveMutedPRs() {
        UserDefaults.standard.set(Array(mutedPRIds), forKey: mutedPRsKey)
        let timestamps = mutedPRTimestamps.mapValues { $0.timeIntervalSince1970 }
        UserDefaults.standard.set(timestamps, forKey: mutedTimestampsKey)
    }

    func isMuted(_ prId: String) -> Bool {
        mutedPRIds.contains(prId)
    }

    func toggleMute(_ prId: String) {
        if mutedPRIds.contains(prId) {
            mutedPRIds.remove(prId)
            mutedPRTimestamps.removeValue(forKey: prId)
        } else {
            mutedPRIds.insert(prId)
            mutedPRTimestamps[prId] = Date()
        }
        saveMutedPRs()
    }

    /// Unmute a PR (used by auto-unmute feature)
    private func unmute(_ prId: String) {
        mutedPRIds.remove(prId)
        mutedPRTimestamps.removeValue(forKey: prId)
        saveMutedPRs()
    }

    func unmuteClosed() {
        // Remove muted IDs for PRs that are no longer open
        let openIds = Set(state.openPRs.map { $0.id })
        let closedMuted = mutedPRIds.subtracting(openIds)
        if !closedMuted.isEmpty {
            mutedPRIds.subtract(closedMuted)
            for id in closedMuted {
                mutedPRTimestamps.removeValue(forKey: id)
            }
            saveMutedPRs()
        }
    }

    /// Check muted PRs for new activity and auto-unmute if enabled
    private func checkAutoUnmute(for prs: [PullRequest]) async {
        guard autoUnmuteOnActivity else { return }
        guard let username = state.username else { return }

        // Find muted PRs that might have new activity
        let mutedPRs = prs.filter { mutedPRIds.contains($0.id) }

        for pr in mutedPRs {
            guard let muteTime = mutedPRTimestamps[pr.id] else { continue }

            // Check if PR was updated after mute time
            if pr.updatedAt > muteTime {
                // Check for qualifying new activity
                if await hasQualifyingNewActivity(pr: pr, since: muteTime, username: username) {
                    unmute(pr.id)
                    print("Auto-unmuted PR \(pr.number) due to new activity")
                }
            }
        }
    }

    /// Check if a PR has new activity that qualifies for auto-unmute
    private func hasQualifyingNewActivity(pr: PullRequest, since muteTime: Date, username: String) async -> Bool {
        do {
            // Fetch comments and reviews using REST API
            async let commentsTask = runGH([
                "api", "repos/\(pr.repository.nameWithOwner)/issues/\(pr.number)/comments"
            ])
            async let reviewsTask = runGH([
                "api", "repos/\(pr.repository.nameWithOwner)/pulls/\(pr.number)/reviews"
            ])

            let (commentsData, reviewsData) = try await (commentsTask, reviewsTask)

            let comments = (try? JSONSerialization.jsonObject(with: commentsData)) as? [[String: Any]] ?? []
            let reviews = (try? JSONSerialization.jsonObject(with: reviewsData)) as? [[String: Any]] ?? []

            // Check comments
            for comment in comments {
                guard let createdAtStr = comment["created_at"] as? String,
                      let createdAt = iso8601Formatter.date(from: createdAtStr),
                      createdAt > muteTime else { continue }

                guard let user = comment["user"] as? [String: Any],
                      let login = user["login"] as? String,
                      let type = user["type"] as? String else { continue }

                // Skip self
                if login.lowercased() == username.lowercased() { continue }

                // Check bot filter
                if autoUnmuteOnlyHumans && type != "User" { continue }
                if autoUnmuteOnlyHumans && !isRealUser(login, excludingUsername: username) { continue }

                // Check mentions filter
                if autoUnmuteOnlyMentions {
                    let body = comment["body"] as? String ?? ""
                    if !body.contains("@\(username)") { continue }
                }

                // This comment qualifies
                return true
            }

            // Check reviews
            for review in reviews {
                guard let submittedAtStr = review["submitted_at"] as? String,
                      let submittedAt = iso8601Formatter.date(from: submittedAtStr),
                      submittedAt > muteTime else { continue }

                guard let user = review["user"] as? [String: Any],
                      let login = user["login"] as? String,
                      let type = user["type"] as? String else { continue }

                // Skip self
                if login.lowercased() == username.lowercased() { continue }

                // Check bot filter
                if autoUnmuteOnlyHumans && type != "User" { continue }
                if autoUnmuteOnlyHumans && !isRealUser(login, excludingUsername: username) { continue }

                // Check mentions filter - reviews don't really have mentions, so if onlyMentions is on,
                // we check the review body
                if autoUnmuteOnlyMentions {
                    let body = review["body"] as? String ?? ""
                    if !body.contains("@\(username)") { continue }
                }

                // This review qualifies
                return true
            }

            return false
        } catch {
            print("Failed to check activity for auto-unmute on PR \(pr.number): \(error)")
            return false
        }
    }

    // MARK: - Auto Refresh

    private func startAutoRefresh() {
        refreshTimer?.invalidate()
        let interval = TimeInterval(refreshIntervalMinutes * 60)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
            }
        }
    }

    private func observeSettingsChanges() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Restart timer with new interval when settings change
            self?.startAutoRefresh()
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
            async let prsResult = fetchMyPRs(mergedDays: mergedDays)
            async let reviewsResult = fetchReviewRequests()
            async let notificationsResult = fetchNotifications(hours: notificationHours)
            async let issuesResult = fetchMyIssues(hours: notificationHours)

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

            // Clean up muted IDs for closed PRs
            unmuteClosed()

            // Check for auto-unmute on new activity
            await checkAutoUnmute(for: prs.open)

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

                // Find gh binary - GUI apps don't inherit shell PATH
                guard let ghPath = GitHubCLI.path else {
                    continuation.resume(throwing: GitHubError.cliError("GitHub CLI not found. Install with: brew install gh"))
                    return
                }

                process.executableURL = URL(fileURLWithPath: ghPath)
                process.arguments = arguments

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

    private func enrichMergedPRs(_ prs: [PullRequest]) async -> [PullRequest] {
        guard let username = state.username else { return prs }

        return await withTaskGroup(of: PullRequest.self) { group in
            for pr in prs {
                group.addTask {
                    await self.checkExternalActivity(pr, username: username)
                }
            }

            var enriched: [PullRequest] = []
            for await pr in group {
                enriched.append(pr)
            }
            return enriched.sorted { ($0.mergedAt ?? $0.updatedAt) > ($1.mergedAt ?? $1.updatedAt) }
        }
    }

    private func checkExternalActivity(_ pr: PullRequest, username: String) async -> PullRequest {
        var enriched = pr

        do {
            // Use REST API which properly returns "type" field to identify bots
            async let commentsTask = runGH([
                "api", "repos/\(pr.repository.nameWithOwner)/issues/\(pr.number)/comments"
            ])
            async let reviewsTask = runGH([
                "api", "repos/\(pr.repository.nameWithOwner)/pulls/\(pr.number)/reviews"
            ])

            let (commentsData, reviewsData) = try await (commentsTask, reviewsTask)

            let comments = (try? JSONSerialization.jsonObject(with: commentsData)) as? [[String: Any]] ?? []
            let reviews = (try? JSONSerialization.jsonObject(with: reviewsData)) as? [[String: Any]] ?? []

            // Check for comments from real users (not bots, not self)
            // REST API uses "user" instead of "author", and includes "type" field
            let hasExternalComments = comments.contains { comment in
                guard let user = comment["user"] as? [String: Any],
                      let login = user["login"] as? String,
                      let type = user["type"] as? String else { return false }
                return type == "User" && isRealUser(login, excludingUsername: username)
            }

            // Check for reviews from real users (not bots, not self)
            let hasExternalReviews = reviews.contains { review in
                guard let user = review["user"] as? [String: Any],
                      let login = user["login"] as? String,
                      let type = user["type"] as? String else { return false }
                return type == "User" && isRealUser(login, excludingUsername: username)
            }

            enriched.hasExternalActivity = hasExternalComments || hasExternalReviews
        } catch {
            print("Failed to check activity for PR \(pr.number): \(error)")
            enriched.hasExternalActivity = false
        }

        return enriched
    }

    /// Check if a username is a real user (not a bot and not the excluded user)
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

    private func fetchMyIssues(hours: Int) async throws -> [Issue] {
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
