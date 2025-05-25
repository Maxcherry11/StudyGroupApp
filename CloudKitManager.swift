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
                let record = member.toRecord(existing: matchedRecord)

                let modifyOperation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
                modifyOperation.modifyRecordsCompletionBlock = { savedRecords, _, error in
                    DispatchQueue.main.async {
                        if let error = error {
                            print("❌ Error saving: \(error.localizedDescription)")
                            completion(nil)
                        } else if let savedRecord = savedRecords?.first {
                            print("✅ Successfully saved member: \(member.name) with ID: \(savedRecord.recordID.recordName)")
                            completion(savedRecord.recordID)
                        } else {
                            print("⚠️ Save completed but no record returned.")
                            completion(nil)
                        }
                    }
                }

                self.database.add(modifyOperation)
            }
        }

        database.add(operation)
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
            deleteOperation.modifyRecordsCompletionBlock = { _, _, error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("❌ Error deleting records: \(error.localizedDescription)")
                        completion(false)
                    } else {
                        print("🗑️ Deleted \(recordIDsToDelete.count) records from CloudKit.")
                        completion(true)
                    }
                }
            }
            self.database.add(deleteOperation)
        }

        database.add(operation)
    }
}
