import SwiftUI

// MARK: - Open PR Row

struct OpenPRRow: View {
    let pr: PullRequest
    @EnvironmentObject var service: GitHubService
    @State private var isHovered = false

    private var isMuted: Bool {
        service.isMuted(pr.id)
    }

    private var ciStatus: CIStatus {
        CIStatus.from(checks: pr.statusCheckRollup)
    }

    private var hasConflicts: Bool {
        pr.mergeable == "CONFLICTING" || (pr.attentionReasons?.contains("conflicts") ?? false)
    }

    private var ageColor: Color {
        guard let createdAt = pr.createdAt else { return AppColors.ageFresh }
        let days = Calendar.current.dateComponents([.day], from: createdAt, to: Date()).day ?? 0

        if days < 1 { return AppColors.ageFresh }
        if days < 3 { return AppColors.ageRecent }
        if days < 7 { return AppColors.ageModerate }
        return AppColors.ageOld
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main clickable area
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
                                    .background(AppColors.draft.opacity(0.3))
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
                                .foregroundColor(approvals >= reviewers ? AppColors.success : AppColors.ciPending)
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
                                .background(AppColors.conflict.opacity(0.2))
                                .foregroundColor(AppColors.conflict)
                                .cornerRadius(3)
                            }

                            Spacer()

                            // Mute button (shown on hover or if muted)
                            if isHovered || isMuted {
                                Button(action: { service.toggleMute(pr.id) }) {
                                    ZStack {
                                        Image(systemName: "bell")
                                            .font(.system(size: 10))
                                        // Diagonal slash line (always shown)
                                        Rectangle()
                                            .fill(isMuted ? AppColors.muted : Color.primary)
                                            .frame(width: 14, height: 1.5)
                                            .rotationEffect(.degrees(-45))
                                    }
                                    .frame(width: 20, height: 20)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(isMuted ? AppColors.muted : .secondary)
                                .help(isMuted ? "Unmute" : "Mute")
                            }

                            // Attention indicator (dimmed if muted)
                            if pr.needsAttention == true {
                                Circle()
                                    .fill(AppColors.attention)
                                    .opacity(isMuted ? 0.3 : 1.0)
                                    .frame(width: 8, height: 8)
                            }
                        }
                    }
                }
                .padding(8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(AppColors.cardBackground(hovered: isHovered))
        .cornerRadius(6)
        .onHover { isHovered = $0 }
        .opacity(isMuted ? 0.6 : 1.0)
    }
}

// MARK: - Merged PR Row

struct MergedPRRow: View {
    let pr: PullRequest
    @EnvironmentObject var service: GitHubService
    @State private var isHovered = false

    var body: some View {
        Button(action: { service.openInBrowser(url: pr.url) }) {
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(AppColors.mergedPRs)
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
                                .foregroundColor(AppColors.additions)
                        }
                        if let deletions = pr.deletions {
                            Text("-\(deletions)")
                                .font(.caption2)
                                .foregroundColor(AppColors.deletions)
                        }
                    }
                }
            }
            .padding(8)
            .background(AppColors.cardBackground(hovered: isHovered))
            .cornerRadius(6)
            .onHover { isHovered = $0 }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Review Request Row

struct ReviewRequestRow: View {
    let review: ReviewRequest
    @EnvironmentObject var service: GitHubService
    @State private var isHovered = false

    var body: some View {
        Button(action: { service.openInBrowser(url: review.url) }) {
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(AppColors.reviewRequests)
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
                            .foregroundColor(AppColors.reviewRequests)

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
            .background(AppColors.cardBackground(hovered: isHovered))
            .cornerRadius(6)
            .onHover { isHovered = $0 }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Notification Row

struct NotificationRow: View {
    let notification: GitHubNotification
    @EnvironmentObject var service: GitHubService
    @State private var isHovered = false

    private var icon: (name: String, color: Color) {
        switch notification.reason {
        case "review_requested":
            return ("eye", AppColors.reviewRequested)
        case "mention":
            return ("bubble.left", AppColors.mention)
        case "author":
            return ("arrow.triangle.pull", AppColors.author)
        case "ci_activity":
            return ("arrow.clockwise", AppColors.ciActivity)
        case "assign":
            return ("exclamationmark.circle", AppColors.assign)
        case "state_change":
            return ("arrow.triangle.merge", AppColors.stateChange)
        default:
            return ("bell", AppColors.defaultNotification)
        }
    }

    private var webUrl: String? {
        if let url = notification.url {
            // Convert API URL to web URL
            return url
                .replacingOccurrences(of: "api.github.com/repos", with: "github.com")
                .replacingOccurrences(of: "/pulls/", with: "/pull/")
        } else if let repoUrl = notification.repoUrl {
            // Fallback to repo URL, with /actions suffix for CI activity
            if notification.reason == "ci_activity" {
                return "\(repoUrl)/actions"
            }
            return repoUrl
        }
        return nil
    }

    var body: some View {
        Button(action: {
            if let url = webUrl {
                service.openInBrowser(url: url)
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
            .background(AppColors.notificationBackground(hovered: isHovered))
            .cornerRadius(4)
            .onHover { isHovered = $0 }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Issue Row

struct IssueRow: View {
    let issue: Issue
    @EnvironmentObject var service: GitHubService
    @State private var isHovered = false

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
            .background(AppColors.cardBackground(hovered: isHovered))
            .cornerRadius(6)
            .onHover { isHovered = $0 }
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
        case .success: return AppColors.ciSuccess
        case .failure: return AppColors.ciFailure
        case .pending: return AppColors.ciPending
        case .unknown: return AppColors.ciUnknown
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
