import Foundation

// MARK: - PR Preview Details

/// Detailed information for PR preview pane
struct PRPreviewDetails: Equatable {
    let prId: String
    let prUrl: String                    // GitHub PR URL for constructing file links
    let additions: Int
    let deletions: Int
    let changedFilesCount: Int
    let topChangedFiles: [ChangedFile]
    let failedWorkflows: [WorkflowRun]
    let pendingReviewers: [String]       // Who still needs to review
    let completedReviews: [PRReview]     // Who already reviewed
    let recentMentions: [PRComment]
    let createdAt: Date?
    let updatedAt: Date?

    static func empty(prId: String) -> PRPreviewDetails {
        PRPreviewDetails(
            prId: prId,
            prUrl: "",
            additions: 0,
            deletions: 0,
            changedFilesCount: 0,
            topChangedFiles: [],
            failedWorkflows: [],
            pendingReviewers: [],
            completedReviews: [],
            recentMentions: [],
            createdAt: nil,
            updatedAt: nil
        )
    }
}

// MARK: - PR Review

struct PRReview: Identifiable, Equatable {
    var id: String { "\(author)-\(Int(submittedAt?.timeIntervalSince1970 ?? 0))" }
    let author: String
    let state: ReviewState
    let submittedAt: Date?

    enum ReviewState: String, Equatable {
        case approved = "APPROVED"
        case changesRequested = "CHANGES_REQUESTED"
        case commented = "COMMENTED"
        case pending = "PENDING"
        case dismissed = "DISMISSED"

        var displayName: String {
            switch self {
            case .approved: return "Approved"
            case .changesRequested: return "Changes requested"
            case .commented: return "Commented"
            case .pending: return "Pending"
            case .dismissed: return "Dismissed"
            }
        }

        var icon: String {
            switch self {
            case .approved: return "checkmark.circle.fill"
            case .changesRequested: return "xmark.circle.fill"
            case .commented: return "bubble.left.fill"
            case .pending: return "clock.fill"
            case .dismissed: return "minus.circle.fill"
            }
        }
    }
}

// MARK: - Changed File

struct ChangedFile: Identifiable, Equatable {
    var id: String { filename }
    let filename: String
    let additions: Int
    let deletions: Int

    var totalChanges: Int { additions + deletions }

    /// Returns just the filename without the path
    var shortName: String {
        filename.components(separatedBy: "/").last ?? filename
    }

    /// Returns the directory path without the filename
    var directory: String? {
        let components = filename.components(separatedBy: "/")
        guard components.count > 1 else { return nil }
        return components.dropLast().joined(separator: "/")
    }
}

// MARK: - Workflow Run

struct WorkflowRun: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let conclusion: String
    let url: String?

    var isFailed: Bool {
        conclusion.lowercased() == "failure"
    }
}

// MARK: - PR Comment

struct PRComment: Identifiable, Equatable {
    var id: String { "\(author)-\(Int(createdAt.timeIntervalSince1970))" }
    let author: String
    let body: String
    let createdAt: Date
    let url: String?

    /// Returns a truncated preview of the comment body
    var preview: String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let singleLine = trimmed.replacingOccurrences(of: "\n", with: " ")
        if singleLine.count > 100 {
            return String(singleLine.prefix(97)) + "..."
        }
        return singleLine
    }
}

// MARK: - Preview State

/// Tracks the hover state and loading for PR preview
struct PRPreviewState: Equatable {
    var hoveredPRId: String?
    var isPreviewPaneHovered: Bool = false
    var isMainPaneHovered: Bool = false
    var previewCache: [String: PRPreviewDetails] = [:]
    var loadingPRIds: Set<String> = []
    var errorPRIds: [String: String] = [:]

    var currentPreview: PRPreviewDetails? {
        guard let id = hoveredPRId else { return nil }
        return previewCache[id]
    }

    var isLoadingCurrent: Bool {
        guard let id = hoveredPRId else { return false }
        return loadingPRIds.contains(id)
    }

    var currentError: String? {
        guard let id = hoveredPRId else { return nil }
        return errorPRIds[id]
    }
}
