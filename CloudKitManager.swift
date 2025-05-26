import CloudKit
import Foundation

class CloudKitManager: ObservableObject {
    private let database = CKContainer(identifier: "iCloud.com.dj.Outcast").publicCloudDatabase
    private let recordType = "TeamMember"

    @Published var team: [TeamMember] = []

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
                    self.team = fetchedMembers
                    completion(fetchedMembers)
                case .failure(let error):
                    print("❌ CloudKit query failed: \(error.localizedDescription)")
                    completion([])
                }
            }
        }

        database.add(operation)
    }

    func save(_ member: TeamMember, completion: @escaping (CKRecord.ID?) -> Void) {
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
                completion(results)
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
}
