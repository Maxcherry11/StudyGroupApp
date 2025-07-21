import Foundation
import CloudKit

class TwelveWeekYearViewModel: ObservableObject {
    @Published var members: [TwelveWeekYearMember] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let container = CKContainer.default()
    private let recordType = "TwelveWeekYearMember"
    private let cacheKey = "TwelveWeekYearMembersCache"

    init() {
        loadMembersFromCache()
        fetchMembersFromCloudKit()
        syncWithUserNames()
    }

    // MARK: - Fetch from CloudKit
    func fetchMembersFromCloudKit() {
        isLoading = true
        errorMessage = nil

        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        let operation = CKQueryOperation(query: query)
        var fetched: [TwelveWeekYearMember] = []

        operation.recordFetchedBlock = { record in
            if let member = TwelveWeekYearMember.from(record: record) {
                fetched.append(member)
            }
        }

        operation.queryCompletionBlock = { [weak self] _, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                } else {
                    self?.members = fetched
                    self?.saveMembersToCache(fetched)
                }
            }
        }

        container.publicCloudDatabase.add(operation)
    }

    // MARK: - Add or Update Member
    func saveMember(_ member: TwelveWeekYearMember) {
        let recordID = CKRecord.ID(recordName: member.id)
        let record = CKRecord(recordType: recordType, recordID: recordID)
        record["name"] = member.name as CKRecordValue

        container.publicCloudDatabase.save(record) { [weak self] _, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                } else {
                    if let index = self?.members.firstIndex(where: { $0.id == member.id }) {
                        self?.members[index] = member
                    } else {
                        self?.members.append(member)
                    }
                    self?.saveMembersToCache(self?.members ?? [])
                }
            }
        }
    }

    // MARK: - Delete Member
    func deleteMember(named name: String) {
        guard let member = members.first(where: { $0.name == name }) else { return }
        let recordID = CKRecord.ID(recordName: member.id)

        container.publicCloudDatabase.delete(withRecordID: recordID) { [weak self] _, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                } else {
                    self?.members.removeAll { $0.name == name }
                    self?.saveMembersToCache(self?.members ?? [])
                }
            }
        }
    }

    // MARK: - Local Cache
    private func saveMembersToCache(_ members: [TwelveWeekYearMember]) {
        if let data = try? JSONEncoder().encode(members) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    private func loadMembersFromCache() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let cached = try? JSONDecoder().decode([TwelveWeekYearMember].self, from: data) else { return }
        self.members = cached
    }

    // MARK: - Splash Screen Sync
    func syncWithUserNames() {
        let names = UserManager.shared.userNames
        for name in names {
            if !members.contains(where: { $0.name == name }) {
                let new = TwelveWeekYearMember(id: "twy-\(name)", name: name)
                saveMember(new)
            }
        }

        for member in members {
            if !names.contains(member.name) {
                deleteMember(named: member.name)
            }
        }
    }
}

struct TwelveWeekYearMember: Identifiable, Codable, Equatable {
    var id: String
    var name: String

    static func from(record: CKRecord) -> TwelveWeekYearMember? {
        guard let name = record["name"] as? String else { return nil }
        return TwelveWeekYearMember(id: record.recordID.recordName, name: name)
    }
}
