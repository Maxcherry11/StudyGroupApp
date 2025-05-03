import Foundation
import CloudKit

class WinTheDayViewModel: ObservableObject {
    @Published var teamData: [TeamMember] = []
    private let publicDatabase = CKContainer.default().publicCloudDatabase

    init() {
        loadData()
    }

    func loadData() {
        if let data = UserDefaults.standard.data(forKey: "teamData"),
           let decoded = try? JSONDecoder().decode([TeamMember].self, from: data) {
            teamData = decoded
        } else {
            teamData = [
                TeamMember(name: "D.J.", quotesToday: 0, salesWTD: 8, salesMTD: 20, quotesGoal: 10, salesWTDGoal: 2, salesMTDGoal: 8),
                TeamMember(name: "Deanna", quotesToday: 4, salesWTD: 4, salesMTD: 14, quotesGoal: 10, salesWTDGoal: 2, salesMTDGoal: 8),
                TeamMember(name: "Dimitri", quotesToday: 0, salesWTD: 9, salesMTD: 24, quotesGoal: 10, salesWTDGoal: 2, salesMTDGoal: 8),
                TeamMember(name: "Ron", quotesToday: 0, salesWTD: 0, salesMTD: 0, quotesGoal: 10, salesWTDGoal: 2, salesMTDGoal: 8)
            ]
        }
    }

    func saveData() {
        if let encoded = try? JSONEncoder().encode(teamData) {
            UserDefaults.standard.set(encoded, forKey: "teamData")
        }

        for member in teamData {
            let record = CKRecord(recordType: "TeamMember")
            record["name"] = member.name as NSString
            record["quotesToday"] = member.quotesToday as NSNumber
            record["quotesGoal"] = member.quotesGoal as NSNumber
            record["salesWTD"] = member.salesWTD as NSNumber
            record["salesWTDGoal"] = member.salesWTDGoal as NSNumber
            record["salesMTD"] = member.salesMTD as NSNumber
            record["salesMTDGoal"] = member.salesMTDGoal as NSNumber

            publicDatabase.save(record) { _, error in
                if let error = error {
                    print("Error saving to CloudKit: \(error.localizedDescription)")
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
}
