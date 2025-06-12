import CloudKit
import Combine
import Foundation

class LifeScoreboardViewModel: ObservableObject {
    /// Use the shared Outcast container for scoreboard records.
    private let container = CKContainer(identifier: "iCloud.com.dj.Outcast")
    private let recordType = "ScoreRecord"

    @Published var scores: [ScoreEntry] = []
    @Published var activity: [ActivityRow] = []
    /// Stable ordering of members for display. Mirrors the logic used in
    /// ``WinTheDayViewModel`` so rows don't reshuffle on every appearance.
    @Published var displayedMembers: [TeamMember] = []
    /// Activity rows matching ``displayedMembers`` ordering.
    @Published var displayedActivity: [ActivityRow] = []
    @Published var onTime: Double = 17.7
    @Published var travel: Double = 31.0
    @Published var teamMembers: [TeamMember] = []

    private var cancellables = Set<AnyCancellable>()
    /// Signature of the last CloudKit fetch. Used to avoid UI resets when
    /// returning to the scoreboard if nothing has changed.
    private var lastFetchHash: Int?
    /// Tracks whether a full load has already occurred. Prevents unnecessary
    /// re-fetching when the view appears multiple times.
    private var hasLoadedFromCloud = false
    /// Whether the initial display order has been loaded from disk.
    private var hasLoadedDisplayOrder = false
    /// Key used for persisting the member display order.
    private let orderKey = "ScoreboardDisplayOrder"

    init() {
        CloudKitManager.shared.$teamMembers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] members in
                guard let self = self else { return }
                let newNames = members.map { $0.name }
                let currentNames = self.teamMembers.map { $0.name }

                // Update local names and trigger a reload only when names change
                if Set(newNames) != Set(currentNames) {
                    self.teamMembers = members
                    self.updateLocalEntries(names: newNames)
                    if self.hasLoadedFromCloud {
                        self.loadFromCloud()
                    }
                } else {
                    self.teamMembers = members
                }
            }
            .store(in: &cancellables)
    }

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

    // MARK: - Order Persistence

    private func saveOrder() {
        let names = displayedMembers.map { $0.name }
        UserDefaults.standard.set(names, forKey: orderKey)
    }

    private func loadSavedOrder() -> [String] {
        UserDefaults.standard.stringArray(forKey: orderKey) ?? []
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

        // Keep displayed arrays in sync with membership changes
        var currentNames = displayedMembers.map { $0.name }
        currentNames.removeAll { !names.contains($0) }
        for name in names where !currentNames.contains(name) {
            currentNames.append(name)
        }
        displayedMembers = currentNames.compactMap { n in teamMembers.first { $0.name == n } }
        displayedActivity = currentNames.compactMap { n in activity.first { $0.name == n } }
        saveOrder()
    }

    /// Fetches all team members from CloudKit and updates ``teamMembers``.
    func fetchTeamMembersFromCloud() {
        CloudKitManager.shared.fetchAllTeamMembers { [weak self] fetched in
            DispatchQueue.main.async {
                self?.teamMembers = fetched
            }
        }
    }

    /// Loads team members and their scores directly from CloudKit.
    /// This bypasses any local defaults so the view always reflects the
    /// latest saved data.
    func loadFromCloud() {
        CloudKitManager.shared.fetchAllTeamMembers { [weak self] members in
            guard let self = self else { return }
            let names = members.map { $0.name }
            CloudKitManager.shared.fetchScores(for: names) { records in
                DispatchQueue.main.async {
                    let newHash = self.computeHash(members: members, records: records)

                    if self.lastFetchHash != newHash {
                        self.teamMembers = members
                        self.scores = names.map { name in
                            let value = records[name]?.score ?? 0
                            return ScoreEntry(name: name, score: value)
                        }
                        self.activity = names.map { name in
                            let values = records[name]
                            return ActivityRow(
                                name: name,
                                score: values?.score ?? 0,
                                pending: values?.pending ?? 0,
                                projected: values?.projected ?? 0.0
                            )
                        }
                        self.updateDisplayOrder(with: names)
                        self.lastFetchHash = newHash
                    } else {
                        // Even if nothing changed, keep team member list in sync
                        self.teamMembers = members
                    }
                }
            }
        }
    }

    /// Performs the initial CloudKit load if it hasn't been done yet.
    /// Called from the view's `onAppear` so existing data isn't cleared
    /// when returning to the scoreboard.
    func loadIfNeeded() {
        guard !hasLoadedFromCloud else { return }
        hasLoadedFromCloud = true
        loadFromCloud()
    }

    /// Manual refresh entry point used by pull-to-refresh in the view.
    func refreshFromCloud() {
        loadFromCloud()
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

    /// Updates ``displayedMembers`` and ``displayedActivity`` using the provided
    /// ordered list of names. This is called after a CloudKit refresh or when
    /// member names change.
    private func updateDisplayOrder(with names: [String]) {
        if !hasLoadedDisplayOrder {
            let saved = loadSavedOrder()
            let starting = saved.isEmpty ? names.sorted { score(for: $0) > score(for: $1) } : saved
            displayedMembers = starting.compactMap { name in
                teamMembers.first { $0.name == name }
            }
            displayedActivity = starting.compactMap { name in
                activity.first { $0.name == name }
            }
            hasLoadedDisplayOrder = true
        } else {
            var order = displayedMembers.map { $0.name }
            order.removeAll { !names.contains($0) }
            for name in names where !order.contains(name) {
                order.append(name)
            }
            displayedMembers = order.compactMap { n in teamMembers.first { $0.name == n } }
            displayedActivity = order.compactMap { n in activity.first { $0.name == n } }
        }
        saveOrder()
    }

    /// Computes a simple signature for the provided members and score records.
    /// This mirrors the change-detection logic used by ``WinTheDayViewModel``.
    private func computeHash(members: [TeamMember],
                             records: [String: (score: Int, pending: Int, projected: Double)]) -> Int {
        var hasher = Hasher()
        let sorted = members.sorted { $0.name < $1.name }
        for member in sorted {
            hasher.combine(member.name)
            let values = records[member.name]
            hasher.combine(values?.score ?? 0)
            hasher.combine(values?.pending ?? 0)
            hasher.combine(Int((values?.projected ?? 0).rounded()))
        }
        return hasher.finalize()
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

