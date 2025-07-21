import Foundation

struct GoalProgress: Identifiable, Codable, Equatable {
    /// Stable identifier for each goal. Defaults to a new UUID when not provided.
    let id: UUID
    var title: String
    var percent: Double

    /// Creates a new `GoalProgress` optionally overriding the generated `id`.
    init(id: UUID = UUID(), title: String, percent: Double) {
        self.id = id
        self.title = title
        self.percent = percent
    }
}

