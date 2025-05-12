import Foundation
import CloudKit

class WinTheDayViewModel: ObservableObject {
    @Published var teamData: [TeamMember] = []
    private let manager = CloudKitManager()

    init() {
        print("✅ WinTheDayViewModel initialized")
        loadData()
    }

    func loadData() {
        manager.fetchTeam { [weak self] members in
            DispatchQueue.main.async {
                self?.teamData = members
                self?.teamData.sort { $0.sortIndex < $1.sortIndex }
                print("📦 Loaded cards count: \(self?.teamData.count ?? 0)")
            }
        }
    }

    func saveData(completion: (() -> Void)? = nil) {
        for (index, member) in teamData.enumerated() {
            member.sortIndex = index
            manager.save(member)
        }
        completion?()
    }

    func resetAllProgress() {
        for member in teamData {
            member.quotesToday = 0
            member.salesWTD = 0
            member.salesMTD = 0
        }
        saveData()
    }
}
