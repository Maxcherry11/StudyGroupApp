import CloudKit
import Foundation

class CloudKitManager: ObservableObject {
    static let shared = CloudKitManager()
    /// The primary iCloud container for all app data.
    static let container = CKContainer(identifier: "iCloud.com.dj.Outcast")
    private let database = CloudKitManager.container.publicCloudDatabase
    private let recordType = "TeamMember"
    private let scoreRecordType = "ScoreRecord"
    private let cardRecordType = "Card"
    private static let userRecordType = "User"

    @Published var team: [TeamMember] = []

    private func isValid(_ member: TeamMember) -> Bool {
        !member.name.trimmingCharacters(in: .whitespaces).isEmpty &&
        member.quotesGoal > 0 &&
        member.salesWTDGoal > 0 &&
        member.salesMTDGoal > 0
    }

    func fetchTeam(completion: @escaping ([TeamMember]) -> Void) {
        // Explicitly use NSPredicate(value: true) to avoid relying on implicit queryable fields
        let predicate = NSPredicate(value: true)
        let query = CKQuery(recordType: recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

        var fetchedMembers: [TeamMember] = []

        let operation = CKQueryOperation(query: query)
        operation.recordMatchedBlock = { recordID, result in
            switch result {
            case .success(let record):
                if let member = TeamMember(record: record) {
                    fetchedMembers.append(member)
                }
            case .failure(let error):
                print("❌ Failed to match record: \(error.localizedDescription)")
            }
        }

        operation.queryResultBlock = { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    print("📤 Fetching from CloudKit...")
                    print("✅ Retrieved \(fetchedMembers.count) members:")
                    for member in fetchedMembers {
                        print("   • \(member.name)")
                    }
                    let valid = fetchedMembers.filter { self.isValid($0) }
                    self.team = valid
                    completion(valid)
                case .failure(let error):
                    print("❌ CloudKit query failed: \(error.localizedDescription)")
                    completion([])
                }
            }
        }

