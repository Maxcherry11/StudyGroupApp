import Foundation
import CloudKit

class TwelveWeekYearViewModel: ObservableObject {
    @Published var members: [TwelveWeekMember] = []

    private let recordType = TwelveWeekMember.recordType
    private let cacheKey = "TwelveWeekMembersCache"

    init() {
        loadCachedMembers()
        fetchMembersFromCloud()
    }

    // MARK: - Load from UserDefaults

    private func loadCachedMembers() {
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let decoded = try? JSONDecoder().decode([TwelveWeekMember].self, from: data) {
            self.members = decoded
        }
    }

    private func cacheMembers() {
        if let data = try? JSONEncoder().encode(members) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    // MARK: - Fetch from CloudKit

    func fetchMembersFromCloud() {
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        CKContainer.default().publicCloudDatabase.perform(query, inZoneWith: nil) { records, error in
            DispatchQueue.main.async {
                guard let records = records else { return }
                let fetched = records.compactMap { TwelveWeekMember(record: $0) }

                if fetched != self.members {
                    self.members = fetched
                    self.cacheMembers()
                }
            }
        }
    }

    // MARK: - Save

    func saveMember(_ member: TwelveWeekMember) {
        let record = member.record
        CKContainer.default().publicCloudDatabase.save(record) { _, error in
            DispatchQueue.main.async {
                if let index = self.members.firstIndex(where: { $0.name == member.name }) {
                    self.members[index] = member
                } else {
                    self.members.append(member)
                }
                self.cacheMembers()
            }
        }
    }

    // MARK: - Delete

    func deleteMember(named name: String) {
        let recordID = CKRecord.ID(recordName: "twy-\(name)")
        CKContainer.default().publicCloudDatabase.delete(withRecordID: recordID) { _, _ in
            DispatchQueue.main.async {
                self.members.removeAll { $0.name == name }
                self.cacheMembers()
            }
        }
    }

    // MARK: - Sync with UserManager

    func updateLocalEntries(names: [String]) {
        for name in names {
            if !members.contains(where: { $0.name == name }) {
                let newMember = TwelveWeekMember(name: name, goals: [])
                saveMember(newMember)
            }
        }

        for member in members {
            if !names.contains(member.name) {
                deleteMember(named: member.name)
            }
        }
    }
}
