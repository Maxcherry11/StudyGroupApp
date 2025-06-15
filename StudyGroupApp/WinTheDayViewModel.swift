import Foundation
import CloudKit
import SwiftUI

class WinTheDayViewModel: ObservableObject {
    @Published var teamData: [TeamMember] = []

    /// Prevents repeatedly overwriting ``teamData`` when the view reappears.
    private var hasLoadedCloudKit = false

    init() {
        let stored = loadLocalMembers().sorted { $0.sortIndex < $1.sortIndex }
        self.teamMembers = stored
        self.displayedMembers = stored
        self.teamData = [] // empty until CloudKit returns
        let names = Self.loadLocalGoalNames()
        self.goalNames = names
        self.lastGoalHash = Self.computeGoalHash(for: names)
        self.lastFetchHash = computeHash(for: stored)
    }
    @Published var teamMembers: [TeamMember] = []
    @Published var displayedMembers: [TeamMember] = []
    @Published var cards: [Card] = []
    @Published var displayedCards: [Card] = []
    @Published var selectedUserName: String = ""
    @Published var goalNames: GoalNames = GoalNames()
    private let storageKey = "WTDMemberStorage"
    private static let goalNameKey = "WTDGoalNames"
    private var hasLoadedDisplayOrder = false
    /// Signature of the last CloudKit fetch used to detect changes
    private var lastFetchHash: Int?
    private var lastGoalHash: Int?
    private let weeklyResetKey = "WTDWeeklyReset"
    private let monthlyResetKey = "WTDMonthlyReset"
    private var hasFetchedMembers = false

    /// Calculates a simple hash representing the current production values for
    /// the provided team members. This allows quick comparison between
    /// subsequent CloudKit fetches so the view only reorders when data changes.
    private func computeHash(for members: [TeamMember]) -> Int {
        var hasher = Hasher()
        for m in members {
            hasher.combine(m.name)
            hasher.combine(m.quotesToday)
            hasher.combine(m.salesWTD)
            hasher.combine(m.salesMTD)
        }
        return hasher.finalize()
    }

    /// Sorts ``displayedCards`` a single time based on production metrics.
    /// This mirrors the stable ordering used by Life Scoreboard.
    func loadInitialDisplayOrder() {
        guard !hasLoadedDisplayOrder else { return }
        displayedMembers = teamMembers.sorted {
            ($0.quotesToday + $0.salesWTD + $0.salesMTD) >
            ($1.quotesToday + $1.salesWTD + $1.salesMTD)
        }
        hasLoadedDisplayOrder = true
    }

    /// Initializes ``displayedMembers`` only once using the current
    /// ``teamMembers`` order so that card order remains stable when returning
    /// from the splash screen.
    func initializeDisplayedCardsIfNeeded() {
        if displayedMembers.isEmpty {
            displayedMembers = teamMembers.sorted { $0.sortIndex < $1.sortIndex }
        }
    }

    /// Reorders ``displayedCards`` after the user saves edits.
    func reorderAfterSave() {
        reorderCards()
    }

    // MARK: - Card Sync Helpers

    func fetchCardsFromCloud() {
        CloudKitManager.fetchCards { fetched in
            DispatchQueue.main.async {
                self.cards = fetched
                self.displayedCards = fetched.sorted { $0.production > $1.production }
            }
        }
    }

    /// Convenience wrapper mirroring LifeScoreboardViewModel.fetchTeamMembersFromCloud
    /// for fetching the latest production values without altering local order.
    func fetchScores() {
        fetchMembersFromCloud { [weak self] in
            guard let self = self else { return }
            if !self.hasLoadedCloudKit {
                self.teamData = self.teamMembers.sorted { $0.sortIndex < $1.sortIndex }
                self.hasLoadedCloudKit = true
            }
        }
    }

