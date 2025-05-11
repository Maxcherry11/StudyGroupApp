import SwiftUI
import CloudKit

class WinTheDayViewModel: ObservableObject {
    @Published var teamData: [TeamMember] = []

    init() {
        self.teamData = [
            TeamMember(name: "D.J.", quotesToday: 3, salesWTD: 1, salesMTD: 4, quotesGoal: 10, salesWTDGoal: 2, salesMTDGoal: 8),
            TeamMember(name: "Ron", quotesToday: 6, salesWTD: 2, salesMTD: 7, quotesGoal: 10, salesWTDGoal: 2, salesMTDGoal: 8),
            TeamMember(name: "Deanna", quotesToday: 2, salesWTD: 1, salesMTD: 3, quotesGoal: 10, salesWTDGoal: 2, salesMTDGoal: 8),
            TeamMember(name: "Dimitri", quotesToday: 5, salesWTD: 3, salesMTD: 6, quotesGoal: 10, salesWTDGoal: 2, salesMTDGoal: 8)
        ]
    }

    func loadData() {
        let manager = CloudKitManager()
        manager.fetchTeam { members in
            DispatchQueue.main.async {
                self.teamData = members
            }
        }
    }

    func saveData() {
        let manager = CloudKitManager()
        for member in teamData {
            manager.save(member)
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
}
