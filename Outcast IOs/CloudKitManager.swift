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
            case .success:
                let generatedID = UUID()
                let member = TeamMember(
                    id: generatedID,
                    name: "Placeholder",
                    quotesToday: 0,
                    salesWTD: 0,
                    salesMTD: 0,
                    quotesGoal: 10,
                    salesWTDGoal: 5,
                    salesMTDGoal: 20
                )
                fetchedMembers.append(member)
            case .failure(let error):
                print("❌ Failed to match record:", error.localizedDescription)
            }
        }

        operation.queryResultBlock = { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.team = fetchedMembers
                    completion(fetchedMembers)
                case .failure(let error):
                    print("❌ CloudKit query failed:", error.localizedDescription)
                    completion([])
                }
            }
        }

        database.add(operation)
    }

    func save(_ member: TeamMember) {
        let recordID = CKRecord.ID(recordName: member.id.uuidString)
        let record = CKRecord(recordType: "TeamMember", recordID: recordID)
        database.save(record) { returnedRecord, error in
            if let error = error {
                print("❌ Error saving:", error.localizedDescription)
            }
        }
    }

    func delete(_ member: TeamMember) {
        let id = CKRecord.ID(recordName: member.id.uuidString)
        database.delete(withRecordID: id) { _, error in
            if let error = error {
                print("❌ Error deleting:", error.localizedDescription)
            }
        }
    }
}
