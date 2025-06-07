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
            DispatchQueue.main.async {
                guard let records = records else {
                    print("❌ Load error: \(error?.localizedDescription ?? \"Unknown error\")")
                    return
                }

                let loadedEntries = records.map { record -> ScoreEntry in
                    ScoreEntry(
                        name: record["name"] as? String ?? "",
                        score: record["score"] as? Int ?? 0
                    )
                }
                self.scores = loadedEntries

                let rows = loadedEntries.map { entry in
                    let row = ActivityRow(entry: entry)
                    if let record = records.first(where: { $0["name"] as? String == entry.name }) {
                        row.pending = record["pending"] as? Int ?? 0
                        row.projected = record["projected"] as? Double ?? 0.0
                    }
                    return row
                }
                self.activity = rows
                print("✅ Loaded \(rows.count) records from CloudKit")
            }
        }
    }

    func save(_ entry: ScoreEntry, pending: Int, projected: Double) {
        let predicate = NSPredicate(format: "name == %@", entry.name)
        let query = CKQuery(recordType: recordType, predicate: predicate)

        container.publicCloudDatabase.perform(query, inZoneWith: nil) { records, error in
            let record = records?.first ?? CKRecord(recordType: self.recordType)
            record["name"] = entry.name as CKRecordValue
            record["score"] = entry.score as CKRecordValue
            record["pending"] = pending as CKRecordValue
            record["projected"] = projected as CKRecordValue

            self.container.publicCloudDatabase.save(record) { _, error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("❌ Save error: \(error.localizedDescription)")
                    } else {
                        print("✅ Saved \(entry.name)")
                        self.load()
                    }
                }
            }
        }
    }
}

