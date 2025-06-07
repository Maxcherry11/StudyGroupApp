import CloudKit
import Foundation

class LifeScoreboardViewModel: ObservableObject {
    private let container = CKContainer.default()
    private let recordType = "ScoreRecord"

    @Published var scores: [ScoreEntry] = []
    @Published var activity: [ActivityRow] = []
    @Published var onTime: Double = 17.7
    @Published var travel: Double = 31.0

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

        init(name: String, score: Int, pending: Int, projected: Double) {
            self.name = name
            self.entries = [ScoreEntry(name: name, score: score)]
            self.pending = pending
            self.projected = projected
        }
    }

    func score(for name: String) -> Int {
        if let entry = entry(for: name) {
            return entry.score
        }
        return 0
    }

    func entry(for name: String) -> ScoreEntry? {
        return scores.first(where: { $0.name == name })
    }

    func row(for name: String) -> ActivityRow? {
        activity.first(where: { $0.name == name })
    }

    private func updateLocalEntries(names: [String]) {
        // Remove entries for deleted users
        scores.removeAll { entry in !names.contains(entry.name) }
        activity.removeAll { row in !names.contains(row.name) }

        // Add entries for new users
        for name in names where !scores.contains(where: { $0.name == name }) {
            let entry = ScoreEntry(name: name, score: 0)
            scores.append(entry)
            let row = ActivityRow(name: name, score: 0, pending: 0, projected: 0)
            row.entries = [entry]
            activity.append(row)
        }
    }

    func load(for names: [String]) {
        updateLocalEntries(names: names)
        CloudKitManager.shared.fetchScores(for: names) { records in
            for (name, values) in records {
                if let index = self.scores.firstIndex(where: { $0.name == name }) {
                    self.scores[index].score = values.score
                }
                if let row = self.activity.first(where: { $0.name == name }) {
                    row.pending = values.pending
                    row.projected = values.projected
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

    func createTestScoreRecord() {
        let record = CKRecord(recordType: recordType)
        record["name"] = "D.J." as CKRecordValue
        record["score"] = 5 as CKRecordValue
        record["pending"] = 2 as CKRecordValue
        record["projected"] = 100.0 as CKRecordValue

        container.publicCloudDatabase.save(record) { _, error in
            if let error = error {
                print("❌ Error saving test record: \(error.localizedDescription)")
            } else {
                print("✅ Test record saved to CloudKit")
            }
        }
    }
}
