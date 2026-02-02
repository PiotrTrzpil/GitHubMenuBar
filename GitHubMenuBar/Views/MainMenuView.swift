import SwiftUI

struct MainMenuView: View {
    @EnvironmentObject var service: GitHubService

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HeaderView()

            Divider()

            // Content
            if service.state.isLoading && service.state.lastUpdated == nil {
                LoadingView()
            } else if let error = service.state.error {
                ErrorView(error: error)
            } else {
                ContentScrollView()
            }

            Divider()

            // Footer
            FooterView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Header

struct HeaderView: View {
    @EnvironmentObject var service: GitHubService

    var body: some View {
        HStack {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.title2)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("GitHub Activity")
                    .font(.headline)

                if let username = service.state.username {
                    Text("@\(username)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if service.state.isLoading {
                ProgressView()
                    .scaleEffect(0.7)
            } else {
                Button(action: {
                    Task { await service.refresh() }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.body)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("Refresh")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }
}

// MARK: - Content

struct ContentScrollView: View {
    @EnvironmentObject var service: GitHubService
    @AppStorage("mergedDays") private var mergedDays = 3
    @AppStorage("notificationHours") private var notificationHours = 24

    private var mergedTitle: String {
        mergedDays == 1 ? "Merged (1 day)" : "Merged (\(mergedDays) days)"
    }

    private var notificationTitle: String {
        "Notifications (\(notificationHours)h)"
    }

    private var issuesTitle: String {
        "My Issues (\(notificationHours)h)"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Open PRs
                if !service.state.openPRs.isEmpty {
                    SectionView(
                        title: "Open PRs",
                        count: service.state.openPRs.count,
                        color: AppColors.openPRs
                    ) {
                        ForEach(service.state.openPRs) { pr in
                            OpenPRRow(pr: pr)
                        }
                    }
                }

                // Review Requests
                if !service.state.reviewRequests.isEmpty {
                    SectionView(
                        title: "Review Requests",
                        count: service.state.reviewRequests.count,
                        color: AppColors.reviewRequests
                    ) {
                        ForEach(service.state.reviewRequests) { review in
                            ReviewRequestRow(review: review)
                        }
                    }
                }

                // Merged PRs
                if !service.state.mergedPRs.isEmpty {
                    SectionView(
                        title: mergedTitle,
                        count: service.state.mergedPRs.count,
                        color: AppColors.mergedPRs
                    ) {
                        ForEach(service.state.mergedPRs) { pr in
                            MergedPRRow(pr: pr)
                        }
                    }
                }

                // Notifications
                if !service.state.notifications.isEmpty {
                    SectionView(
                        title: notificationTitle,
                        count: service.state.notifications.count,
                        color: AppColors.notifications
                    ) {
                        ForEach(service.state.notifications.prefix(10)) { notif in
                            NotificationRow(notification: notif)
                        }
                    }
                }

                // Issues
                if !service.state.issues.isEmpty {
                    SectionView(
                        title: issuesTitle,
                        count: service.state.issues.count,
                        color: AppColors.issues
                    ) {
                        ForEach(service.state.issues.prefix(8)) { issue in
                            IssueRow(issue: issue)
                        }
                    }
                }

                // Empty state
                if service.state.openPRs.isEmpty &&
                   service.state.reviewRequests.isEmpty &&
                   service.state.notifications.isEmpty &&
                   service.state.issues.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .font(.largeTitle)
                            .foregroundColor(AppColors.success)
                        Text("All caught up!")
                            .font(.headline)
                        Text("No pending items")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            }
            .padding()
        }
        .frame(maxHeight: 400)
    }
}

// MARK: - Section Container

struct SectionView<Content: View>: View {
    let title: String
    let count: Int
    let color: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                Text("\(count)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.2))
                    .foregroundColor(color)
                    .cornerRadius(4)
            }

            VStack(spacing: 6) {
                content()
            }
        }
    }
}

// MARK: - Loading & Error

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct ErrorView: View {
    let error: String
    @EnvironmentObject var service: GitHubService

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(AppColors.warning)

            Text("Error")
                .font(.headline)

            Text(error)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if error.contains("auth") {
                Text("Run `gh auth login` in Terminal")
                    .font(.caption)
                    .foregroundColor(AppColors.link)
                    .padding(.top, 4)
            }

            Button("Retry") {
                Task { await service.refresh() }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Footer

struct FooterView: View {
    @EnvironmentObject var service: GitHubService

    var body: some View {
        HStack {
            if let lastUpdated = service.state.lastUpdated {
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    Text("Updated \(lastUpdated.relativeFormatted)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            #if DEBUG
            Button("🎨") {
                AppDelegate.shared?.showColorPreview()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .help("Color Preview (DevMode)")
            #endif

            Button("Settings...") {
                AppDelegate.shared?.showSettings()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundColor(.secondary)

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

// MARK: - Date Extension

extension Date {
    var relativeFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
