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

    func save(_ member: TeamMember) {
        let recordID = CKRecord.ID(recordName: member.id.uuidString)
        let record = CKRecord(recordType: "TeamMember", recordID: recordID)
        record["name"] = member.name as NSString
        record["quotesToday"] = member.quotesToday as NSNumber
        record["salesWTD"] = member.salesWTD as NSNumber
        record["salesMTD"] = member.salesMTD as NSNumber
        record["quotesGoal"] = member.quotesGoal as NSNumber
        record["salesWTDGoal"] = member.salesWTDGoal as NSNumber
        record["salesMTDGoal"] = member.salesMTDGoal as NSNumber
        record["emoji"] = member.emoji as NSString
        record["sortIndex"] = member.sortIndex as NSNumber
        database.save(record) { _, error in
            if let error = error {
                print("❌ Error saving: \(error.localizedDescription)")
            }
        }
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
}
