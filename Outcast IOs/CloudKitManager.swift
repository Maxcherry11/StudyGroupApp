import CloudKit
import Foundation

class CloudKitManager: ObservableObject {
    private let database = CKContainer.default().privateCloudDatabase
    private let recordType = "TeamMember"

    @Published var team: [TeamMember] = []

    func fetchTeam(completion: @escaping ([TeamMember]) -> Void) {
        let predicate = NSPredicate(value: true)
        let query = CKQuery(recordType: recordType, predicate: predicate)

        var fetchedMembers: [TeamMember] = []

        let operation = CKQueryOperation(query: query)
        operation.recordMatchedBlock = { recordID, result in
            switch result {
            case .success(let record):
                let member = TeamMember(
                    id: UUID(uuidString: record.recordID.recordName) ?? UUID(),
                    name: record["name"] as? String ?? "",
                    quotesToday: record["quotesToday"] as? Int ?? 0,
                    salesWTD: record["salesWTD"] as? Int ?? 0,
                    salesMTD: record["salesMTD"] as? Int ?? 0,
                    quotesGoal: record["quotesGoal"] as? Int ?? 10,
                    salesWTDGoal: record["salesWTDGoal"] as? Int ?? 2,
                    salesMTDGoal: record["salesMTDGoal"] as? Int ?? 8,
                    emoji: record["emoji"] as? String ?? "🙂",
                    sortIndex: record["sortIndex"] as? Int ?? 0
                )
                fetchedMembers.append(member)
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
        let record: CKRecord
        if member.id.uuidString.count == 36 {
            let recordID = CKRecord.ID(recordName: member.id.uuidString)
            record = CKRecord(recordType: recordType, recordID: recordID)
        } else {
            record = CKRecord(recordType: recordType)
        }
        record["name"] = member.name as NSString
        record["quotesToday"] = member.quotesToday as NSNumber
        record["salesWTD"] = member.salesWTD as NSNumber
        record["salesMTD"] = member.salesMTD as NSNumber
        record["quotesGoal"] = member.quotesGoal as NSNumber
        record["salesWTDGoal"] = member.salesWTDGoal as NSNumber
        record["salesMTDGoal"] = member.salesMTDGoal as NSNumber
        record["emoji"] = member.emoji as NSString
        record["sortIndex"] = member.sortIndex as NSNumber
        print("💾 Saving member to CloudKit: \(member.name)")
        
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
        database.add(modifyOperation)
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
