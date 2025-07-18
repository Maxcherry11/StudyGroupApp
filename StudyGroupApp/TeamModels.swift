import Foundation

struct GoalProgress: Identifiable {
    let id = UUID()
    var title: String
    var percent: Double
}

extension GoalProgress: Equatable {}

