import Foundation
import CloudKit

/// Lightweight, Codable cache representation of a team member used on the splash screen only.
private struct CachedMember: Codable {
    var name: String
    var emoji: String
    var quotesGoal: Int
    var salesWTDGoal: Int
    var salesMTDGoal: Int
    var sortIndex: Int
}

private extension TeamMember {
    /// Convert a TeamMember to its cached representation.
    var cached: CachedMember {
        CachedMember(
            name: self.name,
            emoji: self.emoji,
            quotesGoal: self.quotesGoal,
            salesWTDGoal: self.salesWTDGoal,
            salesMTDGoal: self.salesMTDGoal,
            sortIndex: self.sortIndex
        )
    }
}

private extension CachedMember {
    /// Convert a CachedMember back to a TeamMember for the splash screen.
    var teamMember: TeamMember {
        let m = TeamMember(name: name)
        m.emoji = emoji
        m.quotesGoal = quotesGoal
        m.salesWTDGoal = salesWTDGoal
        m.salesMTDGoal = salesMTDGoal
        m.sortIndex = sortIndex
        return m
    }
}

/// SplashViewModel uses a non-destructive merge policy for team member lists:
/// - CloudKit fetches are merged with any cached users by normalized name.
/// - Fetched users update cached fields, but no user is *removed* unless explicitly deleted.
/// - This prevents accidental user loss on first launch, cold install, or transient fetch failures.
class SplashViewModel: ObservableObject {
    /// Team members available for selection on the splash screen.
    @Published var teamMembers: [TeamMember] = []

    private let cacheKey = "SplashCachedTeamMembers"

    private func loadCachedMembers() -> [TeamMember] {
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let members = try? JSONDecoder().decode([CachedMember].self, from: data) {
            return members.map { $0.teamMember }
        }
        return []
    }

    private func saveCachedMembers(_ members: [TeamMember]) {
        let payload = members.map { $0.cached }
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    private func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init() {
        // Show any cached list immediately to avoid empty UI and accidental loss on transient fetch failures
        self.teamMembers = loadCachedMembers()
    }

    /// Fetches all members from CloudKit and merges with cache, never implicitly deleting users.
    func fetchMembersFromCloud() {
        CloudKitManager.shared.fetchAllTeamMembers { fetched in
            DispatchQueue.main.async {
                let cached = self.loadCachedMembers()
                // Build a dictionary by normalized name from cached, then overlay fetched (fetched wins per field if available)
                var byName: [String: TeamMember] = [:]
                for m in cached { byName[self.normalize(m.name)] = m }
                for m in fetched {
                    let key = self.normalize(m.name)
                    if let existing = byName[key] {
                        let updated = existing
                        if !m.emoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { updated.emoji = m.emoji }
                        updated.quotesGoal = m.quotesGoal
                        updated.salesWTDGoal = m.salesWTDGoal
                        updated.salesMTDGoal = m.salesMTDGoal
                        updated.sortIndex = m.sortIndex
                        byName[key] = updated
                    } else {
                        byName[key] = m
                    }
                }
                // Never implicitly delete: only explicit user deletes will remove entries from cache
                let merged = Array(byName.values).sorted { $0.sortIndex < $1.sortIndex }
                self.teamMembers = merged
                self.saveCachedMembers(merged)
            }
        }
    }

    /// Adds a new member record, normalizing name and avoiding duplicates, and refreshes ``teamMembers``.
    func addMember(name: String, emoji: String = "🙂") {
        let clean = normalize(name)
        guard !clean.isEmpty else { return }
        if teamMembers.contains(where: { normalize($0.name).lowercased() == clean.lowercased() }) {
            return // already exists; avoid duplicates differing by spacing/case
        }
        // Optimistic local add
        let tmp = TeamMember(name: clean)
        tmp.emoji = emoji
        tmp.sortIndex = teamMembers.count
        let new = tmp
        self.teamMembers.append(new)
        self.saveCachedMembers(self.teamMembers)

        CloudKitManager.shared.addTeamMember(name: clean, emoji: emoji) { [weak self] _ in
            self?.fetchMembersFromCloud()
        }
    }

    /// Deletes the provided member record and refreshes the list (explicit only).
    func deleteMember(_ member: TeamMember) {
        // Optimistic local delete (explicit action only)
        let key = normalize(member.name).lowercased()
        self.teamMembers.removeAll { normalize($0.name).lowercased() == key }
        self.saveCachedMembers(self.teamMembers)

        CloudKitManager.shared.deleteTeamMember(member) { [weak self] _ in
            self?.fetchMembersFromCloud()
        }
    }
}
