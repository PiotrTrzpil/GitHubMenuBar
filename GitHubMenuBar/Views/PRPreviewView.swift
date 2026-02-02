import SwiftUI

// MARK: - PR Preview View

struct PRPreviewView: View {
    let pr: PullRequest
    @Environment(GitHubService.self) var service

    private var previewState: PRPreviewState {
        service.state.previewState
    }

    private var preview: PRPreviewDetails? {
        previewState.previewCache[pr.id]
    }

    private var isLoading: Bool {
        previewState.loadingPRIds.contains(pr.id)
    }

    private var error: String? {
        previewState.errorPRIds[pr.id]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            PreviewHeader(pr: pr)

            Divider()
                .padding(.vertical, 8)

            // Content
            if isLoading {
                LoadingPreview()
            } else if let error = error {
                ErrorPreview(message: error)
            } else if let preview = preview {
                PreviewContent(preview: preview, username: service.state.username)
            } else {
                LoadingPreview()
            }

            Spacer()
        }
        .padding(12)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { hovering in
            service.setPreviewPaneHovered(hovering)
        }
    }
}

// MARK: - Preview Header

private struct PreviewHeader: View {
    let pr: PullRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(pr.repository.nameWithOwner)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("#\(pr.number)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()
            }

            Text(pr.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Loading State

private struct LoadingPreview: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Loading preview...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Error State

private struct ErrorPreview: View {
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundColor(AppColors.warning)

            Text("Failed to load preview")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview Content

private struct PreviewContent: View {
    let preview: PRPreviewDetails
    let username: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Changes Summary
                ChangesSummarySection(preview: preview)

                // Reviews Section (completed + pending)
                if !preview.completedReviews.isEmpty || !preview.pendingReviewers.isEmpty {
                    ReviewsSection(
                        completedReviews: preview.completedReviews,
                        pendingReviewers: preview.pendingReviewers
                    )
                }

                // Failed Workflows
                if !preview.failedWorkflows.isEmpty {
                    FailedWorkflowsSection(workflows: preview.failedWorkflows)
                }

                // Top Changed Files
                if !preview.topChangedFiles.isEmpty {
                    ChangedFilesSection(files: preview.topChangedFiles)
                }

                // Recent Mentions
                if !preview.recentMentions.isEmpty {
                    MentionsSection(comments: preview.recentMentions, username: username)
                }
            }
        }
    }
}

// MARK: - Changes Summary Section

private struct ChangesSummarySection: View {
    let preview: PRPreviewDetails

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PreviewSectionHeader(title: "Changes", icon: "doc.text")

            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Text("+\(preview.additions)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(AppColors.additions)
                }

                HStack(spacing: 4) {
                    Text("-\(preview.deletions)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(AppColors.deletions)
                }

                Text("\(preview.changedFilesCount) files")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Changed Files Section

private struct ChangedFilesSection: View {
    let files: [ChangedFile]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PreviewSectionHeader(title: "Top Changed Files", icon: "doc.badge.plus")

            VStack(alignment: .leading, spacing: 4) {
                ForEach(files) { file in
                    HStack(spacing: 6) {
                        // File icon based on extension
                        Image(systemName: fileIcon(for: file.filename))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(width: 12)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(file.shortName)
                                .font(.caption)
                                .lineLimit(1)

                            if let dir = file.directory {
                                Text(dir)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer()

                        HStack(spacing: 4) {
                            Text("+\(file.additions)")
                                .font(.caption2)
                                .foregroundColor(AppColors.additions)

                            Text("-\(file.deletions)")
                                .font(.caption2)
                                .foregroundColor(AppColors.deletions)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func fileIcon(for filename: String) -> String {
        let ext = filename.components(separatedBy: ".").last?.lowercased() ?? ""
        switch ext {
        case "swift", "rs", "go", "py", "js", "ts", "rb", "java", "kt", "c", "cpp", "h":
            return "chevron.left.forwardslash.chevron.right"
        case "json", "yaml", "yml", "toml", "xml", "plist":
            return "curlybraces"
        case "md", "txt", "rst":
            return "doc.text"
        case "css", "scss", "less":
            return "paintbrush"
        case "png", "jpg", "jpeg", "gif", "svg", "ico":
            return "photo"
        default:
            return "doc"
        }
    }
}

// MARK: - Failed Workflows Section

private struct FailedWorkflowsSection: View {
    let workflows: [WorkflowRun]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PreviewSectionHeader(title: "Failed Checks", icon: "xmark.circle")

            VStack(alignment: .leading, spacing: 4) {
                ForEach(workflows) { workflow in
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(AppColors.ciFailure)

                        Text(workflow.name)
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

// MARK: - Reviews Section (Completed + Pending)

private struct ReviewsSection: View {
    let completedReviews: [PRReview]
    let pendingReviewers: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PreviewSectionHeader(title: "Reviews", icon: "person.2")

            VStack(alignment: .leading, spacing: 6) {
                // Completed reviews
                ForEach(completedReviews) { review in
                    HStack(spacing: 6) {
                        Image(systemName: review.state.icon)
                            .font(.caption2)
                            .foregroundColor(reviewStateColor(review.state))

                        Text(review.author)
                            .font(.caption)

                        Text(review.state.displayName)
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Spacer()

                        if let submittedAt = review.submittedAt {
                            Text(submittedAt.relativeFormatted)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Pending reviewers
                ForEach(pendingReviewers, id: \.self) { reviewer in
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.caption2)
                            .foregroundColor(AppColors.ciPending)

                        Text(reviewer)
                            .font(.caption)

                        Text("Pending")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Spacer()
                    }
                }
            }
        }
    }

    private func reviewStateColor(_ state: PRReview.ReviewState) -> Color {
        switch state {
        case .approved:
            return AppColors.success
        case .changesRequested:
            return AppColors.ciFailure
        case .commented:
            return .secondary
        case .pending:
            return AppColors.ciPending
        case .dismissed:
            return .secondary
        }
    }
}

// MARK: - Mentions Section

private struct MentionsSection: View {
    let comments: [PRComment]
    let username: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PreviewSectionHeader(title: "Mentions", icon: "at")

            VStack(alignment: .leading, spacing: 8) {
                ForEach(comments) { comment in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("@\(comment.author)")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(AppColors.mention)

                            Spacer()

                            Text(comment.createdAt.relativeFormatted)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Text(highlightMention(in: comment.preview, username: username))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    .padding(8)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(6)
                }
            }
        }
    }

    private func highlightMention(in text: String, username: String?) -> AttributedString {
        var attributed = AttributedString(text)
        guard let username = username else { return attributed }

        let mention = "@\(username)"
        if let range = attributed.range(of: mention, options: .caseInsensitive) {
            attributed[range].foregroundColor = AppColors.mention
            attributed[range].font = .caption.bold()
        }
        return attributed
    }
}

// MARK: - Section Header

private struct PreviewSectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
        }
    }
}
