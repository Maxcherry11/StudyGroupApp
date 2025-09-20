import Foundation
import CloudKit

class TwelveWeekYearViewModel: ObservableObject {
    // NOTE: Non-destructive sync rules
    // 1) Never delete local members during automatic sync/merge.
    // 2) Only delete on explicit user action via `deleteMember`.
    // 3) Treat empty CloudKit fetches as non-authoritative; preserve locals and resync.
    @Published var members: [TwelveWeekMember] = []

    /// Primary cache key (versioned) to avoid accidental resets across app updates/migrations
    private let defaultsKey = "twy-cache-v2"
    /// Legacy keys we still read (one-time migration) but never write to
    private let legacyDefaultsKeys: [String] = ["twy-cache", "TwelveWeekMembers"]
    private var lastFetchHash: Int?

    init() {
        loadLocalMembers()
        updateLocalEntries(names: UserManager.shared.userList)
    }

    // MARK: - Local Persistence
    private func loadLocalMembers() {
        let ud = UserDefaults.standard

        // 1) Try newest (v2) key first
        if let data = ud.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([TwelveWeekMember].self, from: data) {
            members = decoded
            lastFetchHash = computeHash(for: decoded)
            return
        }

        // 2) One-time migration from legacy keys (first one that decodes wins)
        for key in legacyDefaultsKeys {
            if let data = ud.data(forKey: key),
               let decoded = try? JSONDecoder().decode([TwelveWeekMember].self, from: data) {
                members = decoded
                lastFetchHash = computeHash(for: decoded)
                // Write forward to v2 key so future loads are stable
                if let v2 = try? JSONEncoder().encode(decoded) {
                    ud.set(v2, forKey: defaultsKey)
                }
                return
            }
        }

        // 3) If nothing decodes, do *not* create seed data here. We'll let
        //    updateLocalEntries(names:) add users non-destructively based on UserManager
        //    without clearing any existing on-disk data.
    }

