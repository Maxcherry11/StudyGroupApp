import Foundation
import CloudKit

class WinTheDayViewModel: ObservableObject {
    @Published var teamData: [TeamMember] = []
    private var database = CKContainer.default().publicCloudDatabase

    init() {
        fetchTeamMembers()
    }
    @Published var teamMembers: [TeamMember] = []
    @Published var selectedUserName: String = ""

    func loadData() {
        print("🔄 loadData() called")
        let predicate = NSPredicate(value: true)
        let query = CKQuery(recordType: "TeamMember", predicate: predicate)
        let operation = CKQueryOperation(query: query)

        var loadedMembers: [TeamMember] = []

        operation.recordFetchedBlock = { record in
            if let member = TeamMember(record: record) {
                loadedMembers.append(member)
            }
        }

        operation.queryCompletionBlock = { [weak self] (_, error) in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ CloudKit query failed:", error.localizedDescription)
                } else {
                    print("✅ Loaded \(loadedMembers.count) records from CloudKit")
                    self?.teamMembers = loadedMembers
                }
            }
        }

        CKContainer.default().publicCloudDatabase.add(operation)
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

    var filteredMembers: [TeamMember] {
        teamMembers.filter {
            guard let name = $0.name.lowercased().replacingOccurrences(of: ".", with: "") as String? else {
                return false
            }
            return name == selectedUserName.lowercased().replacingOccurrences(of: ".", with: "")
        }
    }

    func uploadTestMembersToCloudKit() {
        print("📤 Uploading all team members to CloudKit...")

        let membersToUpload = TeamMember.testMembers

        let records = membersToUpload.compactMap { $0.toCKRecord() }

        let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
        operation.modifyRecordsCompletionBlock = { saved, _, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Upload failed: \(error.localizedDescription)")
                } else {
                    print("✅ Uploaded \(saved?.count ?? 0) members to CloudKit.")
                }
            }
        }

        CKContainer.default().publicCloudDatabase.add(operation)
    }
} // End of class WinTheDayViewModel

#if DEBUG
extension TeamMember {
    static let testMembers: [TeamMember] = [
        TeamMember(
            name: "D.J.",
            quotesToday: 0,
            salesWTD: 0,
            salesMTD: 0,
            quotesGoal: 5,
            salesWTDGoal: 3,
            salesMTDGoal: 6,
            emoji: "🧠",
            sortIndex: 0
        ),
        TeamMember(
            name: "Ron",
            quotesToday: 0,
            salesWTD: 0,
            salesMTD: 0,
            quotesGoal: 2,
            salesWTDGoal: 1,
            salesMTDGoal: 4,
            emoji: "🏌️",
            sortIndex: 1
        ),
        TeamMember(
            name: "Deanna",
            quotesToday: 0,
            salesWTD: 0,
            salesMTD: 0,
            quotesGoal: 3,
            salesWTDGoal: 2,
            salesMTDGoal: 5,
            emoji: "🎯",
            sortIndex: 2
        ),
        TeamMember(
            name: "Dimitri",
            quotesToday: 0,
            salesWTD: 0,
            salesMTD: 0,
            quotesGoal: 4,
            salesWTDGoal: 2,
            salesMTDGoal: 5,
            emoji: "🚀",
            sortIndex: 3
        )
    ]
}
#endif
