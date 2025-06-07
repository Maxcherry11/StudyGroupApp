import Foundation
import CloudKit

class WinTheDayViewModel: ObservableObject {
    @Published var teamData: [TeamMember] = []

    init() {
        self.teamMembers = TeamMember.testMembers
    }
    @Published var teamMembers: [TeamMember] = []
    @Published var selectedUserName: String = ""

    func loadData() {
        guard !selectedUserName.trimmingCharacters(in: .whitespaces).isEmpty else {
            print("⚠️ Skipping loadData: selectedUserName is empty")
            return
        }
        print("🔄 loadData() called")
        let predicate = NSPredicate(value: true)
        let query = CKQuery(recordType: "TeamMember", predicate: predicate)
        let operation = CKQueryOperation(query: query)

        var loadedMembers: [TeamMember] = []

        operation.recordMatchedBlock = { recordID, result in
            switch result {
            case .success(let record):
                if let member = TeamMember(record: record) {
                    loadedMembers.append(member)
                }
            case .failure(let error):
                print("❌ Failed to match record with ID \(recordID.recordName): \(error.localizedDescription)")
            }
        }

        operation.queryResultBlock = { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .failure(let error):
                    print("❌ CloudKit query failed:", error.localizedDescription)
                case .success:
                    print("✅ Loaded \(loadedMembers.count) records from CloudKit")
                    self?.teamMembers = loadedMembers.sorted {
                        ($0.quotesToday + $0.salesWTD + $0.salesMTD) >
                        ($1.quotesToday + $1.salesWTD + $1.salesMTD)
                    }
                }
            }
        }

        print("📡 Starting loadData CloudKit operation...")
        CKContainer(identifier: "iCloud.com.dj.Outcast").publicCloudDatabase.add(operation)
    }

    func fetchFromCloudKit() {
        CloudKitManager().fetchTeam { [weak self] members in
            let valid = members.filter {
                !$0.name.trimmingCharacters(in: .whitespaces).isEmpty &&
                $0.quotesGoal > 0 &&
                $0.salesWTDGoal > 0 &&
                $0.salesMTDGoal > 0
            }
            guard !valid.isEmpty else {
                print("⚠️ Fetched data invalid or empty; keeping existing data")
                return
            }
            DispatchQueue.main.async {
                self?.teamMembers = valid.sorted { $0.sortIndex < $1.sortIndex }
            }
        }
    }

    func fetchTeamMembers() {
        // CloudKit code removed for local/debug use
    }

    func wipeAndResetCloudKit() {
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
        operation.modifyRecordsResultBlock = { result in
            DispatchQueue.main.async {
                switch result {
                case .failure(let error):
                    print("❌ Upload failed: \(error.localizedDescription)")
                case .success:
                    print("✅ Uploaded all test members to CloudKit.")
                }
            }
        }

        CKContainer(identifier: "iCloud.com.dj.Outcast").publicCloudDatabase.add(operation)
    }
} // End of class WinTheDayViewModel

extension TeamMember {
    static let testMembers: [TeamMember] = [
        TeamMember(
            name: "D.J.",
            quotesToday: 0,
            salesWTD: 0,
            salesMTD: 0,
            quotesGoal: 10,
            salesWTDGoal: 2,
            salesMTDGoal: 6,
            emoji: "🧠",
            sortIndex: 0
        ),
        TeamMember(
            name: "Ron",
            quotesToday: 0,
            salesWTD: 0,
            salesMTD: 0,
            quotesGoal: 10,
            salesWTDGoal: 2,
            salesMTDGoal: 6,
            emoji: "🏌️",
            sortIndex: 1
        ),
        TeamMember(
            name: "Deanna",
            quotesToday: 0,
            salesWTD: 0,
            salesMTD: 0,
            quotesGoal: 10,
            salesWTDGoal: 2,
            salesMTDGoal: 6,
            emoji: "🎯",
            sortIndex: 2
        ),
        TeamMember(
            name: "Dimitri",
            quotesToday: 0,
            salesWTD: 0,
            salesMTD: 0,
            quotesGoal: 10,
            salesWTDGoal: 2,
            salesMTDGoal: 6,
            emoji: "🚀",
            sortIndex: 3
        )
    ]
}
