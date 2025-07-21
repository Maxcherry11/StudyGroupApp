import Foundation
import CloudKit

class TwelveWeekYearViewModel: ObservableObject {
    @Published var members: [TwelveWeekYearMember] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    private let container: CKContainer
    private let cacheKey = "TwelveWeekYearMembersCache"

    init(container: CKContainer = CKContainer.default()) {
        self.container = container
        loadMembersFromCache()
        fetchMembersFromCloudKit()
    }

    // MARK: - Fetch from CloudKit
    func fetchMembersFromCloudKit() {
        isLoading = true
        errorMessage = nil
        let predicate = NSPredicate(value: true)
        let query = CKQuery(recordType: "TwelveWeekYearMember", predicate: predicate)
        let operation = CKQueryOperation(query: query)
        var fetchedMembers: [TwelveWeekYearMember] = []

        operation.recordFetchedBlock = { record in
            if let member = TwelveWeekYearMember.from(record: record) {
                fetchedMembers.append(member)
            }
        }
        operation.queryCompletionBlock = { [weak self] cursor, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                } else {
                    self?.members = fetchedMembers
                    self?.saveMembersToCache(members: fetchedMembers)
                }
            }
        }
        container.publicCloudDatabase.add(operation)
    }

    // MARK: - Add New Member
    func addMember(name: String, completion: ((Result<Void, Error>) -> Void)? = nil) {
        let record = CKRecord(recordType: "TwelveWeekYearMember")
        record["name"] = name as CKRecordValue
        isLoading = true
        errorMessage = nil
        container.publicCloudDatabase.save(record) { [weak self] savedRecord, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                    completion?(.failure(error))
                } else if let savedRecord = savedRecord, let member = TwelveWeekYearMember.from(record: savedRecord) {
                    self?.members.append(member)
                    self?.saveMembersToCache(members: self?.members ?? [])
                    completion?(.success(()))
                }
            }
        }
    }

    // MARK: - Local Caching
    private func saveMembersToCache(members: [TwelveWeekYearMember]) {
        do {
            let data = try JSONEncoder().encode(members)
            UserDefaults.standard.set(data, forKey: cacheKey)
        } catch {
            print("Failed to cache members: \(error)")
        }
    }

    private func loadMembersFromCache() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return }
        do {
            let cachedMembers = try JSONDecoder().decode([TwelveWeekYearMember].self, from: data)
            self.members = cachedMembers
        } catch {
            print("Failed to load members from cache: \(error)")
        }
    }

    // MARK: - Sync
    func syncMembers() {
        fetchMembersFromCloudKit()
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
