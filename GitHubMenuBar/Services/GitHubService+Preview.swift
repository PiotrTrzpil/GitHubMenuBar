import Foundation

// MARK: - PR Preview Fetching

extension GitHubService {
    /// Task for delayed clearing of hover state
    private static var clearHoverTask: Task<Void, Never>?

    /// Set the currently hovered PR ID (called with delay from row hover)
    func setHoveredPR(_ prId: String?) {
        // Cancel any pending clear when setting a new PR
        Self.clearHoverTask?.cancel()
        Self.clearHoverTask = nil

        state.previewState.hoveredPRId = prId

        // If setting a new PR, fetch its preview details
        if let prId = prId {
            Task {
                await fetchPreviewDetailsIfNeeded(for: prId)
            }
        }
    }

    /// Clear the hover state (only if neither pane is hovered)
    func clearHoveredPR() {
        // Don't clear if either pane is being hovered
        guard !state.previewState.isPreviewPaneHovered && !state.previewState.isMainPaneHovered else { return }
        // Don't clear if there's a hovered PR (preview is showing)
        guard state.previewState.hoveredPRId != nil else { return }

        scheduleClearHover()
    }

    /// Set whether the main pane is being hovered
    func setMainPaneHovered(_ hovered: Bool) {
        state.previewState.isMainPaneHovered = hovered
        if hovered {
            // Cancel any pending clear
            Self.clearHoverTask?.cancel()
            Self.clearHoverTask = nil
        } else {
            scheduleClearHover()
        }
    }

    /// Set whether the preview pane is being hovered
    func setPreviewPaneHovered(_ hovered: Bool) {
        state.previewState.isPreviewPaneHovered = hovered
        if hovered {
            // Cancel any pending clear
            Self.clearHoverTask?.cancel()
            Self.clearHoverTask = nil
        } else {
            scheduleClearHover()
        }
    }

    /// Schedule a delayed clear of the hover state
    private func scheduleClearHover() {
        // Cancel existing task
        Self.clearHoverTask?.cancel()

        Self.clearHoverTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }

            // Only clear if neither pane is hovered
            if !state.previewState.isMainPaneHovered && !state.previewState.isPreviewPaneHovered {
                state.previewState.hoveredPRId = nil
            }
        }
    }

    /// Fetch preview details if not already cached
    private func fetchPreviewDetailsIfNeeded(for prId: String) async {
        // Already cached?
        if state.previewState.previewCache[prId] != nil {
            return
        }

        // Already loading?
        if state.previewState.loadingPRIds.contains(prId) {
            return
        }

        // Find the PR
        guard let pr = state.openPRs.first(where: { $0.id == prId }) else {
            return
        }

        // Mark as loading
        state.previewState.loadingPRIds.insert(prId)
        state.previewState.errorPRIds.removeValue(forKey: prId)

        do {
            let details = try await fetchPreviewDetails(for: pr)
            state.previewState.previewCache[prId] = details
        } catch {
            state.previewState.errorPRIds[prId] = error.localizedDescription
            print("Failed to fetch preview for PR \(pr.number): \(error)")
        }

        state.previewState.loadingPRIds.remove(prId)
    }

    /// Fetch detailed preview information for a PR
    private func fetchPreviewDetails(for pr: PullRequest) async throws -> PRPreviewDetails {
        // Fetch PR details (files, reviewRequests) and comments concurrently
        async let prDetailsTask = fetchPRFileDetails(for: pr)
        async let commentsTask = fetchRecentComments(for: pr)

        let (prDetails, comments) = try await (prDetailsTask, commentsTask)

        // Extract failed workflows from already-enriched status checks
        let failedWorkflows = extractFailedWorkflows(from: pr)

        // Filter comments that mention the current user
        let mentioningComments = filterMentioningComments(comments, username: state.username)

        return PRPreviewDetails(
            prId: pr.id,
            prUrl: pr.url,
            additions: prDetails.additions,
            deletions: prDetails.deletions,
            changedFilesCount: prDetails.filesCount,
            topChangedFiles: prDetails.topFiles,
            failedWorkflows: failedWorkflows,
            pendingReviewers: prDetails.pendingReviewers,
            completedReviews: prDetails.completedReviews,
            recentMentions: mentioningComments,
            createdAt: prDetails.createdAt,
            updatedAt: prDetails.updatedAt
        )
    }

    // MARK: - PR File Details

    private struct PRFileDetails {
        let additions: Int
        let deletions: Int
        let filesCount: Int
        let topFiles: [ChangedFile]
        let pendingReviewers: [String]
        let completedReviews: [PRReview]
        let createdAt: Date?
        let updatedAt: Date?
    }

    private func fetchPRFileDetails(for pr: PullRequest) async throws -> PRFileDetails {
        let data = try await runGH([
            "pr", "view", String(pr.number),
            "--repo", pr.repository.nameWithOwner,
            "--json", "additions,deletions,files,reviewRequests,latestReviews,createdAt,updatedAt"
        ])

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GitHubError.parseError("Failed to parse PR details")
        }

        let additions = json["additions"] as? Int ?? 0
        let deletions = json["deletions"] as? Int ?? 0

        // Parse dates
        var createdAt: Date?
        var updatedAt: Date?
        if let createdAtStr = json["createdAt"] as? String {
            createdAt = iso8601Formatter.date(from: createdAtStr)
        }
        if let updatedAtStr = json["updatedAt"] as? String {
            updatedAt = iso8601Formatter.date(from: updatedAtStr)
        }

        // Parse files
        var changedFiles: [ChangedFile] = []
        if let files = json["files"] as? [[String: Any]] {
            changedFiles = files.compactMap { file -> ChangedFile? in
                guard let path = file["path"] as? String else { return nil }
                let adds = file["additions"] as? Int ?? 0
                let dels = file["deletions"] as? Int ?? 0
                return ChangedFile(filename: path, additions: adds, deletions: dels)
            }
        }

        // Sort by total changes and take top 5
        let topFiles = changedFiles
            .sorted { $0.totalChanges > $1.totalChanges }
            .prefix(5)
            .map { $0 }

        // Parse pending review requests (who still needs to review)
        var pendingReviewers: [String] = []
        if let reviewRequests = json["reviewRequests"] as? [[String: Any]] {
            pendingReviewers = reviewRequests.compactMap { req -> String? in
                if let login = req["login"] as? String {
                    return login
                } else if let name = req["name"] as? String {
                    return name  // Team name
                }
                return nil
            }
        }

        // Parse completed reviews (latestReviews shows most recent review per person)
        var completedReviews: [PRReview] = []
        if let reviews = json["latestReviews"] as? [[String: Any]] {
            completedReviews = reviews.compactMap { review -> PRReview? in
                guard let author = review["author"] as? [String: Any],
                      let login = author["login"] as? String,
                      let stateStr = review["state"] as? String else {
                    return nil
                }

                let state = PRReview.ReviewState(rawValue: stateStr) ?? .commented
                var submittedAt: Date?
                if let submittedAtStr = review["submittedAt"] as? String {
                    submittedAt = iso8601Formatter.date(from: submittedAtStr)
                }

                return PRReview(author: login, state: state, submittedAt: submittedAt)
            }
        }

        return PRFileDetails(
            additions: additions,
            deletions: deletions,
            filesCount: changedFiles.count,
            topFiles: Array(topFiles),
            pendingReviewers: pendingReviewers,
            completedReviews: completedReviews,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    // MARK: - Comments

    private func fetchRecentComments(for pr: PullRequest) async throws -> [PRComment] {
        let data = try await runGH([
            "api", "repos/\(pr.repository.nameWithOwner)/issues/\(pr.number)/comments"
        ])

        guard let comments = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        // Take last 10 comments, parse them
        return comments.suffix(10).compactMap { comment -> PRComment? in
            guard let user = comment["user"] as? [String: Any],
                  let login = user["login"] as? String,
                  let body = comment["body"] as? String,
                  let createdAtStr = comment["created_at"] as? String,
                  let createdAt = iso8601Formatter.date(from: createdAtStr) else {
                return nil
            }

            let htmlUrl = comment["html_url"] as? String
            return PRComment(author: login, body: body, createdAt: createdAt, url: htmlUrl)
        }
    }

    // MARK: - Workflows

    private func extractFailedWorkflows(from pr: PullRequest) -> [WorkflowRun] {
        guard let checks = pr.statusCheckRollup else { return [] }

        return checks
            .filter { $0.conclusion == "FAILURE" || $0.state == "FAILURE" }
            .compactMap { check -> WorkflowRun? in
                guard let name = check.name else { return nil }
                return WorkflowRun(
                    name: name,
                    conclusion: check.conclusion ?? check.state ?? "failure",
                    url: check.detailsUrl
                )
            }
    }

    // MARK: - Filtering

    private func filterMentioningComments(_ comments: [PRComment], username: String?) -> [PRComment] {
        guard let username = username else { return [] }

        let mention = "@\(username)"
        return comments
            .filter { $0.body.contains(mention) }
            .suffix(3)
            .reversed()  // Most recent first
            .map { $0 }
    }

    // MARK: - Cache Management

    /// Clear the preview cache (call on refresh if needed)
    func clearPreviewCache() {
        state.previewState.previewCache.removeAll()
        state.previewState.errorPRIds.removeAll()
    }

    /// Invalidate cache for a specific PR
    func invalidatePreviewCache(for prId: String) {
        state.previewState.previewCache.removeValue(forKey: prId)
        state.previewState.errorPRIds.removeValue(forKey: prId)
    }
}