    /// Fetches all ``TeamMember`` records from CloudKit and updates ``teamMembers``.
    /// This mirrors the behavior used on the splash screen so both views stay in sync.
    func fetchMembersFromCloud(completion: (() -> Void)? = nil) {
        CloudKitManager.shared.fetchAllTeamMembers { [weak self] fetched in
            DispatchQueue.main.async {
                guard let self = self else { return }

                let newHash = self.computeHash(for: fetched)

                self.updateLocalEntries(names: fetched.map { $0.name })

                for member in fetched {
                    if let index = self.teamMembers.firstIndex(where: { $0.name == member.name }) {
                        self.teamMembers[index].quotesToday = member.quotesToday
                        self.teamMembers[index].salesWTD = member.salesWTD
                        self.teamMembers[index].salesMTD = member.salesMTD
                        self.teamMembers[index].quotesGoal = member.quotesGoal
                        self.teamMembers[index].salesWTDGoal = member.salesWTDGoal
                        self.teamMembers[index].salesMTDGoal = member.salesMTDGoal
                        self.teamMembers[index].emoji = member.emoji
                    }
                }

                if self.hasFetchedMembers {
                    if self.lastFetchHash != newHash {
                        self.reorderCards()
                        self.lastFetchHash = newHash
                    }
                    if !self.hasLoadedCloudKit {
                        self.teamData = self.teamMembers.sorted { $0.sortIndex < $1.sortIndex }
                        self.hasLoadedCloudKit = true
                    }
                } else {
                    self.teamMembers.sort { $0.sortIndex < $1.sortIndex }
                    self.displayedMembers = self.teamMembers
                    self.lastFetchHash = newHash
                    self.initializeResetDatesIfNeeded()
                    self.hasFetchedMembers = true
                    if !self.hasLoadedCloudKit {
                        self.teamData = self.teamMembers.sorted { $0.sortIndex < $1.sortIndex }
                        self.hasLoadedCloudKit = true
                    }
                }
                self.performResetsIfNeeded()
                self.saveLocal()
                completion?()
            }
        }
    }

    func saveEdits(for card: Card) {
        CloudKitManager.saveCard(card)
        withAnimation {
            displayedCards = cards.sorted { $0.production > $1.production }
        }
    }

    /// Saves edits for a given ``TeamMember`` and updates ordering.
    func saveEdits(for member: TeamMember) {
        saveMember(member) { _ in }
        withAnimation {
            reorderAfterSave()
        }
    }

    private func saveLocal() {
        let codable = teamMembers.map { $0.codable }
        if let data = try? JSONEncoder().encode(codable) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadLocalMembers() -> [TeamMember] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([TeamMember.CodableModel].self, from: data) else {
            return []
        }
        return decoded.map { TeamMember(codable: $0) }
    }

    // MARK: - Goal Name Persistence

    private func saveLocalGoalNames() {
        if let data = try? JSONEncoder().encode(goalNames) {
            UserDefaults.standard.set(data, forKey: Self.goalNameKey)
        }
    }

    private static func loadLocalGoalNames() -> GoalNames {
        guard let data = UserDefaults.standard.data(forKey: Self.goalNameKey),
              let decoded = try? JSONDecoder().decode(GoalNames.self, from: data) else {
            return GoalNames()
        }
        return decoded
    }

    private static func computeGoalHash(for names: GoalNames) -> Int {
        var hasher = Hasher()
        hasher.combine(names.quotes)
        hasher.combine(names.salesWTD)
        hasher.combine(names.salesMTD)
        return hasher.finalize()
    }

    private func updateLocalEntries(names: [String]) {
        teamMembers.removeAll { member in !names.contains(member.name) }

        let stored = loadLocalMembers()
        var maxIndex = teamMembers.map { $0.sortIndex }.max() ?? -1

        for name in names where !teamMembers.contains(where: { $0.name == name }) {
            if let saved = stored.first(where: { $0.name == name }) {
                teamMembers.append(saved)
                maxIndex = max(maxIndex, saved.sortIndex)
            } else {
                var newMember = TeamMember(name: name)
                maxIndex += 1
                newMember.sortIndex = maxIndex
                teamMembers.append(newMember)
            }
        }

        teamMembers.sort { $0.sortIndex < $1.sortIndex }
    }