    private func saveLocalMembers() {
        // Avoid clobbering storage with an empty write that could appear during
        // transient states (e.g., before CloudKit merge completes).
        guard !members.isEmpty else { return }
        guard let data = try? JSONEncoder().encode(members) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    // MARK: - Hashing
    private func computeHash(for list: [TwelveWeekMember]) -> Int {
        var hasher = Hasher()
        for m in list {
            hasher.combine(m.name)
            for g in m.goals {
                hasher.combine(g.id)
                hasher.combine(g.title)
                hasher.combine(g.percent)
            }
        }
        return hasher.finalize()
    }

    // MARK: - CloudKit Sync
    // Contract: App updates must not reset 12WY data.
    //  - Empty/failed CloudKit fetches are *non-authoritative*.
    //  - Local cached members + goal stats are preserved and only merged/upserted.
    func fetchMembersFromCloud() {
        let names = UserManager.shared.userList
        // Only *add* missing names locally here; never delete based on this list.
        updateLocalEntries(names: names)

        CloudKitManager.fetchTwelveWeekMembers(matching: names) { [weak self] fetched in
            guard let self = self else { return }
            let newHash = self.computeHash(for: fetched)
            DispatchQueue.main.async {
                // If CloudKit returns *empty*, do NOT treat that as authoritative.
                // Keep locals and schedule an upload instead.
                if fetched.isEmpty {
                    self.scheduleUploadOfLocalMembersIfNeeded()
                    return
                }

                // Only merge when content actually changed.
                if self.lastFetchHash != newHash {
                    self.mergeMembersSafely(serverMembers: fetched, fetchSucceeded: true)
                    self.lastFetchHash = newHash
                    self.saveLocalMembers()
                }
            }
        }
    }

    func saveMember(_ member: TwelveWeekMember) {
        // Capture the prior state so we can detect placeholder vs. intentional edits
        let previous = members.first { existing in
            existing.id == member.id || existing.name == member.name
        }

        if let idx = members.firstIndex(where: { $0.id == member.id }) {
            members[idx] = member
        } else if let idx = members.firstIndex(where: { $0.name == member.name }) {
            members[idx] = member
        } else {
            members.append(member)
        }
        // Persist immediately so manual edits survive even if we bail on CloudKit
        saveLocalMembers()

        let recordID = CKRecord.ID(recordName: "twy-\(member.name)")
        CloudKitManager.container.publicCloudDatabase.fetch(withRecordID: recordID) { [weak self] record, error in
            guard let self else { return }

            let hadGoalsBeforeEdit = !(previous?.goals.isEmpty ?? true)
            let hasGoalsAfterEdit = !member.goals.isEmpty

            var remoteGoals: [GoalProgress] = []
            if let data = record?["goals"] as? Data,
               let decoded = try? JSONDecoder().decode([GoalProgress].self, from: data) {
                remoteGoals = decoded
            }
            let remoteHasGoals = !remoteGoals.isEmpty

            // Scenario: local snapshot is just a placeholder (no goals, default state) but
            // CloudKit already has real data. Avoid overwriting the real progress.
            if record != nil && !hasGoalsAfterEdit && !hadGoalsBeforeEdit && remoteHasGoals {
                DispatchQueue.main.async {
                    if let idx = self.members.firstIndex(where: { $0.id == member.id }) {
                        self.members[idx].goals = remoteGoals
                    } else if let idx = self.members.firstIndex(where: { $0.name == member.name }) {
                        self.members[idx].goals = remoteGoals
                    }
                    self.saveLocalMembers()
                }
                return
            }

            // Decide whether we should attempt a CloudKit save based on the
            // current vs. previous state and the fetch outcome.
            if let ckError = error as? CKError {
                if ckError.code == .unknownItem {
                    // Record truly does not exist yet; safe to create it with current data.
                    CloudKitManager.saveTwelveWeekMember(member) { _ in }
                } else {
                    print("❌ TWY fetch failed for \(member.name): \(ckError.localizedDescription)")
                    // If we only have placeholder data, skip saving to avoid wiping real Cloud data.
                    if hasGoalsAfterEdit || hadGoalsBeforeEdit {
                        CloudKitManager.saveTwelveWeekMember(member) { _ in }
                    }
                }
                return
            }

            if error != nil {
                // Non-CKError (unlikely). Apply the same placeholder guard.
                if hasGoalsAfterEdit || hadGoalsBeforeEdit {
                    CloudKitManager.saveTwelveWeekMember(member) { _ in }
                }
                return
            }

            // No error: either record exists (handled above) or is brand new. Persist the edit.
            CloudKitManager.saveTwelveWeekMember(member) { _ in }
        }
    }

    func deleteMember(named name: String) {
        CloudKitManager.deleteTwelveWeekMember(named: name)
        members.removeAll { $0.name == name }
        saveLocalMembers()
    }

    // MARK: - Sync with UserManager
    func updateLocalEntries(names: [String]) {
        // Only add missing names; do NOT delete local members based on this list.
        // Deletions must be explicit via `deleteMember(named:)`.
        for name in names where !members.contains(where: { $0.name == name }) {
            let newMember = TwelveWeekMember(name: name, goals: [])
            members.append(newMember)
        }
        saveLocalMembers()
    }

    // MARK: - Non-destructive CloudKit merge helpers
    /// Non-destructive merge: upserts remote members and never deletes locals unless explicitly requested elsewhere.
    private func mergeMembersSafely(serverMembers: [TwelveWeekMember], fetchSucceeded: Bool) {
        guard fetchSucceeded else { return }

        // Map current members by stable id if available; fall back to name for legacy data.
        var byKey: [String: TwelveWeekMember] = [:]
        for m in members {
            let key = legacyKey(for: m)
            byKey[key] = m
        }

        // Upsert all remote records.
        for remote in serverMembers {
            let key = legacyKey(for: remote)
            if var existing = byKey[key] {
                // Update mutable fields non-destructively. If you track timestamps, compare here.
                existing.name = remote.name
                existing.goals = remote.goals
                byKey[key] = existing
            } else {
                byKey[key] = remote
            }
        }

        // Do NOT remove locals that are missing from the server here.
        members = Array(byKey.values).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// If we have locals but the server fetch came back empty, schedule pushing locals up.
    private func scheduleUploadOfLocalMembersIfNeeded() {
        guard members.contains(where: { !$0.goals.isEmpty }) else { return }
        for member in members where !member.goals.isEmpty {
            CloudKitManager.saveTwelveWeekMember(member) { _ in }
        }
    }

    /// Temporary compatibility key until all members have a stable id in storage and CloudKit
    private func legacyKey(for member: TwelveWeekMember) -> String {
        // Prefer a stable id if your model has one; else fall back to name.
        // Replace with `member.id.uuidString` when available across app + CloudKit.
        return member.name
    }
}
