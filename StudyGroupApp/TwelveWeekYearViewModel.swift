import Foundation
import CloudKit
import Combine

class TwelveWeekYearViewModel: ObservableObject {
    @Published var members: [TwelveWeekMember] = []

    private let container = CKContainer.default()
    private let defaultsKey = "TwelveWeekMembers"

    init() {
        loadLocalMembers()
    }

    // MARK: - Load from UserDefaults

    private func loadLocalMembers() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([TwelveWeekMember].self, from: data) else {
            return
        }
        self.members = decoded
    }

    private func saveLocalMembers() {
        guard let data = try? JSONEncoder().encode(members) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    // MARK: - CloudKit Sync

    func fetchMembersFromCloud() {
        let predicate = NSPredicate(value: true)
        let query = CKQuery(recordType: TwelveWeekMember.recordType, predicate: predicate)

        container.publicCloudDatabase.perform(query, inZoneWith: nil) { records, error in
            guard let records = records, error == nil else {
                print("⚠️ Fetch failed: \(error?.localizedDescription ?? \"Unknown error\")")
                return
            }

            let fetched = records.compactMap { TwelveWeekMember(record: $0) }

            DispatchQueue.main.async {
                if fetched.hashValue != self.members.hashValue {
                    self.members = fetched
                    self.saveLocalMembers()
                }
            }
        }
    }

    // MARK: - Save

    func saveMember(_ member: TwelveWeekMember) {
        let record = member.record
        container.publicCloudDatabase.save(record) { _, error in
            if let error = error {
                print("⚠️ Save failed: \(error.localizedDescription)")
            } else {
                DispatchQueue.main.async {
                    if let index = self.members.firstIndex(where: { $0.name == member.name }) {
                        self.members[index] = member
                    } else {
                        self.members.append(member)
                    }
                    self.saveLocalMembers()
                }
            }
        }
    }

    // MARK: - Delete

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
            }
        }
    }

    // MARK: - Sync with UserManager

    func updateLocalEntries(names: [String]) {
        var updated = members

        for name in names {
            if !updated.contains(where: { $0.name == name }) {
                let newMember = TwelveWeekMember(name: name, goals: [])
                updated.append(newMember)
                saveMember(newMember)
            }
        }

        self.members = updated
        self.saveLocalMembers()
    }
}