    func load(names: [String], completion: (() -> Void)? = nil) {
        updateLocalEntries(names: names)
        CloudKitManager.shared.fetchTeam { [weak self] members in
            guard let self = self else { return }
            if members.isEmpty {
                DispatchQueue.main.async {
                    self.saveLocal()
                    completion?()
                }
                return
            }

            for name in names {
                if let m = members.first(where: { $0.name == name }) {
                    if let idx = self.teamMembers.firstIndex(where: { $0.name == name }) {
                        self.teamMembers[idx].quotesToday = m.quotesToday
                        self.teamMembers[idx].salesWTD = m.salesWTD
                        self.teamMembers[idx].salesMTD = m.salesMTD
                        self.teamMembers[idx].quotesGoal = m.quotesGoal
                        self.teamMembers[idx].salesWTDGoal = m.salesWTDGoal
                        self.teamMembers[idx].salesMTDGoal = m.salesMTDGoal
                        self.teamMembers[idx].emoji = m.emoji
                    }
                }
            }
            DispatchQueue.main.async {
                self.saveLocal()
                completion?()
            }
        }
    }

    func saveMember(_ member: TeamMember, completion: ((CKRecord.ID?) -> Void)? = nil) {
        CloudKitManager.shared.save(member) { id in
            completion?(id)
        }
        saveLocal()
    }

    var filteredMembers: [TeamMember] {
        teamMembers.filter {
            guard let name = $0.name.lowercased().replacingOccurrences(of: ".", with: "") as String? else {
                return false
            }
            return name == selectedUserName.lowercased().replacingOccurrences(of: ".", with: "")
        }
    }

    /// Reorders team members by current production (quotes + sales) and updates
    /// their persisted `sortIndex`. This mirrors the stable ordering logic used
    /// in LifeScoreboardViewModel.
    func reorderCards() {
        teamMembers.sort {
            ($0.quotesToday + $0.salesWTD + $0.salesMTD) >
            ($1.quotesToday + $1.salesWTD + $1.salesMTD)
        }
        for index in teamMembers.indices {
            teamMembers[index].sortIndex = index
        }
        displayedMembers = teamMembers
        lastFetchHash = computeHash(for: teamMembers)
    }

    func loadCardOrderFromCloud(for user: String) {
        CloudKitManager.shared.fetchCardOrder(for: user) { [weak self] savedOrder in
            guard let self = self else { return }
            if let savedOrder = savedOrder {
                let ordered = savedOrder.compactMap { idString in
                    self.teamMembers.first { $0.id.uuidString == idString }
                }
                self.displayedMembers = ordered
            } else {
                let sorted = self.teamMembers.sorted {
                    ($0.quotesToday + $0.salesWTD + $0.salesMTD) >
                    ($1.quotesToday + $1.salesWTD + $1.salesMTD)
                }
                self.displayedMembers = sorted
            }
        }
    }

    func saveCardOrderToCloud(for user: String) {
        let order = displayedMembers.map { $0.id.uuidString }
        CloudKitManager.shared.saveCardOrder(for: user, order: order)
    }

    // MARK: - Goal Name Sync

    func fetchGoalNamesFromCloud() {
        CloudKitManager.shared.fetchGoalNames { [weak self] fetched in
            guard let self = self, let fetched = fetched else { return }
            let newHash = Self.computeGoalHash(for: fetched)
            if self.lastGoalHash != newHash {
                self.goalNames = fetched
                self.lastGoalHash = newHash
                self.saveLocalGoalNames()
            }
        }
    }

