import SwiftUI

// MARK: - Color Preview View (DevMode)

struct ColorPreviewView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                colorSection("Section Badge Colors") {
                    colorRow("Open PRs", AppColors.openPRs)
                    colorRow("Review Requests", AppColors.reviewRequests)
                    colorRow("Merged PRs", AppColors.mergedPRs)
                    colorRow("Notifications", AppColors.notifications)
                    colorRow("Issues", AppColors.issues)
                }

                colorSection("CI Status Colors") {
                    colorRow("Success", AppColors.ciSuccess)
                    colorRow("Failure", AppColors.ciFailure)
                    colorRow("Pending", AppColors.ciPending)
                    colorRow("Unknown", AppColors.ciUnknown)
                }

                colorSection("PR Age Colors") {
                    colorRow("Fresh (< 1 day)", AppColors.ageFresh)
                    colorRow("Recent (1-3 days)", AppColors.ageRecent)
                    colorRow("Moderate (3-7 days)", AppColors.ageModerate)
                    colorRow("Old (> 7 days)", AppColors.ageOld)
                }

                colorSection("Status Colors") {
                    colorRow("Attention", AppColors.attention)
                    colorRow("Conflict", AppColors.conflict)
                    colorRow("Success", AppColors.success)
                    colorRow("Error", AppColors.error)
                    colorRow("Warning", AppColors.warning)
                }

                colorSection("Notification Reason Colors") {
                    colorRow("Review Requested", AppColors.reviewRequested)
                    colorRow("Mention", AppColors.mention)
                    colorRow("Author", AppColors.author)
                    colorRow("CI Activity", AppColors.ciActivity)
                    colorRow("Assign", AppColors.assign)
                    colorRow("State Change", AppColors.stateChange)
                    colorRow("Default", AppColors.defaultNotification)
                }

                colorSection("Diff Colors") {
                    colorRow("Additions", AppColors.additions)
                    colorRow("Deletions", AppColors.deletions)
                }

                colorSection("UI Colors") {
                    colorRow("Draft", AppColors.draft)
                    colorRow("Muted", AppColors.muted)
                    colorRow("Link", AppColors.link)
                }

                colorSection("Card Backgrounds") {
                    HStack(spacing: 12) {
                        VStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(AppColors.cardBackground(hovered: false))
                                .frame(height: 40)
                            Text("Normal")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        VStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(AppColors.cardBackground(hovered: true))
                                .frame(height: 40)
                            Text("Hovered")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Sample card preview
                colorSection("Sample Card") {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Text("owner/repo")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("#123")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("2h ago")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Text("Sample PR title here")
                            .font(.caption)
                            .fontWeight(.medium)
                        HStack(spacing: 6) {
                            HStack(spacing: 2) {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 9))
                                Text("CI")
                                    .font(.caption2)
                            }
                            .foregroundColor(AppColors.ciSuccess)

                            HStack(spacing: 2) {
                                Image(systemName: "xmark.circle")
                                    .font(.system(size: 9))
                                Text("lint")
                                    .font(.caption2)
                            }
                            .foregroundColor(AppColors.ciFailure)

                            HStack(spacing: 2) {
                                Image(systemName: "clock")
                                    .font(.system(size: 9))
                                Text("CI")
                                    .font(.caption2)
                            }
                            .foregroundColor(AppColors.ciPending)

                            HStack(spacing: 2) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 9))
                                Text("Conflicts")
                                    .font(.caption2)
                            }
                            .foregroundColor(AppColors.conflict)
                        }
                    }
                    .padding(8)
                    .background(AppColors.cardBackground(hovered: false))
                    .cornerRadius(6)
                }
            }
            .padding()
        }
        .frame(width: 350, height: 600)
    }

    private func colorSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .padding(.bottom, 4)
            content()
        }
        .padding()
        .background(AppColors.cardBackground(hovered: false))
        .cornerRadius(8)
    }

    private func colorRow(_ name: String, _ color: Color) -> some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 20, height: 20)

            Text(name)
                .font(.caption)

            Spacer()

            Text(name)
                .font(.caption)
                .foregroundColor(color)
        }
    }
}

#Preview {
    ColorPreviewView()
}
