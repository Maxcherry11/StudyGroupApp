import Foundation
import CloudKit

class WinTheDayViewModel: ObservableObject {
    @Published var teamData: [TeamMember] = []
    private var database = CKContainer.default().publicCloudDatabase

    init() {
        fetchTeamMembers()
    }

    func loadData() {
        fetchTeamMembers()
    }

    func fetchTeamMembers() {
        let query = CKQuery(recordType: "TeamMember", predicate: NSPredicate(value: true))
        database.perform(query, inZoneWith: nil) { records, error in
            if let records = records {
                DispatchQueue.main.async {
                    self.teamData = records.compactMap { TeamMember(record: $0) }
                }
            }
        }
    }

    func wipeAndResetCloudKit() {
        let query = CKQuery(recordType: "TeamMember", predicate: NSPredicate(value: true))
        database.perform(query, inZoneWith: nil) { records, error in
            if let records = records {
                let operations = records.map { CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: [$0.recordID]) }
                let operationQueue = OperationQueue()
                operationQueue.addOperations(operations, waitUntilFinished: true)

                DispatchQueue.main.async {
                    self.teamData.removeAll()
                    // Add any default team members or reset logic here
                }
            }
        }
    }
}