    func saveGoalNames(quotes: String, salesWTD: String, salesMTD: String) {
        goalNames.quotes = quotes
        goalNames.salesWTD = salesWTD
        goalNames.salesMTD = salesMTD
        lastGoalHash = Self.computeGoalHash(for: goalNames)
        saveLocalGoalNames()
        CloudKitManager.shared.saveGoalNames(goalNames)
    }

    // MARK: - Periodic Reset Logic

    /// Resets weekly and monthly values when a new period starts.
    func performResetsIfNeeded() {
        let calendar = Calendar.current
        let now = Date()

        let lastWeekly = UserDefaults.standard.object(forKey: weeklyResetKey) as? Date ?? .distantPast
        if let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)),
           startOfWeek > lastWeekly {
            resetWeeklyValues()
            UserDefaults.standard.set(startOfWeek, forKey: weeklyResetKey)
        }

        let lastMonthly = UserDefaults.standard.object(forKey: monthlyResetKey) as? Date ?? .distantPast
        if let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
           startOfMonth > lastMonthly {
            resetMonthlyValues()
            UserDefaults.standard.set(startOfMonth, forKey: monthlyResetKey)
        }
    }

    private func initializeResetDatesIfNeeded() {
        let calendar = Calendar.current
        let now = Date()
        if UserDefaults.standard.object(forKey: weeklyResetKey) == nil,
           let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) {
            UserDefaults.standard.set(startOfWeek, forKey: weeklyResetKey)
        }
        if UserDefaults.standard.object(forKey: monthlyResetKey) == nil,
           let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) {
            UserDefaults.standard.set(startOfMonth, forKey: monthlyResetKey)
        }
    }

    private func resetWeeklyValues() {
        for index in teamMembers.indices {
            teamMembers[index].quotesToday = 0
            teamMembers[index].salesWTD = 0
            saveMember(teamMembers[index]) { _ in }
        }
        teamMembers = teamMembers.map { $0 }
    }

    private func resetMonthlyValues() {
        for index in teamMembers.indices {
            teamMembers[index].salesMTD = 0
            saveMember(teamMembers[index]) { _ in }
        }
        teamMembers = teamMembers.map { $0 }
    }


    func uploadTestMembersToCloudKit() {
        print("📤 Uploading all team members to CloudKit...")

        let membersToUpload = TeamMember.testMembers

        let records = membersToUpload.compactMap { $0.toRecord() }

        let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
        operation.modifyRecordsResultBlock = { result in
            DispatchQueue.main.async {
                switch result {
                case .failure(let error):
                    print("❌ Upload failed: \(error.localizedDescription)")
                case .success:
                    print("✅ Uploaded all test members to CloudKit.")
                }
            }
        }

        CKContainer(identifier: "iCloud.com.dj.Outcast").publicCloudDatabase.add(operation)
    }
} // End of class WinTheDayViewModel

extension TeamMember {
    static let testMembers: [TeamMember] = [
        TeamMember(
            name: "D.J.",
            quotesToday: 0,
            salesWTD: 0,
            salesMTD: 0,
            quotesGoal: 10,
            salesWTDGoal: 2,
            salesMTDGoal: 6,
            emoji: "🧠",
            sortIndex: 0
        ),
        TeamMember(
            name: "Ron",
            quotesToday: 0,
            salesWTD: 0,
            salesMTD: 0,
            quotesGoal: 10,
            salesWTDGoal: 2,
            salesMTDGoal: 6,
            emoji: "🏌️",
            sortIndex: 1
        ),
        TeamMember(
            name: "Deanna",
            quotesToday: 0,
            salesWTD: 0,
            salesMTD: 0,
            quotesGoal: 10,
            salesWTDGoal: 2,
            salesMTDGoal: 6,
            emoji: "🎯",
            sortIndex: 2
        ),
        TeamMember(
            name: "Dimitri",
            quotesToday: 0,
            salesWTD: 0,
            salesMTD: 0,
            quotesGoal: 10,
            salesWTDGoal: 2,
            salesMTDGoal: 6,
            emoji: "🚀",
            sortIndex: 3
        )
    ]
}
