import SwiftUI

class LifeScoreboardViewModel: ObservableObject {
    class ScoreEntry: ObservableObject, Identifiable {
        let id = UUID()
        let name: String
        @Published var score: Int
        @Published var color: Color = .gray

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
        @Published var entries: [ScoreEntry] = []

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
        {
            let row = ActivityRow(name: "Deanna", pending: 3, projected: 28083)
            row.entries = [ScoreEntry(name: "Deanna", score: 38)]
            return row
        }(),
        {
            let row = ActivityRow(name: "D.J.", pending: 6, projected: 19315)
            row.entries = [ScoreEntry(name: "D.J.", score: 16)]
            return row
        }(),
        {
            let row = ActivityRow(name: "Dimitri", pending: 0, projected: 51856)
            row.entries = [ScoreEntry(name: "Dimitri", score: 47)]
            return row
        }(),
        {
            let row = ActivityRow(name: "Greg", pending: 3, projected: 0)
            row.entries = [ScoreEntry(name: "Greg", score: 7)]
            return row
        }()
    ]
    @Published var selectedScoreEntry: ScoreEntry?
    @Published var selectedActivityRow: ActivityRow?
}
