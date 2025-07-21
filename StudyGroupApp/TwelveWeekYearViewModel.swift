import Foundation
import CloudKit

class TwelveWeekYearViewModel: ObservableObject {
    @Published var members: [TwelveWeekMember] = []
    private let recordType = "TwelveWeekMember"

    init() {
        loadMembersFromCache()
        fetchMembersFromCloud()
    }

    func loadMembersFromCache() {
        if let data = UserDefaults.standard.data(forKey: "TwelveWeekMembers") {
            if let decoded = try? JSONDecoder().decode([TwelveWeekMember].self, from: data) {
                self.members = decoded
            }
        }
    }

    func saveMembersToCache() {
        if let data = try? JSONEncoder().encode(members) {
            UserDefaults.standard.set(data, forKey: "TwelveWeekMembers")
        }
    }

    func fetchMembersFromCloud() {
        let predicate = NSPredicate(value: true)
        let query = CKQuery(recordType: recordType, predicate: predicate)
        CKContainer.default().privateCloudDatabase.perform(query, inZoneWith: nil) { records, error in
            if let records = records {
                DispatchQueue.main.async {
                    self.members = records.compactMap { TwelveWeekMember(record: $0) }
                    self.saveMembersToCache()
                }
            }
        }
    }

    func saveMemberToCloud(_ member: TwelveWeekMember) {
        let record = member.toRecord()
        CKContainer.default().privateCloudDatabase.save(record) { _, error in
            if error == nil {
                DispatchQueue.main.async {
                    self.fetchMembersFromCloud()
                }
            }
        }
    }
}
