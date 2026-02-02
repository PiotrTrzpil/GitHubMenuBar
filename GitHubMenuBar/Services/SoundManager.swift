import AudioToolbox
import Foundation

/// System sound IDs for different alert types
enum AlertSound: SystemSoundID {
    case ping = 1057      // Attention-getting, for review requests
    case glass = 1054     // Subtle, for approvals
    case basso = 1022     // Warning tone, for CI failures
    case pop = 1152       // Quick notification, for mentions
}

/// Manages sound alerts for GitHub events
@MainActor
@Observable
final class SoundManager {
    static let shared = SoundManager()

    // MARK: - Settings

    var soundEnabled: Bool {
        UserDefaults.standard.bool(forKey: "soundEnabled")
    }

    var soundNewReviewRequest: Bool {
        UserDefaults.standard.bool(forKey: "soundNewReviewRequest")
    }

    var soundCIFailure: Bool {
        UserDefaults.standard.bool(forKey: "soundCIFailure")
    }

    var soundPRApproved: Bool {
        UserDefaults.standard.bool(forKey: "soundPRApproved")
    }

    var soundNewMention: Bool {
        UserDefaults.standard.bool(forKey: "soundNewMention")
    }

    // MARK: - State Tracking

    /// Track IDs we've already alerted on to avoid duplicates
    private var seenReviewRequestIds: Set<String> = []
    private var seenCIFailureIds: Set<String> = []
    private var seenApprovedIds: Set<String> = []
    private var seenMentionIds: Set<String> = []

    /// Whether we've done the initial load (skip sounds on first refresh)
    private var hasInitializedState = false

    private init() {}

    // MARK: - Public API

    /// Check for new events and play appropriate sounds
    /// Call this after each refresh with the updated state
    func checkAndPlaySounds(for state: GitHubState) {
        guard soundEnabled else { return }

        // Skip sounds on first load to avoid alert storm
        guard hasInitializedState else {
            initializeSeenState(from: state)
            hasInitializedState = true
            return
        }

        // Check each event type
        checkNewReviewRequests(state.reviewRequests)
        checkCIFailures(state.openPRs)
        checkApprovals(state.openPRs)
        checkMentions(state.notifications)
    }

    /// Reset tracking state (e.g., when user logs out or changes accounts)
    func reset() {
        seenReviewRequestIds.removeAll()
        seenCIFailureIds.removeAll()
        seenApprovedIds.removeAll()
        seenMentionIds.removeAll()
        hasInitializedState = false
    }

    // MARK: - Private Methods

    private func initializeSeenState(from state: GitHubState) {
        // Record all current IDs so we don't alert on them
        seenReviewRequestIds = Set(state.reviewRequests.map { $0.id })
        seenCIFailureIds = Set(
            state.openPRs
                .filter { CIStatus.from(checks: $0.statusCheckRollup) == .failure }
                .map { $0.id }
        )
        seenApprovedIds = Set(
            state.openPRs
                .filter { $0.reviewDecision == "APPROVED" }
                .map { $0.id }
        )
        seenMentionIds = Set(
            state.notifications
                .filter { $0.reason == "mention" }
                .map { $0.id }
        )
    }

    private func checkNewReviewRequests(_ requests: [ReviewRequest]) {
        guard soundNewReviewRequest else { return }

        let currentIds = Set(requests.map { $0.id })
        let newIds = currentIds.subtracting(seenReviewRequestIds)

        if !newIds.isEmpty {
            playSound(.ping)
        }

        seenReviewRequestIds = currentIds
    }

    private func checkCIFailures(_ prs: [PullRequest]) {
        guard soundCIFailure else { return }

        let failedPRIds = Set(
            prs
                .filter { CIStatus.from(checks: $0.statusCheckRollup) == .failure }
                .map { $0.id }
        )
        let newFailures = failedPRIds.subtracting(seenCIFailureIds)

        if !newFailures.isEmpty {
            playSound(.basso)
        }

        seenCIFailureIds = failedPRIds
    }

    private func checkApprovals(_ prs: [PullRequest]) {
        guard soundPRApproved else { return }

        let approvedPRIds = Set(
            prs
                .filter { $0.reviewDecision == "APPROVED" }
                .map { $0.id }
        )
        let newApprovals = approvedPRIds.subtracting(seenApprovedIds)

        if !newApprovals.isEmpty {
            playSound(.glass)
        }

        seenApprovedIds = approvedPRIds
    }

    private func checkMentions(_ notifications: [GitHubNotification]) {
        guard soundNewMention else { return }

        let mentionIds = Set(
            notifications
                .filter { $0.reason == "mention" }
                .map { $0.id }
        )
        let newMentions = mentionIds.subtracting(seenMentionIds)

        if !newMentions.isEmpty {
            playSound(.pop)
        }

        seenMentionIds = mentionIds
    }

    private func playSound(_ sound: AlertSound) {
        AudioServicesPlaySystemSound(sound.rawValue)
    }
}
