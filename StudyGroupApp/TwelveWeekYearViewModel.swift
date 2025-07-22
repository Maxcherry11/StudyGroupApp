import Foundation
import CloudKit

class TwelveWeekYearViewModel: ObservableObject {
    @Published var members: [TwelveWeekMember] = []

    private let container = CKContainer.default()
    private let defaultsKey = "TwelveWeekMembers"
    private var lastFetchHash: Int?

    init() {
        loadLocalMembers()
        updateLocalEntries(names: UserManager.shared.userList)
    }

    // MARK: - Local Persistence
    private func loadLocalMembers() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([TwelveWeekMember].self, from: data) else { return }
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

        let predicate = NSPredicate(value: true)
        let query = CKQuery(recordType: TwelveWeekMember.recordType, predicate: predicate)

        container.publicCloudDatabase.perform(query, inZoneWith: nil) { records, error in
            guard let records = records, error == nil else {
                print("⚠️ Fetch failed: \(error?.localizedDescription ?? "Unknown error")")
                return
            }

            let fetched = records.compactMap { TwelveWeekMember(record: $0) }
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
        let record = member.record
        container.publicCloudDatabase.save(record) { _, error in
            if let error = error {
                print("⚠️ Save failed: \(error.localizedDescription)")
            } else {
                DispatchQueue.main.async {
                    if let idx = self.members.firstIndex(where: { $0.name == member.name }) {
                        self.members[idx] = member
                    } else {
                        self.members.append(member)
                    }
                    self.saveLocalMembers()
                }
            }
        }
    }

    func deleteMember(named name: String) {
        let recordID = CKRecord.ID(recordName: "twy-\(name)")
        container.publicCloudDatabase.delete(withRecordID: recordID) { _, error in
            if let error = error {
                print("⚠️ Deletion failed: \(error.localizedDescription)")
            } else {
                DispatchQueue.main.async {
                    self.members.removeAll { $0.name == name }
                    self.saveLocalMembers()
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
