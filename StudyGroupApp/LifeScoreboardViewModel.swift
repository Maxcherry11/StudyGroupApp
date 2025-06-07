import SwiftUI
import Combine
import CloudKit

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

    // MARK: - CloudKit Sync

    private var database: CKDatabase {
        CKContainer(identifier: "iCloud.com.dj.Outcast").publicCloudDatabase
    }

    /// Load CloudKit data for the current user and update local models
    func load() {
        let current = UserManager.shared.currentUserName
        guard !current.isEmpty else { return }

        // Fetch ScoreEntry
        let scorePredicate = NSPredicate(format: "name == %@", current)
        let scoreQuery = CKQuery(recordType: ScoreEntry.recordType, predicate: scorePredicate)
        let scoreOperation = CKQueryOperation(query: scoreQuery)

        var fetchedScore: Int?
        scoreOperation.recordMatchedBlock = { _, result in
            if case .success(let record) = result {
                fetchedScore = record["score"] as? Int
            }
        }

        scoreOperation.queryResultBlock = { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let scoreValue = fetchedScore,
                   let entry = self.scores.first(where: { $0.name == current }) {
                    entry.score = scoreValue
                }
            }
        }
        database.add(scoreOperation)

        // Fetch ActivityRow
        let activityPredicate = NSPredicate(format: "name == %@", current)
        let activityQuery = CKQuery(recordType: ActivityRow.recordType, predicate: activityPredicate)
        let activityOperation = CKQueryOperation(query: activityQuery)

        var fetchedPending: Int?
        var fetchedProjected: Double?
        activityOperation.recordMatchedBlock = { _, result in
            if case .success(let record) = result {
                fetchedPending = record["pending"] as? Int
                fetchedProjected = record["projected"] as? Double
            }
        }

        activityOperation.queryResultBlock = { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let row = self.activity.first(where: { $0.name == current }) {
                    if let p = fetchedPending { row.pending = p }
                    if let proj = fetchedProjected { row.projected = proj }
                }
            }
        }
        database.add(activityOperation)
    }

    /// Save changes for the current user to CloudKit
    func save(_ updated: ScoreEntry, for activityRow: ActivityRow) {
        let current = UserManager.shared.currentUserName
        guard updated.name == current && activityRow.name == current else { return }

        // Query for existing ScoreEntry
        let scorePredicate = NSPredicate(format: "name == %@", current)
        let scoreQuery = CKQuery(recordType: ScoreEntry.recordType, predicate: scorePredicate)
        let scoreOperation = CKQueryOperation(query: scoreQuery)
        scoreOperation.resultsLimit = 1

        var matchedScore: CKRecord?
        scoreOperation.recordMatchedBlock = { _, result in
            if case .success(let record) = result { matchedScore = record }
        }

        scoreOperation.queryResultBlock = { [weak self] _ in
            guard let self = self else { return }
            // Query for existing ActivityRow
            let activityPredicate = NSPredicate(format: "name == %@", current)
            let activityQuery = CKQuery(recordType: ActivityRow.recordType, predicate: activityPredicate)
            let activityOperation = CKQueryOperation(query: activityQuery)
            activityOperation.resultsLimit = 1

            var matchedActivity: CKRecord?
            activityOperation.recordMatchedBlock = { _, result in
                if case .success(let record) = result { matchedActivity = record }
            }

            activityOperation.queryResultBlock = { _ in
                let scoreRecord = updated.toRecord(existing: matchedScore)
                let activityRecord = activityRow.toRecord(existing: matchedActivity)

                let modify = CKModifyRecordsOperation(recordsToSave: [scoreRecord, activityRecord], recordIDsToDelete: nil)
                modify.modifyRecordsResultBlock = { result in
                    if case .failure(let error) = result {
                        print("❌ Failed to save scoreboard: \(error.localizedDescription)")
                    }
                }
                self.database.add(modify)
            }
            self.database.add(activityOperation)
        }

        database.add(scoreOperation)
    }
}

// MARK: - CloudKit Helpers

extension LifeScoreboardViewModel.ScoreEntry {
    static let recordType = "ScoreEntry"

    convenience init?(record: CKRecord) {
        guard let name = record["name"] as? String,
              let score = record["score"] as? Int else { return nil }
        self.init(name: name, score: score)
    }

    func toRecord(existing: CKRecord? = nil) -> CKRecord {
        let record = existing ?? CKRecord(recordType: Self.recordType, recordID: CKRecord.ID(recordName: name))
        record["name"] = name as CKRecordValue
        record["score"] = score as CKRecordValue
        return record
    }
}

extension LifeScoreboardViewModel.ActivityRow {
    static let recordType = "ActivityRow"

    convenience init?(record: CKRecord) {
        guard let name = record["name"] as? String,
              let pending = record["pending"] as? Int,
              let projected = record["projected"] as? Double else { return nil }
        self.init(name: name, pending: pending, projected: projected)
    }

    func toRecord(existing: CKRecord? = nil) -> CKRecord {
        let record = existing ?? CKRecord(recordType: Self.recordType, recordID: CKRecord.ID(recordName: name))
        record["name"] = name as CKRecordValue
        record["pending"] = pending as CKRecordValue
        record["projected"] = projected as CKRecordValue
        return record
    }
}
