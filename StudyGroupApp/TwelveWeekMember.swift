import Foundation

/// A team member's progress for the 12 Week Year feature.
///
/// Stores the member name and their collection of `GoalProgress` entries.
/// Provides a computed `progress` value representing the average percent
/// complete for all associated goals.
struct TwelveWeekMember: Identifiable {
    /// Stable identifier for binding and list use.
    var id = UUID()

    /// Display name for the team member.
    var name: String

    /// Collection of progress objects for each goal.
    var goals: [GoalProgress]

    /// Average completion across all goals as a value between 0 and 1.
    var progress: Double {
        guard !goals.isEmpty else { return 0 }
        return goals.map { $0.percent }.reduce(0, +) / Double(goals.count)
    }
}

extension TwelveWeekMember: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        for goal in goals {
            hasher.combine(goal.title)
            hasher.combine(goal.percent)
        }
    }

    static func == (lhs: TwelveWeekMember, rhs: TwelveWeekMember) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.goals == rhs.goals
    }
}
