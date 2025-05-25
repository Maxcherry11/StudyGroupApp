import Foundation
import CloudKit

class WinTheDayViewModel: ObservableObject {
    @Published var teamData: [TeamMember] = []

    init() {
        self.teamMembers = TeamMember.testMembers
    }
    @Published var teamMembers: [TeamMember] = []
    @Published var selectedUserName: String = ""

    #if !DEBUG
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

        print("📡 Starting loadData CloudKit operation...")
        CKContainer.default().publicCloudDatabase.add(operation)
    }
    #endif

    func fetchTeamMembers() {
        let query = CKQuery(recordType: "TeamMember", predicate: NSPredicate(value: true))
        // CloudKit code removed for local/debug use
    }

    func wipeAndResetCloudKit() {
        let query = CKQuery(recordType: "TeamMember", predicate: NSPredicate(value: true))
        // CloudKit code removed for local/debug use
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

        let records = membersToUpload.compactMap { $0.toRecord() }

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
