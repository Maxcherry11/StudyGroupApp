import SwiftUI
import Combine

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

    @Published var scores: [ScoreEntry] = []

    let onTime: Double = 17.7
    let travel: Double = 31.0

    @Published var activity: [ActivityRow] = []
    @Published var selectedScoreEntry: ScoreEntry?
    @Published var selectedActivityRow: ActivityRow?

    private var cancellables: Set<AnyCancellable> = []

    init() {
        updateFromUsers(UserManager.shared.allUsers)

        UserManager.shared.$allUsers
            .sink { [weak self] names in
                self?.updateFromUsers(names)
            }
            .store(in: &cancellables)
    }

    private func updateFromUsers(_ names: [String]) {
        var newScores: [ScoreEntry] = []
        var newActivity: [ActivityRow] = []

        for name in names {
            let score = scores.first(where: { $0.name == name })?.score ?? 0
            let scoreEntry = ScoreEntry(name: name, score: score)

            let existingRow = activity.first(where: { $0.name == name })
            let pending = existingRow?.pending ?? 0
            let projected = existingRow?.projected ?? 0
            let row = ActivityRow(name: name, pending: pending, projected: projected)
            row.entries = [scoreEntry]

            newScores.append(scoreEntry)
            newActivity.append(row)
        }

        DispatchQueue.main.async {
            self.scores = newScores
            self.activity = newActivity
        }
    }

    func score(for name: String) -> Int {
        scores.first(where: { $0.name == name })?.score ?? 0
    }

    func row(for name: String) -> ActivityRow? {
        activity.first(where: { $0.name == name })
    }
}
