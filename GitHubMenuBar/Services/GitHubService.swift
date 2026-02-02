import Foundation
import AppKit

/// Service for fetching GitHub data using the `gh` CLI
@MainActor
@Observable
final class GitHubService {
    static let shared = GitHubService()

    // Note: internal set needed for extensions in other files
    var state = GitHubState()
    let mutedPRs = MutedPRsManager.shared

    private var refreshTimer: Timer?
    private var settingsObserver: NSObjectProtocol?

    // MARK: - Settings

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

    // MARK: - Shared Utilities

    let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    let iso8601Formatter = ISO8601DateFormatter()

    // MARK: - Initialization

    private init() {
        startAutoRefresh()
        observeSettingsChanges()
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
            Task { @MainActor in
                self?.startAutoRefresh()
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

            // Check for sound-worthy events
            SoundManager.shared.checkAndPlaySounds(for: state)

            // Clean up muted IDs for closed PRs
            let openIds = Set(state.openPRs.map { $0.id })
            mutedPRs.unmuteClosed(openPRIds: openIds)

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

    // MARK: - Muting Convenience

    func isMuted(_ prId: String) -> Bool {
        mutedPRs.isMuted(prId)
    }

    func toggleMute(_ prId: String) {
        mutedPRs.toggleMute(prId)
    }

    var mutedPRIds: Set<String> {
        mutedPRs.mutedPRIds
    }

    // MARK: - Auto-Unmute

    /// Check muted PRs for new activity and auto-unmute if enabled
    private func checkAutoUnmute(for prs: [PullRequest]) async {
        guard mutedPRs.autoUnmuteOnActivity else { return }
        guard let username = state.username else { return }

        // Find muted PRs that might have new activity
        let mutedPRsList = prs.filter { mutedPRs.isMuted($0.id) }

        for pr in mutedPRsList {
            guard let muteTime = mutedPRs.getMuteTimestamp(pr.id) else { continue }

            // Check if PR was updated after mute time
            if pr.updatedAt > muteTime {
                // Check for qualifying new activity
                if await hasQualifyingNewActivity(pr: pr, since: muteTime, username: username) {
                    mutedPRs.unmute(pr.id)
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
                if mutedPRs.autoUnmuteOnlyHumans && type != "User" { continue }
                if mutedPRs.autoUnmuteOnlyHumans && !isRealUser(login, excludingUsername: username) { continue }

                // Check mentions filter
                if mutedPRs.autoUnmuteOnlyMentions {
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
                if mutedPRs.autoUnmuteOnlyHumans && type != "User" { continue }
                if mutedPRs.autoUnmuteOnlyHumans && !isRealUser(login, excludingUsername: username) { continue }

                // Check mentions filter - reviews don't really have mentions, so if onlyMentions is on,
                // we check the review body
                if mutedPRs.autoUnmuteOnlyMentions {
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
}
