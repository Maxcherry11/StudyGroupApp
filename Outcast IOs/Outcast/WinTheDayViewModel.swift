import CloudKit
import Combine

class WinTheDayViewModel: ObservableObject {
    @Published var teamData: [TeamMember] = []

    private let cloudKitManager = CloudKitManager()

    func loadData() {
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
            cloudKitManager.save(member)
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
            TeamMember(id: UUID(), name: "D.J.", quotesToday: 0, salesWTD: 0, salesMTD: 0, quotesGoal: 15, salesWTDGoal: 3, salesMTDGoal: 12, emoji: "🚀", sortIndex: 0),
            TeamMember(id: UUID(), name: "Ron", quotesToday: 0, salesWTD: 0, salesMTD: 0, quotesGoal: 15, salesWTDGoal: 3, salesMTDGoal: 12, emoji: "🔥", sortIndex: 1),
            TeamMember(id: UUID(), name: "Deanna", quotesToday: 0, salesWTD: 0, salesMTD: 0, quotesGoal: 15, salesWTDGoal: 3, salesMTDGoal: 12, emoji: "🌟", sortIndex: 2),
            TeamMember(id: UUID(), name: "Dimitri", quotesToday: 0, salesWTD: 0, salesMTD: 0, quotesGoal: 15, salesWTDGoal: 3, salesMTDGoal: 12, emoji: "💡", sortIndex: 3)
        ]
    }
}
