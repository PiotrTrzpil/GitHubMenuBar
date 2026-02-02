import SwiftUI

// MARK: - Open PR Row

struct OpenPRRow: View {
    let pr: PullRequest
    @EnvironmentObject var service: GitHubService

    private var ciStatus: CIStatus {
        CIStatus.from(checks: pr.statusCheckRollup)
    }

    private var hasConflicts: Bool {
        pr.mergeable == "CONFLICTING" || (pr.attentionReasons?.contains("conflicts") ?? false)
    }

    private var ageColor: Color {
        guard let createdAt = pr.createdAt else { return .green }
        let days = Calendar.current.dateComponents([.day], from: createdAt, to: Date()).day ?? 0

        if days < 1 { return .green }
        if days < 3 { return Color(red: 0.6, green: 0.8, blue: 0.2) } // lime
        if days < 7 { return .yellow }
        return .orange
    }

    var body: some View {
        Button(action: { service.openInBrowser(url: pr.url) }) {
            HStack(alignment: .top, spacing: 8) {
                // Age indicator
                RoundedRectangle(cornerRadius: 2)
                    .fill(ageColor)
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 4) {
                    // Repo and PR number
                    HStack(spacing: 4) {
                        Text(pr.repository.nameWithOwner)
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Text("#\(pr.number)")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        if pr.isDraft {
                            Text("Draft")
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.gray.opacity(0.3))
                                .cornerRadius(3)
                        }

                        Spacer()

                        Text(pr.updatedAt.relativeFormatted)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    // Title
                    Text(pr.title)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .foregroundColor(.primary)

                    // Status badges
                    HStack(spacing: 6) {
                        // CI Status
                        StatusBadge(status: ciStatus, label: pr.failingCheck ?? "CI")

                        // Review progress
                        if let approvals = pr.approvalsCount, let reviewers = pr.reviewersCount, reviewers > 0 {
                            HStack(spacing: 2) {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 9))
                                Text("\(approvals)/\(reviewers)")
                                    .font(.caption2)
                            }
                            .foregroundColor(approvals >= reviewers ? .green : .yellow)
                        }

                        // Comments
                        if let comments = pr.commentsCount, comments > 0 {
                            HStack(spacing: 2) {
                                Image(systemName: "bubble.left")
                                    .font(.system(size: 9))
                                Text("\(comments)")
                                    .font(.caption2)
                            }
                            .foregroundColor(.secondary)
                        }

                        // Conflicts badge
                        if hasConflicts {
                            HStack(spacing: 2) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 9))
                                Text("Conflicts")
                                    .font(.caption2)
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.yellow.opacity(0.2))
                            .foregroundColor(.yellow)
                            .cornerRadius(3)
                        }

                        Spacer()

                        // Attention indicator
                        if pr.needsAttention == true {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 8, height: 8)
                        }
                    }
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Merged PR Row

struct MergedPRRow: View {
    let pr: PullRequest
    @EnvironmentObject var service: GitHubService

    var body: some View {
        Button(action: { service.openInBrowser(url: pr.url) }) {
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.purple)
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(pr.repository.nameWithOwner)
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Text("#\(pr.number)")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Spacer()

                        if let mergedAt = pr.mergedAt {
                            Text(mergedAt.relativeFormatted)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    Text(pr.title)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .foregroundColor(.primary)

                    HStack(spacing: 8) {
                        if let additions = pr.additions {
                            Text("+\(additions)")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                        if let deletions = pr.deletions {
                            Text("-\(deletions)")
                                .font(.caption2)
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Review Request Row

struct ReviewRequestRow: View {
    let review: ReviewRequest
    @EnvironmentObject var service: GitHubService

    var body: some View {
        Button(action: { service.openInBrowser(url: review.url) }) {
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.orange)
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(review.repository?.nameWithOwner ?? "unknown")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Text("#\(review.number)")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Text("@\(review.author.login)")
                            .font(.caption2)
                            .foregroundColor(.orange)

                        Spacer()

                        Text(review.updatedAt.relativeFormatted)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Text(review.title)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .foregroundColor(.primary)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Notification Row

struct NotificationRow: View {
    let notification: GitHubNotification
    @EnvironmentObject var service: GitHubService

    private var icon: (name: String, color: Color) {
        switch notification.reason {
        case "review_requested":
            return ("eye", .purple)
        case "mention":
            return ("bubble.left", .blue)
        case "author":
            return ("arrow.triangle.pull", .green)
        case "ci_activity":
            return ("arrow.clockwise", .yellow)
        case "assign":
            return ("exclamationmark.circle", .orange)
        case "state_change":
            return ("arrow.triangle.merge", .purple)
        default:
            return ("bell", .gray)
        }
    }

    var body: some View {
        Button(action: {
            if let url = notification.url {
                // Convert API URL to web URL
                let webUrl = url
                    .replacingOccurrences(of: "api.github.com/repos", with: "github.com")
                    .replacingOccurrences(of: "/pulls/", with: "/pull/")
                service.openInBrowser(url: webUrl)
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: icon.name)
                    .font(.caption)
                    .foregroundColor(icon.color)
                    .frame(width: 16)

                Text(notification.title)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundColor(.primary)

                Spacer()

                Text(notification.updatedAt.relativeFormatted)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Issue Row

struct IssueRow: View {
    let issue: Issue
    @EnvironmentObject var service: GitHubService

    var body: some View {
        Button(action: { service.openInBrowser(url: issue.url) }) {
            HStack(spacing: 8) {
                Text("#\(issue.number)")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if issue.commentsCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 9))
                        Text("\(issue.commentsCount)")
                            .font(.caption2)
                    }
                    .foregroundColor(.secondary)
                }

                Text(issue.title)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundColor(.primary)

                Spacer()

                Text(issue.updatedAt.relativeFormatted)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: CIStatus
    let label: String

    private var icon: String {
        switch status {
        case .success: return "checkmark.circle"
        case .failure: return "xmark.circle"
        case .pending: return "clock"
        case .unknown: return "questionmark.circle"
        }
    }

    private var color: Color {
        switch status {
        case .success: return .green
        case .failure: return .red
        case .pending: return .yellow
        case .unknown: return .gray
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(status == .failure ? label : "CI")
                .font(.caption2)
                .lineLimit(1)
        }
        .foregroundColor(color)
    }
}
