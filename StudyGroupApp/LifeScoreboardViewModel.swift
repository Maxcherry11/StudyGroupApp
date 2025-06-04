import SwiftUI

class LifeScoreboardViewModel: ObservableObject {
    class ScoreEntry: ObservableObject, Identifiable {
        let id = UUID()
        let name: String
        @Published var score: Int

        var color: Color {
            switch score {
            case 40...: return .green
            case 20..<40: return .yellow
            default: return .gray
            }
        }

        init(name: String, score: Int) {
            self.name = name
            self.score = score
        }
    }

    class ActivityRow: ObservableObject, Identifiable {
        let id = UUID()
        let name: String
        @Published var pending: Int
        @Published var projected: Double

        init(name: String, pending: Int, projected: Double) {
            self.name = name
            self.pending = pending
            self.projected = projected
        }
    }

    @Published var scores: [ScoreEntry] = [
        ScoreEntry(name: "Dimitri", score: 47),
        ScoreEntry(name: "Deanna", score: 38),
        ScoreEntry(name: "D.J.", score: 16),
        ScoreEntry(name: "Ron", score: 0),
        ScoreEntry(name: "Greg", score: 7)
    ]

    let onTime: Double = 17.7
    let travel: Double = 31.0

    @Published var activity: [ActivityRow] = [
        ActivityRow(name: "Deanna", pending: 3, projected: 28083),
        ActivityRow(name: "D.J.", pending: 6, projected: 19315),
        ActivityRow(name: "Dimitri", pending: 0, projected: 51856),
        ActivityRow(name: "Greg", pending: 3, projected: 0)
    ]
    @Published var selectedScoreEntry: ScoreEntry?
    @Published var selectedActivityRow: ActivityRow?
}
