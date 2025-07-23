import Foundation
import CloudKit

class TwelveWeekYearViewModel: ObservableObject {
    @Published var members: [TwelveWeekMember] = []

    /// Local storage key for cached members.
    private let defaultsKey = "twy-cache"
    private var lastFetchHash: Int?

    init() {
        loadLocalMembers()
        updateLocalEntries(names: UserManager.shared.userList)
    }

    // MARK: - Local Persistence
    private func loadLocalMembers() {
        let data = UserDefaults.standard.data(forKey: defaultsKey) ??
            UserDefaults.standard.data(forKey: "TwelveWeekMembers")
        guard let unwrapped = data,
              let decoded = try? JSONDecoder().decode([TwelveWeekMember].self, from: unwrapped) else { return }
        members = decoded
        lastFetchHash = computeHash(for: decoded)
    }

    private func saveLocalMembers() {
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
    func fetchMembersFromCloud() {
        let names = UserManager.shared.userList
        updateLocalEntries(names: names)

        CloudKitManager.fetchTwelveWeekMembers { [weak self] fetched in
            guard let self = self else { return }
            let newHash = self.computeHash(for: fetched)
            DispatchQueue.main.async {
                if self.lastFetchHash != newHash {
                    self.members = fetched
                    self.lastFetchHash = newHash
                    self.saveLocalMembers()
                }
            }
        }
    }

    func saveMember(_ member: TwelveWeekMember) {
        CloudKitManager.saveTwelveWeekMember(member)
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
        // Remove any members not in the provided names
        for member in members where !names.contains(member.name) {
            deleteMember(named: member.name)
        }

        // Add missing names
        for name in names where !members.contains(where: { $0.name == name }) {
            let newMember = TwelveWeekMember(name: name, goals: [])
            members.append(newMember)
            saveMember(newMember)
        }

        saveLocalMembers()
    }
}
