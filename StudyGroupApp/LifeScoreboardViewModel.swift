import CloudKit
import Foundation

class LifeScoreboardViewModel: ObservableObject {
    /// CloudKit container shared with WinTheDay
    private let container = CloudKitManager.container
    private let recordType = "ScoreRecord"

    /// All team members fetched from CloudKit
    @Published var teamMembers: [TeamMember] = []
    @Published var scores: [ScoreEntry] = []
    @Published var activity: [ActivityRow] = []
    @Published var onTime: Double = 17.7
    @Published var travel: Double = 31.0

    /// Key used for persisting scoreboard data locally
    private let storageKey = "LifeScoreboardStorage"
    /// Key used for persisting team members locally
    private let memberStorageKey = "LifeScoreboardMembers"
    /// Signature of the last CloudKit fetch used to detect changes
    private var lastFetchHash: Int?
    /// Signature of the last team member fetch
    private var lastMemberHash: Int?

    init() {
        teamMembers = loadLocalMembers().sorted { $0.sortIndex < $1.sortIndex }
        let stored = loadLocalScores().sorted { $0.sortIndex < $1.sortIndex }
        for item in stored {
            let entry = ScoreEntry(name: item.name, score: item.score, sortIndex: item.sortIndex)
            scores.append(entry)
            let row = ActivityRow(name: item.name, score: item.score, sortIndex: item.sortIndex, pending: item.pending, projected: item.projected)
            row.entries = [entry]
            activity.append(row)
        }
        lastFetchHash = computeHash(for: stored)
        lastMemberHash = computeMemberHash(for: teamMembers)
    }

    struct ScoreEntry: Identifiable, Hashable, Codable {
        var id = UUID()
        var name: String
        var score: Int
        var sortIndex: Int = 0
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

