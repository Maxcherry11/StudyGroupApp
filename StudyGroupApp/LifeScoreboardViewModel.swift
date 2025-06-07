import CloudKit
import SwiftUI

class LifeScoreboardViewModel: ObservableObject {
    @Published var scores: [ScoreEntry] = []
    @Published var activity: [ActivityRow] = []
    @Published var onTime: Double = 17.7
    @Published var travel: Double = 31.0

    private let container = CKContainer.default()
    private let recordType = "LifeScoreEntry"

    struct ScoreEntry: Identifiable, Hashable {
        var id = UUID()
        var name: String
        var score: Int
    }

    class ActivityRow: ObservableObject, Identifiable {
        let id = UUID()
        let name: String
        var entries: [ScoreEntry]
        @Published var pending: Int
        @Published var projected: Double

        init(entry: ScoreEntry) {
            self.name = entry.name
            self.entries = [entry]
            self.pending = 0
            self.projected = 0.0
        }

        init(name: String, pending: Int, projected: Double) {
            self.name = name
            self.entries = [ScoreEntry(name: name, score: 0)]
            self.pending = pending
            self.projected = projected
        }
    }

    func score(for name: String) -> Int {
        scores.first(where: { $0.name == name })?.score ?? 0
    }

    func row(for name: String) -> ActivityRow? {
        activity.first(where: { $0.name == name })
    }

    func load() {
        print("🔄 Fetching from CloudKit...")
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        container.publicCloudDatabase.perform(query, inZoneWith: nil) { records, error in
            guard let records = records else {
                DispatchQueue.main.async {
                    print("❌ Load error: \(error?.localizedDescription ?? \"Unknown error\")")
                }
                return
            }

            let loadedEntries = records.map { record -> ScoreEntry in
                ScoreEntry(
                    name: record["name"] as? String ?? "",
                    score: record["score"] as? Int ?? 0
                )
            }
            let loadedActivity = records.map { record -> ActivityRow in
                ActivityRow(
                    name: record["name"] as? String ?? "",
                    pending: record["pending"] as? Int ?? 0,
                    projected: record["projected"] as? Double ?? 0.0
                )
            }

            DispatchQueue.main.async {
                self.scores = loadedEntries
                self.activity = loadedActivity
            }
        }
    }
        }
    func save(_ entry: ScoreEntry, pending: Int, projected: Double) {
        guard let index = scores.firstIndex(where: { $0.name == entry.name }) else { return }
        scores[index].score = entry.score

        if let rowIndex = activity.firstIndex(where: { $0.name == entry.name }) {
            activity[rowIndex].pending = pending
            activity[rowIndex].projected = projected
        }

        CloudKitManager.shared.saveScore(entry: entry, pending: pending, projected: projected)
    }
}

