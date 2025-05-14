import CloudKit
import Combine

class WinTheDayViewModel: ObservableObject {
    @Published var teamData: [TeamMember] = []

    private let cloudKitManager = CloudKitManager()

    func loadData() {
        // wipeAndResetCloudKit()
        // return
        cloudKitManager.fetchAll { [weak self] members in
            DispatchQueue.main.async {
                if members.isEmpty {
                    let defaults = self?.createDefaultTeam() ?? []
                    self?.teamData = defaults
                    self?.saveData()
                } else {
                    self?.teamData = members.sorted(by: { $0.sortIndex < $1.sortIndex })
                }
            }
        }
    }

    func saveData() {
        for member in teamData {
            cloudKitManager.save(member) { recordID in
                if let idString = recordID?.recordName,
                   let index = self.teamData.firstIndex(where: { $0.name == member.name }) {
                    self.teamData[index].id = UUID(uuidString: idString) ?? self.teamData[index].id
                }
            }
        }
    }

    func resetAllProgress() {
        for index in teamData.indices {
            teamData[index].quotesToday = 0
            teamData[index].salesWTD = 0
            teamData[index].salesMTD = 0
        }
        saveData()
    }

    private func createDefaultTeam() -> [TeamMember] {
        return [
            TeamMember(name: "D.J.", quotesToday: 0, salesWTD: 0, salesMTD: 0, quotesGoal: 15, salesWTDGoal: 3, salesMTDGoal: 12, emoji: "🚀", sortIndex: 0),
            TeamMember(name: "Ron", quotesToday: 0, salesWTD: 0, salesMTD: 0, quotesGoal: 15, salesWTDGoal: 3, salesMTDGoal: 12, emoji: "🔥", sortIndex: 1),
            TeamMember(name: "Deanna", quotesToday: 0, salesWTD: 0, salesMTD: 0, quotesGoal: 15, salesWTDGoal: 3, salesMTDGoal: 12, emoji: "🌟", sortIndex: 2),
            TeamMember(name: "Dimitri", quotesToday: 0, salesWTD: 0, salesMTD: 0, quotesGoal: 15, salesWTDGoal: 3, salesMTDGoal: 12, emoji: "💡", sortIndex: 3)
        ]
    }

    /// Wipes all TeamMember records from CloudKit and reinserts the default users under the current iCloud account.
    public func wipeAndResetCloudKit() {
        cloudKitManager.deleteAll { [weak self] success in
            guard success else {
                print("❌ Failed to delete records.")
                return
            }
            DispatchQueue.main.async {
                let defaults = self?.createDefaultTeam() ?? []
                self?.teamData = defaults
                self?.saveData()
                print("🧹 CloudKit reset complete. Default team re-added.")
            }
        }
    }
}
