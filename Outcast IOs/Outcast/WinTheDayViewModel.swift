import CloudKit
import Combine

class WinTheDayViewModel: ObservableObject {
    @Published var teamData: [TeamMember] = []

    private let cloudKitManager = CloudKitManager()

    func loadData() {
        cloudKitManager.fetchAll { [weak self] members in
            DispatchQueue.main.async {
                self?.teamData = members.sorted(by: { $0.sortIndex < $1.sortIndex })
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
}
