import Foundation

// MARK: - PR Enrichment

extension GitHubService {
    func enrichOpenPRs(_ prs: [PullRequest]) async -> [PullRequest] {
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

    func enrichMergedPRs(_ prs: [PullRequest]) async -> [PullRequest] {
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

    func checkExternalActivity(_ pr: PullRequest, username: String) async -> PullRequest {
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
    func isRealUser(_ login: String, excludingUsername: String) -> Bool {
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

    func enrichPR(_ pr: PullRequest) async -> PullRequest {
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
                            name: check["name"] as? String,
                            detailsUrl: check["detailsUrl"] as? String
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
}
