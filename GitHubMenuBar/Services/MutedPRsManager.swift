import Foundation

/// Manages muted PR state and persistence
@MainActor
@Observable
final class MutedPRsManager {
    static let shared = MutedPRsManager()

    private(set) var mutedPRIds: Set<String> = []
    private var mutedPRTimestamps: [String: Date] = [:]

    private let mutedPRsKey = "mutedPRIds"
    private let mutedTimestampsKey = "mutedPRTimestamps"

    // MARK: - Auto-unmute Settings

    var autoUnmuteOnActivity: Bool {
        UserDefaults.standard.object(forKey: "autoUnmuteOnActivity") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "autoUnmuteOnActivity")
    }

    var autoUnmuteOnlyHumans: Bool {
        UserDefaults.standard.object(forKey: "autoUnmuteOnlyHumans") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "autoUnmuteOnlyHumans")
    }

    var autoUnmuteOnlyMentions: Bool {
        UserDefaults.standard.object(forKey: "autoUnmuteOnlyMentions") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "autoUnmuteOnlyMentions")
    }

    // MARK: - Initialization

    private init() {
        load()
    }

    // MARK: - Public API

    func isMuted(_ prId: String) -> Bool {
        mutedPRIds.contains(prId)
    }

    func toggleMute(_ prId: String) {
        if mutedPRIds.contains(prId) {
            mutedPRIds.remove(prId)
            mutedPRTimestamps.removeValue(forKey: prId)
        } else {
            mutedPRIds.insert(prId)
            mutedPRTimestamps[prId] = Date()
        }
        save()
    }

    func unmute(_ prId: String) {
        mutedPRIds.remove(prId)
        mutedPRTimestamps.removeValue(forKey: prId)
        save()
    }

    func getMuteTimestamp(_ prId: String) -> Date? {
        mutedPRTimestamps[prId]
    }

    /// Remove muted IDs for PRs that are no longer open
    func unmuteClosed(openPRIds: Set<String>) {
        let closedMuted = mutedPRIds.subtracting(openPRIds)
        if !closedMuted.isEmpty {
            mutedPRIds.subtract(closedMuted)
            for id in closedMuted {
                mutedPRTimestamps.removeValue(forKey: id)
            }
            save()
        }
    }

    // MARK: - Persistence

    private func load() {
        if let saved = UserDefaults.standard.array(forKey: mutedPRsKey) as? [String] {
            mutedPRIds = Set(saved)
        }
        if let timestamps = UserDefaults.standard.dictionary(forKey: mutedTimestampsKey) as? [String: Double] {
            mutedPRTimestamps = timestamps.mapValues { Date(timeIntervalSince1970: $0) }
        }
    }

    private func save() {
        UserDefaults.standard.set(Array(mutedPRIds), forKey: mutedPRsKey)
        let timestamps = mutedPRTimestamps.mapValues { $0.timeIntervalSince1970 }
        UserDefaults.standard.set(timestamps, forKey: mutedTimestampsKey)
    }
}
