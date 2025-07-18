import Foundation

struct TwelveWeekMember: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var goals: [GoalProgress]

    var progress: Double {
        guard !goals.isEmpty else { return 0 }
        return goals.map { $0.percent }.reduce(0, +) / Double(goals.count)
    }
}
