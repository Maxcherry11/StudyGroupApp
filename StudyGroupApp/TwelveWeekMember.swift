import Foundation
import CloudKit

struct TwelveWeekMember: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var goals: [GoalProgress]
    var emoji: String

    var progress: Double {
        guard !goals.isEmpty else { return 0 }
        return goals.map { $0.percent }.reduce(0, +) / Double(goals.count)
    }
}
