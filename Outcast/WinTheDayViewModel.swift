import Foundation
import CloudKit

class WinTheDayViewModel: ObservableObject {
    @Published var teamData: [TeamMember] = []
    /// Use the Outcast container explicitly for all sync operations.
    private let database = CKContainer(identifier: "iCloud.com.dj.Outcast").publicCloudDatabase

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

        database.add(operation)
    }

    func fetchTeamMembers() {
        let query = CKQuery(recordType: "TeamMember", predicate: NSPredicate(value: true))
        database.fetch(withQuery: query,
                       inZoneWith: nil,
                       desiredKeys: nil,
                       resultsLimit: CKQueryOperation.maximumResults) { result in
            switch result {
            case .success(let (matchResults, _)):
                let records = matchResults.compactMap { _, recordResult in
                    try? recordResult.get()
                }
                DispatchQueue.main.async {
                    self.teamData = records.compactMap { TeamMember(record: $0) }
                }
            case .failure:
                break
            }
        }
    }

    func wipeAndResetCloudKit() {
        let query = CKQuery(recordType: "TeamMember", predicate: NSPredicate(value: true))
        database.fetch(withQuery: query,
                       inZoneWith: nil,
                       desiredKeys: nil,
                       resultsLimit: CKQueryOperation.maximumResults) { result in
            switch result {
            case .success(let (matchResults, _)):
                let records = matchResults.compactMap { _, recordResult in
                    try? recordResult.get()
                }
                let operations = records.map { CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: [$0.recordID]) }
                let operationQueue = OperationQueue()
                operationQueue.addOperations(operations, waitUntilFinished: true)

                DispatchQueue.main.async {
                    self.teamData.removeAll()
                    // Add any default team members or reset logic here
                }
            case .failure:
                break
            }
        }
    }

    var filteredMembers: [TeamMember] {
        teamMembers
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

        database.add(operation)
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
