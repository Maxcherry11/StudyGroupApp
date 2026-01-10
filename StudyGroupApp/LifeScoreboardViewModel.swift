import CloudKit
import Foundation

@MainActor
class LifeScoreboardViewModel: ObservableObject {
    /// CloudKit container shared with WinTheDay
    private let container = CloudKitManager.container

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
        NotificationCenter.default.addObserver(
            forName: .cloudKitTeamMemberDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.applyTeamMemberSnapshot(CloudKitManager.shared.teamMembers)
            }
        }
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

    private func applyTeamMemberSnapshot(_ members: [TeamMember]) {
        let newHash = computeMemberHash(for: members)
        teamMembers = members

        if lastMemberHash != newHash {
            let entries = buildScoreEntries(from: members)
            let rows = buildActivityRows(from: entries)
            scores = entries
            activity = rows
            lastMemberHash = newHash
            saveLocalMembers()
            load(for: members.map { $0.name })
        } else {
            load(for: members.map { $0.name })
        }
    }

    func load(for names: [String]) {
        updateLocalEntries(names: names)
        CloudKitManager.shared.fetchScores(for: names) { [weak self] records in
            guard let self = self else { return }
            guard !records.isEmpty else { return }

            var fetched: [StoredScore] = []
            for (idx, name) in names.enumerated() {
                if let values = records[name] {
                    let sort = self.scores.first(where: { $0.name == name })?.sortIndex ?? idx
                    fetched.append(StoredScore(name: name,
                                              score: values.score,
                                              pending: values.pending,
                                              projected: values.projected,
                                              sortIndex: sort))
                } else if let entry = self.entry(for: name),
                          let row = self.row(for: name) {
                    fetched.append(StoredScore(name: name,
                                              score: entry.score,
                                              pending: row.pending,
                                              projected: row.projected,
                                              sortIndex: entry.sortIndex))
                } else {
                    let sort = self.scores.first(where: { $0.name == name })?.sortIndex ?? idx
                    fetched.append(StoredScore(name: name,
                                              score: 0,
                                              pending: 0,
                                              projected: 0,
                                              sortIndex: sort))
                }
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
        let recordID = CKRecord.ID(recordName: "member-\(entry.name)")

        container.publicCloudDatabase.fetch(withRecordID: recordID) { existingRecord, _ in
            if let record = existingRecord {
                record["actual"] = entry.score as CKRecordValue
                record["pending"] = pending as CKRecordValue
                record["projected"] = projected as CKRecordValue

                container.publicCloudDatabase.save(record) { _, error in
                    if let error = error {
                        print("❌ Error saving updated score record: \(error)")
                    } else {
                        print("✅ Successfully updated score record: \(record.recordID.recordName)")
                    }
                }
            } else {
                let newRecord = CKRecord(recordType: "TeamMember", recordID: recordID)
                newRecord["name"] = entry.name as CKRecordValue
                newRecord["actual"] = entry.score as CKRecordValue
                newRecord["pending"] = pending as CKRecordValue
                newRecord["projected"] = projected as CKRecordValue
                newRecord["quotesGoal"] = 0 as CKRecordValue
                newRecord["salesWTDGoal"] = 0 as CKRecordValue
                newRecord["salesMTDGoal"] = 0 as CKRecordValue
                newRecord["emoji"] = "🌱" as CKRecordValue

                container.publicCloudDatabase.save(newRecord) { _, error in
                    if let error = error {
                        print("❌ Failed to create new TeamMember: \(error)")
                    } else {
                        print("✅ Created new TeamMember record for \(entry.name)")
                    }
                }
            }
        }
    }

    /// Ensures all `TeamMember` records contain Life Scoreboard fields.
    /// Missing values are initialized to `0` without overwriting existing data.
    func syncScoreboardFields() {
        let predicate = NSPredicate(value: true)
        let query = CKQuery(recordType: "TeamMember", predicate: predicate)

        CloudKitManager.container.publicCloudDatabase.fetch(
            withQuery: query,
            inZoneWith: nil,
            desiredKeys: nil,
            resultsLimit: CKQueryOperation.maximumResults
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let (matchResults, _)):
                    print("✅ syncScoreboardFields() matched \(matchResults.count) records")

                    for (recordID, recordResult) in matchResults {
                        switch recordResult {
                        case .success(let record):
                            print("📥 Record loaded: \(record)")

                            var needsSave = false
                            if record["actual"] == nil {
                                record["actual"] = 0 as CKRecordValue
                                needsSave = true
                            }
                            if record["pending"] == nil {
                                record["pending"] = 0 as CKRecordValue
                                needsSave = true
                            }
                            if record["projected"] == nil {
                                record["projected"] = 0.0 as CKRecordValue
                                needsSave = true
                            }

                            if needsSave {
                                CloudKitManager.container.publicCloudDatabase.save(record) { _, error in
                                    if let error = error {
                                        print("❌ Failed to update \(recordID.recordName): \(error.localizedDescription)")
                                    } else {
                                        print("✅ Updated scoreboard fields for \(recordID.recordName)")
                                    }
                                }
                            }
                        case .failure(let error):
                            print("⚠️ Record fetch failed for \(recordID): \(error.localizedDescription)")
                        }
                    }

                case .failure(let error):
                    print("❌ syncScoreboardFields() failed with error: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Team Member Sync

    /// Fetches all `TeamMember` records from CloudKit and initializes
    /// the local scoreboard state. The resulting order is based on the
    /// members' saved scores so rows remain stable between view loads.
    func fetchTeamMembersFromCloud() {
        DispatchQueue.main.async {
            CloudKitManager.shared.migrateTeamMemberFieldsIfNeeded()
            // Ensure all records contain scoreboard fields before fetching
            // members so older entries gain the new fields.
            self.syncScoreboardFields()

            CloudKitManager.shared.fetchAllTeamMembers { [weak self] fetched in
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
    }

    /// Cleans up invalid TeamMember records and ensures each member is stored
    /// under their name-based record ID. This guarantees consistent sync across
    /// devices and removes duplicates.
    func syncTeamMembersToCloudKit() {
        let container = CloudKitManager.container
        let database = container.publicCloudDatabase

        var fetched: [CKRecord] = []

        let predicate = NSPredicate(value: true)
        let query = CKQuery(recordType: "TeamMember", predicate: predicate)

        let operation = CKQueryOperation(query: query)
        operation.recordMatchedBlock = { recordID, result in
            switch result {
            case .success(let record):
                fetched.append(record)
            case .failure(let error):
                print("Error for record \(recordID): \(error.localizedDescription)")
            }
        }

        operation.queryResultBlock = { [weak self] cursorResult in
            DispatchQueue.main.async {
                switch cursorResult {
                case .success:
                    self?.reconcileTeamMembers(records: fetched, in: database)
                case .failure(let error):
                    print("❌ syncTeamMembersToCloudKit() failed with error: \(error.localizedDescription)")
                }
            }
        }

        database.add(operation)
    }

    private func reconcileTeamMembers(records: [CKRecord], in database: CKDatabase) {
        var recordsToSave: [CKRecord] = []
        var recordsToDelete: [CKRecord.ID] = []

        var seenNames: Set<String> = []

        for record in records {
            guard let name = record["name"] as? String, !name.trimmingCharacters(in: .whitespaces).isEmpty else {
                recordsToDelete.append(record.recordID)
                continue
            }

            let canonicalID = CKRecord.ID(recordName: "member-\(name)")

            if seenNames.contains(name) {
                recordsToDelete.append(record.recordID)
                continue
            }
            seenNames.insert(name)

            if record.recordID != canonicalID {
                if let member = TeamMember(record: record) {
                    let newRecord = member.toRecord()
                    recordsToSave.append(newRecord)
                }
                recordsToDelete.append(record.recordID)
            }
        }

        guard !recordsToSave.isEmpty || !recordsToDelete.isEmpty else { return }

        let modify = CKModifyRecordsOperation(recordsToSave: recordsToSave, recordIDsToDelete: recordsToDelete)
        modify.modifyRecordsResultBlock = { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    print("✅ syncTeamMembersToCloudKit() reconciled \(recordsToSave.count) records, deleted \(recordsToDelete.count) duplicates")
                case .failure(let error):
                    print("❌ syncTeamMembersToCloudKit() modify failed: \(error.localizedDescription)")
                }
            }
        }
        database.add(modify)
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
        if let date = components.date,
           let range = Calendar.current.range(of: .day, in: .year, for: date) {
            return range.count
        }
        return 365
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