        database.add(operation)
    }

    func save(_ member: TeamMember, completion: @escaping (CKRecord.ID?) -> Void) {
        guard isValid(member) else {
            print("⚠️ Skipping save for invalid member: \(member.name)")
            completion(nil)
            return
        }
        let predicate = NSPredicate(format: "name == %@", member.name)
        let query = CKQuery(recordType: recordType, predicate: predicate)

        let operation = CKQueryOperation(query: query)
        operation.desiredKeys = nil
        operation.resultsLimit = 1

        var matchedRecord: CKRecord?

        operation.recordMatchedBlock = { recordID, result in
            switch result {
            case .success(let record):
                matchedRecord = record
            case .failure(let error):
                print("❌ Failed to match existing record: \(error.localizedDescription)")
            }
        }

        operation.queryResultBlock = { result in
            DispatchQueue.main.async {
                let modifyOperation = self.prepareModifyOperation(for: member, existingRecord: matchedRecord, completion: completion)
                self.database.add(modifyOperation)
            }
        }

        database.add(operation)
    }

    private func prepareModifyOperation(for member: TeamMember, existingRecord: CKRecord?, completion: @escaping (CKRecord.ID?) -> Void) -> CKModifyRecordsOperation {
        let record = member.toRecord(existing: existingRecord)

        let modifyOperation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        modifyOperation.modifyRecordsResultBlock = { result in
            DispatchQueue.main.async {
                switch result {
                case .failure(let error):
                    print("❌ Error saving: \(error.localizedDescription)")
                    completion(nil)
                case .success:
                    print("✅ Successfully saved member: \(member.name)")
                    completion(record.recordID)
                }
            }
        }

        return modifyOperation
    }

    func delete(_ member: TeamMember) {
        let id = CKRecord.ID(recordName: member.id.uuidString)
        database.delete(withRecordID: id) { _, error in
            if let error = error {
                print("❌ Error deleting: \(error.localizedDescription)")
            }
        }
    }

    func fetchAll(completion: @escaping ([TeamMember]) -> Void) {
        fetchTeam(completion: completion)
    }

    func fetchFiltered(byUserName name: String, completion: @escaping ([TeamMember]) -> Void) {
        let predicate = NSPredicate(format: "name == %@", name)
        let query = CKQuery(recordType: recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

        var results: [TeamMember] = []

        let operation = CKQueryOperation(query: query)
        operation.recordMatchedBlock = { recordID, result in
            switch result {
            case .success(let record):
                if let member = TeamMember(record: record) {
                    results.append(member)
                }
            case .failure(let error):
                print("❌ Failed to fetch record: \(error.localizedDescription)")
            }
        }

        operation.queryResultBlock = { _ in
            DispatchQueue.main.async {
                let valid = results.filter { self.isValid($0) }
                completion(valid)
            }
        }

        database.add(operation)
    }

    func deleteAll(completion: @escaping (Bool) -> Void) {
        let predicate = NSPredicate(value: true)
        let query = CKQuery(recordType: recordType, predicate: predicate)
        var recordIDsToDelete: [CKRecord.ID] = []

        let operation = CKQueryOperation(query: query)
        operation.recordMatchedBlock = { recordID, result in
            switch result {
            case .success:
                recordIDsToDelete.append(recordID)
            case .failure(let error):
                print("❌ Error matching record for deletion: \(error.localizedDescription)")
            }
        }

        operation.queryResultBlock = { result in
            if recordIDsToDelete.isEmpty {
                DispatchQueue.main.async {
                    print("🧹 No records to delete.")
                    completion(true)
                }
                return
            }

            let deleteOperation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: recordIDsToDelete)
            deleteOperation.modifyRecordsResultBlock = { result in
                DispatchQueue.main.async {
                    switch result {
                    case .failure(let error):
                        print("❌ Error deleting records: \(error.localizedDescription)")
                        completion(false)
                    case .success:
                        print("🗑️ Deleted \(recordIDsToDelete.count) records from CloudKit.")
                        completion(true)
                    }
                }
            }
            self.database.add(deleteOperation)
        }

        database.add(operation)
    }
    
    func deleteByName(_ name: String, completion: @escaping (Bool) -> Void) {
        let predicate = NSPredicate(format: "name == %@", name)
        let query = CKQuery(recordType: recordType, predicate: predicate)

        let operation = CKQueryOperation(query: query)
        operation.resultsLimit = 1

        var matchedID: CKRecord.ID?

        operation.recordMatchedBlock = { recordID, result in
            switch result {
            case .success:
                matchedID = recordID
            case .failure(let error):
                print("❌ Failed to find record to delete: \(error.localizedDescription)")
            }
        }

        operation.queryResultBlock = { result in
            DispatchQueue.main.async {
                guard let recordID = matchedID else {
                    print("⚠️ No matching record ID found for name: \(name)")
                    completion(false)
                    return
                }

                self.database.delete(withRecordID: recordID) { _, error in
                    DispatchQueue.main.async {
                        if let error = error {
                            print("❌ Error deleting record by name: \(error.localizedDescription)")
                            completion(false)
                        } else {
                            print("🗑️ Deleted record with name: \(name)")
                            completion(true)
                        }
                    }
                }
            }
        }

        database.add(operation)
    }

    func saveScore(entry: LifeScoreboardViewModel.ScoreEntry, pending: Int, projected: Double) {
        let predicate = NSPredicate(format: "name == %@", entry.name)
        let query = CKQuery(recordType: scoreRecordType, predicate: predicate)
        database.fetch(withQuery: query) { result in
            switch result {
            case .success(let (matchResults, _)):
                let records = matchResults.compactMap { _, result in
                    try? result.get()
                }

                let record = records.first ?? CKRecord(recordType: self.scoreRecordType)
                record["name"] = entry.name as CKRecordValue
                record["score"] = entry.score as CKRecordValue
                record["pending"] = pending as CKRecordValue
                record["projected"] = projected as CKRecordValue

                self.database.save(record) { _, error in
                    if let error = error {
                        print("❌ Error saving score: \(error.localizedDescription)")
                    }
                }

            case .failure(let error):
                print("❌ Query failed: \(error.localizedDescription)")
            }
        }
    }

    func createScoreRecord(for name: String) {
        let record = CKRecord(recordType: scoreRecordType)
        record["name"] = name as CKRecordValue
        record["score"] = 0 as CKRecordValue
        record["pending"] = 0 as CKRecordValue
        record["projected"] = 0.0 as CKRecordValue
        database.save(record) { _, error in
            if let error = error {
                print("❌ Error creating score record: \(error.localizedDescription)")
            } else {
                print("✅ Created score record for \(name)")
            }
        }
    }

    func deleteScoreRecord(for name: String) {
        let predicate = NSPredicate(format: "name == %@", name)
        let query = CKQuery(recordType: scoreRecordType, predicate: predicate)
        let operation = CKQueryOperation(query: query)
        operation.resultsLimit = 1

        var matchedID: CKRecord.ID?
        operation.recordMatchedBlock = { recordID, result in
            if case .success = result {
                matchedID = recordID
            }
        }

        operation.queryResultBlock = { [weak self] _ in
            guard let self = self, let id = matchedID else { return }
            self.database.delete(withRecordID: id) { _, error in
                if let error = error {
                    print("❌ Error deleting score record: \(error.localizedDescription)")
                } else {
                    print("🗑️ Deleted score record for \(name)")
                }
            }
        }

        database.add(operation)
    }

    func fetchScores(for names: [String], completion: @escaping ([String: (score: Int, pending: Int, projected: Double)]) -> Void) {
        guard !names.isEmpty else {
            completion([:])
            return
        }
        let predicate = NSPredicate(format: "name IN %@", names)
        let query = CKQuery(recordType: scoreRecordType, predicate: predicate)

        var results: [String: (Int, Int, Double)] = [:]
        let operation = CKQueryOperation(query: query)
        operation.recordMatchedBlock = { _, result in
            if case .success(let record) = result {
                let name = record["name"] as? String ?? ""
                let score = record["score"] as? Int ?? 0
                let pending = record["pending"] as? Int ?? 0
                let projected = record["projected"] as? Double ?? 0.0
                results[name] = (score, pending, projected)
            }
        }

        operation.queryResultBlock = { _ in
            DispatchQueue.main.async {
                completion(results)
            }
        }

        database.add(operation)
    }

    // MARK: - User Sync

    /// Fetches all user names from CloudKit.
    static func fetchUsers(completion: @escaping ([String]) -> Void) {
        let predicate = NSPredicate(value: true)
        let query = CKQuery(recordType: userRecordType, predicate: predicate)
        CloudKitManager.container.publicCloudDatabase.perform(query, inZoneWith: nil) { records, error in
            guard let records = records, error == nil else {
                let message = error?.localizedDescription ?? "Unknown error"
                print("❌ Failed to fetch users: \(message)")
                completion([])
                return
            }
            let names = records.compactMap { $0["name"] as? String }
            print("✅ Cloud returned users: \(names)")
            completion(names.sorted())
        }
    }

    /// Saves the provided user name to CloudKit.
    static func saveUser(_ name: String, completion: @escaping () -> Void) {
        let record = CKRecord(recordType: userRecordType, recordID: CKRecord.ID(recordName: name))
        record["name"] = name as CKRecordValue
        CloudKitManager.container.publicCloudDatabase.save(record) { _, error in
            if let error = error {
                print("❌ Error saving user: \(error)")
            } else {
                print("✅ Successfully saved member: \(name)")
            }
            completion()
        }
    }

    /// Deletes the user with the given name from CloudKit.
    static func deleteUser(_ name: String) {
        let id = CKRecord.ID(recordName: name)
        CloudKitManager.container.publicCloudDatabase.delete(withRecordID: id) { _, _ in }
    }

    // MARK: - Card Sync

    /// Fetches all Win the Day cards from CloudKit.
    static func fetchCards(completion: @escaping ([Card]) -> Void) {
        let query = CKQuery(recordType: shared.cardRecordType, predicate: NSPredicate(value: true))
        CloudKitManager.container.publicCloudDatabase.perform(query, inZoneWith: nil) { records, error in
            guard let records = records, error == nil else {
                completion([])
                return
            }
            let cards = records.compactMap(Card.init)
            completion(cards)
        }
    }

    /// Saves a Win the Day card to CloudKit.
    static func saveCard(_ card: Card) {
        let record = card.toCKRecord()
        CloudKitManager.container.publicCloudDatabase.save(record) { _, _ in }
    }

}
