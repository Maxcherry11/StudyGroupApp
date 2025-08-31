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
        CloudKitManager.saveTwelveWeekMember(member) { result in
            switch result {
            case .success:
                print("✅ TWY member saved: \(member.name)")
            case .failure(let error):
                print("❌ Failed to save TWY member \(member.name): \(error.localizedDescription)")
            }
        }
        if let idx = members.firstIndex(where: { $0.name == member.name }) {
            members[idx] = member
        } else {
            members.append(member)
        }
        saveLocalMembers()
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
        guard !members.isEmpty else { return }
        for m in members { CloudKitManager.saveTwelveWeekMember(m) { _ in } }
    }

    /// Temporary compatibility key until all members have a stable id in storage and CloudKit
    private func legacyKey(for member: TwelveWeekMember) -> String {
        // Prefer a stable id if your model has one; else fall back to name.
        // Replace with `member.id.uuidString` when available across app + CloudKit.
        return member.name
    }
}