        init(name: String, score: Int, sortIndex: Int, pending: Int, projected: Double) {
            self.name = name
            self.entries = [ScoreEntry(name: name, score: score, sortIndex: sortIndex)]
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

    /// Calculates a simple signature for the provided stored scores to detect
    /// changes between CloudKit fetches.
    private func computeHash(for stored: [StoredScore]) -> Int {
        var hasher = Hasher()
        for item in stored {
            hasher.combine(item.name)
            hasher.combine(item.score)
            hasher.combine(item.pending)
            hasher.combine(item.projected)
        }
        return hasher.finalize()
    }

    /// Model used for local persistence
    private struct StoredScore: Codable {
        var name: String
        var score: Int
        var pending: Int
        var projected: Double
        var sortIndex: Int
    }

    private func saveLocal() {
        let stored = scores.map { score -> StoredScore in
            let row = activity.first { $0.name == score.name }
            return StoredScore(
                name: score.name,
                score: score.score,
                pending: row?.pending ?? 0,
                projected: row?.projected ?? 0,
                sortIndex: score.sortIndex
            )
        }
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadLocalScores() -> [StoredScore] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([StoredScore].self, from: data) else {
            return []
        }
        return decoded
    }

    private func saveLocalMembers() {
        let models = teamMembers.map { $0.codable }
        if let data = try? JSONEncoder().encode(models) {
            UserDefaults.standard.set(data, forKey: memberStorageKey)
        }
    }

    private func loadLocalMembers() -> [TeamMember] {
        guard let data = UserDefaults.standard.data(forKey: memberStorageKey),
              let decoded = try? JSONDecoder().decode([TeamMember.CodableModel].self, from: data) else {
            return []
        }
        return decoded.map { TeamMember(codable: $0) }
    }

    private func computeMemberHash(for members: [TeamMember]) -> Int {
        var hasher = Hasher()
        for m in members {
            hasher.combine(m.name)
            hasher.combine(m.quotesGoal)
            hasher.combine(m.salesWTDGoal)
            hasher.combine(m.salesMTDGoal)
            hasher.combine(m.emoji)
        }
        return hasher.finalize()
    }

    private func updateLocalEntries(names: [String]) {
        // Remove entries for deleted users
        scores.removeAll { entry in !names.contains(entry.name) }
        activity.removeAll { row in !names.contains(row.name) }

        let stored = loadLocalScores()

        // Add entries for new users using any stored values
        for name in names where !scores.contains(where: { $0.name == name }) {
            if let saved = stored.first(where: { $0.name == name }) {
                let entry = ScoreEntry(name: name, score: saved.score, sortIndex: saved.sortIndex)
                scores.append(entry)
                let row = ActivityRow(name: name, score: saved.score, sortIndex: saved.sortIndex, pending: saved.pending, projected: saved.projected)
                row.entries = [entry]
                activity.append(row)
            } else {
                let index = scores.count
                let entry = ScoreEntry(name: name, score: 0, sortIndex: index)
                scores.append(entry)
                let row = ActivityRow(name: name, score: 0, sortIndex: index, pending: 0, projected: 0)
                row.entries = [entry]
                activity.append(row)
            }
        }

        // Ensure ordering based on stored sortIndex
        scores.sort { $0.sortIndex < $1.sortIndex }
        activity.sort { lhs, rhs in
            guard let left = scores.firstIndex(where: { $0.name == lhs.name }),
                  let right = scores.firstIndex(where: { $0.name == rhs.name }) else { return false }
            return left < right
        }
    }

    func load(for names: [String]) {
        updateLocalEntries(names: names)
        CloudKitManager.shared.fetchScores(for: names) { [weak self] records in
            guard let self = self else { return }

            var fetched: [StoredScore] = []
            for (idx, name) in names.enumerated() {
                let values = records[name]
                let score = values?.score ?? self.entry(for: name)?.score ?? 0
                let pending = values?.pending ?? self.row(for: name)?.pending ?? 0
                let projected = values?.projected ?? self.row(for: name)?.projected ?? 0
                let sort = self.scores.first(where: { $0.name == name })?.sortIndex ?? idx
                fetched.append(StoredScore(name: name, score: score, pending: pending, projected: projected, sortIndex: sort))
            }

            DispatchQueue.main.async {
                let newHash = self.computeHash(for: fetched)

                if self.lastFetchHash != newHash {
                    let sorted = fetched.sorted { $0.score > $1.score }
                    for (index, item) in sorted.enumerated() {
                        if let scoreIndex = self.scores.firstIndex(where: { $0.name == item.name }) {
                            self.scores[scoreIndex].score = item.score
                            self.scores[scoreIndex].sortIndex = index
                        } else {
                            self.scores.append(ScoreEntry(name: item.name, score: item.score, sortIndex: index))
                        }

                        if let row = self.activity.first(where: { $0.name == item.name }) {
                            row.pending = item.pending
                            row.projected = item.projected
                        } else {
                            let row = ActivityRow(name: item.name, score: item.score, sortIndex: index, pending: item.pending, projected: item.projected)
                            row.entries = [ScoreEntry(name: item.name, score: item.score, sortIndex: index)]
                            self.activity.append(row)
                        }
                    }
                    self.scores.sort { $0.sortIndex < $1.sortIndex }
                    self.activity.sort { lhs, rhs in
                        guard let left = self.scores.firstIndex(where: { $0.name == lhs.name }),
                              let right = self.scores.firstIndex(where: { $0.name == rhs.name }) else { return false }
                        return left < right
                    }
                    self.lastFetchHash = newHash
                } else {
                    for item in fetched {
                        if let scoreIndex = self.scores.firstIndex(where: { $0.name == item.name }) {
                            self.scores[scoreIndex].score = item.score
                        }
                        if let row = self.activity.first(where: { $0.name == item.name }) {
                            row.pending = item.pending
                            row.projected = item.projected
                        }
                    }
                }

                self.saveLocal()
            }
        }
    }

    /// Reorders local entries by score and updates their stored sort index.
    private func reorderLocal() {
        scores.sort { $0.score > $1.score }
        for index in scores.indices { scores[index].sortIndex = index }
        activity.sort { lhs, rhs in
            guard let left = scores.firstIndex(where: { $0.name == lhs.name }),
                  let right = scores.firstIndex(where: { $0.name == rhs.name }) else { return false }
            return left < right
        }
        lastFetchHash = computeHash(for: scores.map { score in
            StoredScore(name: score.name,
                        score: score.score,
                        pending: activity.first { $0.name == score.name }?.pending ?? 0,
                        projected: activity.first { $0.name == score.name }?.projected ?? 0,
                        sortIndex: score.sortIndex)
        })
    }
    func save(_ entry: ScoreEntry, pending: Int, projected: Double) {
        guard let index = scores.firstIndex(where: { $0.name == entry.name }) else { return }
        scores[index].score = entry.score

        if let rowIndex = activity.firstIndex(where: { $0.name == entry.name }) {
            activity[rowIndex].pending = pending
            activity[rowIndex].projected = projected
        }

        reorderLocal()
        saveLocal()

        let container = CloudKitManager.container
        let recordID = CKRecord.ID(recordName: "score-\(entry.name)")

        container.publicCloudDatabase.fetch(withRecordID: recordID) { existingRecord, _ in
            if let record = existingRecord {
                record["actual"] = entry.score as CKRecordValue
                record["pending"] = pending as CKRecordValue
                record["projected"] = projected as CKRecordValue

                container.publicCloudDatabase.save(record) { savedRecord, error in
                    if let error = error {
                        print("❌ Error saving updated score record: \(error)")
                    } else {
                        print("✅ Successfully updated score record: \(record.recordID.recordName)")
                    }
                }
            } else {
                print("❌ Failed to find existing record for score: \(entry.name)")
            }
        }
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

    /// Loads only `TeamMember` records containing Life Scoreboard fields.
    private func fetchScoreboardMembers(completion: @escaping ([TeamMember]) -> Void) {
        let predicate = NSPredicate(format: "pending >= 0 OR projected >= 0")
        let query = CKQuery(recordType: "TeamMember", predicate: predicate)
        let operation = CKQueryOperation(query: query)

        var results: [TeamMember] = []

        operation.recordFetchedBlock = { record in
            let name = record["name"] as? String ?? "Unknown"
            let pending = record["pending"] as? Int ?? 0
            let projected = record["projected"] as? Double ?? 0
            let actual = record["actual"] as? Int ?? 0

            let member = TeamMember(name: name)
            member.pending = pending
            member.projected = projected
            member.actual = actual
            results.append(member)
        }

        operation.queryCompletionBlock = { _, _ in
            DispatchQueue.main.async {
                completion(results)
            }
        }

        container.publicCloudDatabase.add(operation)
    }

    /// Ensures all `TeamMember` records contain Life Scoreboard fields.
    /// Missing values are initialized to `0` without overwriting existing data.
    func syncScoreboardFields() {
        // Use the same container as WinTheDay
        let container = CloudKitManager.container
        let database = container.publicCloudDatabase
        let query = CKQuery(recordType: "TeamMember", predicate: NSPredicate(value: true))

        database.fetch(withQuery: query,
                        inZoneWith: nil,
                        desiredKeys: nil,
                        resultsLimit: CKQueryOperation.maximumResults) { result in
            switch result {
            case .success(let (matchResults, _)):
                let records = matchResults.compactMap { _, recordResult in
                    try? recordResult.get()
                }
                for record in records {
                    var needsUpdate = false

                    if record.object(forKey: "pending") == nil {
                        record["pending"] = 0 as CKRecordValue
                        needsUpdate = true
                    }

                    if record.object(forKey: "projected") == nil {
                        record["projected"] = 0 as CKRecordValue
                        needsUpdate = true
                    }

                    if record.object(forKey: "actual") == nil {
                        record["actual"] = 0 as CKRecordValue
                        needsUpdate = true
                    }

                    if needsUpdate {
                        database.save(record) { _, err in
                            if let err = err {
                                print("⚠️ Failed to seed Life Scoreboard fields for \(record.recordID.recordName): \(err)")
                            } else {
                                let name = record["name"] as? String ?? "unknown"
                                print("✅ Seeded missing Life Scoreboard fields for \(name)")
                            }
                        }
                    }
                }
            case .failure(let error):
                print("⚠️ CloudKit fetch error: \(error)")
            }
        }
    }

    // MARK: - Team Member Sync

    /// Fetches all `TeamMember` records from CloudKit and initializes
    /// the local scoreboard state. The resulting order is based on the
    /// members' saved scores so rows remain stable between view loads.
    func fetchTeamMembersFromCloud() {
        // Ensure Life Scoreboard fields exist before loading data
        syncScoreboardFields()

        fetchScoreboardMembers { [weak self] fetched in
            guard let self = self else { return }
            let newHash = self.computeMemberHash(for: fetched)

            DispatchQueue.main.async {
                // Always update the local member list so removed names disappear
                self.teamMembers = fetched
            }

            if self.lastMemberHash != newHash {
                let entries = self.buildScoreEntries(from: fetched)
                let rows = self.buildActivityRows(from: entries)

                DispatchQueue.main.async {
                    self.scores = entries
                    self.activity = rows
                    self.lastMemberHash = newHash
                    self.saveLocalMembers()
                    self.load(for: fetched.map { $0.name })
                }
            } else {
                DispatchQueue.main.async {
                    self.load(for: fetched.map { $0.name })
                }
            }
        }
    }

    /// Cleans up invalid TeamMember records and ensures each member is stored
    /// under their name-based record ID. This guarantees consistent sync across
    /// devices and removes duplicates.
    func syncTeamMembersToCloudKit() {
        // Use the same container as WinTheDay
        let container = CloudKitManager.container
        let database = container.publicCloudDatabase

        // Step 1: Fetch existing records
        let query = CKQuery(recordType: "TeamMember", predicate: NSPredicate(value: true))
        database.fetch(withQuery: query,
                       inZoneWith: nil,
                       desiredKeys: nil,
                       resultsLimit: CKQueryOperation.maximumResults) { result in
            switch result {
            case .success(let (matchResults, _)):
                let records = matchResults.compactMap { _, recordResult in
                    try? recordResult.get()
                }
                var recordsToDelete: [CKRecord.ID] = []
                var existingNames: Set<String> = []

                for record in records {
                    if let name = record["name"] as? String, !name.trimmingCharacters(in: .whitespaces).isEmpty {
                        existingNames.insert(name)
                    } else {
                        recordsToDelete.append(record.recordID)
                    }
                }

                // Step 2: Delete unnamed records
                let deleteOp = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: recordsToDelete)
                deleteOp.savePolicy = .allKeys
                deleteOp.modifyRecordsCompletionBlock = { _, deleted, error in
                    if let error = error {
                        print("❌ Failed to delete unnamed records: \(error)")
                    } else {
                        print("🧹 Deleted \(deleted?.count ?? 0) unnamed TeamMember records")
                    }
                }

                // Step 3: Save or update records for each known user
                var recordsToSave: [CKRecord] = []

                for member in self.teamMembers {
                    guard !member.name.trimmingCharacters(in: .whitespaces).isEmpty else { continue }

                    let recordID = CKRecord.ID(recordName: "member-\(member.name)")
                    let record = CKRecord(recordType: "TeamMember", recordID: recordID)
                    record["name"] = member.name as CKRecordValue
                    record["emoji"] = member.emoji as CKRecordValue
                    record["sortIndex"] = member.sortIndex as CKRecordValue
                    recordsToSave.append(record)
                }

                let saveOp = CKModifyRecordsOperation(recordsToSave: recordsToSave, recordIDsToDelete: nil)
                saveOp.savePolicy = .allKeys
                saveOp.modifyRecordsCompletionBlock = { saved, _, error in
                    if let error = error {
                        print("❌ Failed to save TeamMember records: \(error)")
                    } else {
                        print("✅ Synced \(saved?.count ?? 0) TeamMember records to CloudKit")
                        DispatchQueue.main.async {
                            self.fetchTeamMembersFromCloud()
                        }
                    }
                }

                // Run operations
                OperationQueue.main.addOperations([deleteOp, saveOp], waitUntilFinished: false)
            case .failure(let error):
                print("❌ Failed to fetch TeamMember records: \(error)")
            }
        }
    }

    /// Creates score entries from the provided team members using any
    /// locally stored values and sorts them by score descending.
    private func buildScoreEntries(from members: [TeamMember]) -> [ScoreEntry] {
        let stored = loadLocalScores()
        var entries: [ScoreEntry] = []

        for member in members {
            if let saved = stored.first(where: { $0.name == member.name }) {
                entries.append(ScoreEntry(name: member.name,
                                         score: saved.score,
                                         sortIndex: saved.sortIndex))
            } else if let existing = scores.first(where: { $0.name == member.name }) {
                entries.append(existing)
            } else {
                entries.append(ScoreEntry(name: member.name,
                                         score: 0,
                                         sortIndex: entries.count))
            }
        }

        var sorted = entries.sorted { $0.score > $1.score }
        for index in sorted.indices { sorted[index].sortIndex = index }
        return sorted
    }

    /// Builds activity rows aligned with the provided score entries.
    private func buildActivityRows(from entries: [ScoreEntry]) -> [ActivityRow] {
        let stored = loadLocalScores()
        return entries.map { entry in
            let saved = stored.first(where: { $0.name == entry.name })
            let row = ActivityRow(name: entry.name,
                                  score: entry.score,
                                  sortIndex: entry.sortIndex,
                                  pending: saved?.pending ?? 0,
                                  projected: saved?.projected ?? 0)
            row.entries = [entry]
            return row
        }
    }
}

// MARK: - On Time Goals

extension LifeScoreboardViewModel {

    /// Yearly policy goals
    var travelGoal: Int { 70 }
    var honorGoal: Int { 40 }

    /// The number of days in this year (accounts for leap years)
    private var daysInYear: Int {
        let year = Calendar.current.component(.year, from: Date())
        let components = DateComponents(calendar: .current, year: year)
        return Calendar.current.range(of: .day, in: .year, for: components.date!)?.count ?? 365
    }

    /// The current day of the year (1–365/366)
    private var currentDayOfYear: Int {
        Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
    }

    /// 🎯 Daily-updating On Time Count for Travel
    var onTimeTravelTarget: Int {
        Int(round((Double(travelGoal) / Double(daysInYear)) * Double(currentDayOfYear)))
    }

    /// 🎯 Daily-updating On Time Count for Honor
    var onTimeHonorTarget: Int {
        Int(round((Double(honorGoal) / Double(daysInYear)) * Double(currentDayOfYear)))
    }
}

