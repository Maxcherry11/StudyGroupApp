import Foundation
import CloudKit
import SwiftUI

class WinTheDayViewModel: ObservableObject {
    @Published var teamData: [TeamMember] = []
    /// Set to true once CloudKit data has been loaded and sorted
    @Published var isLoaded = false


    init() {
        let stored = loadLocalMembers().sorted { $0.sortIndex < $1.sortIndex }
        self.teamMembers = stored
        self.displayedMembers = stored
        // Use locally stored order as a placeholder until CloudKit loads
        self.teamData = stored
        self.cards = loadCardsFromDevice()
        self.displayedCards = self.cards
        let names = Self.loadLocalGoalNames()
        self.goalNames = names
        self.lastGoalHash = Self.computeGoalHash(for: names)
        self.lastFetchHash = computeHash(for: stored)
        // Initialize members from the splash screen user list
        fetchMembersFromCloud()
    }
    @Published var teamMembers: [TeamMember] = []
    @Published var displayedMembers: [TeamMember] = []
    @Published var cards: [Card] = []
    @Published var displayedCards: [Card] = []
    @Published var selectedUserName: String = ""
    @Published var goalNames: GoalNames = GoalNames()
    /// Indicates whether a card sync operation is in progress
    @Published var isLoading: Bool = false
    private let storageKey = "WTDMemberStorage"
    private static let goalNameKey = "WTDGoalNames"
    private let cardsStorageKey = "WTDCardsStorage"
    private var hasLoadedDisplayOrder = false
    /// Signature of the last CloudKit fetch used to detect changes
    private var lastFetchHash: Int?
    private var lastGoalHash: Int?
    private let weeklyResetKey = "WTDWeeklyReset"
    private let monthlyResetKey = "WTDMonthlyReset"

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
            hasher.combine(m.quotesGoal)
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

    /// Reorders cards and updates ``teamData`` after the user saves edits.
    /// This keeps the visible list in sync with the latest production values.
    func reorderAfterSave() {
        reorderCards()
        teamData = teamMembers
    }

    // MARK: - Card Sync Helpers


    private func loadLocalCards() {
        if let data = UserDefaults.standard.data(forKey: cardsStorageKey),
           let cached = try? JSONDecoder().decode([Card].self, from: data) {
            DispatchQueue.main.async {
                self.cards = cached.sorted(by: { $0.orderIndex < $1.orderIndex })
                self.displayedCards = self.cards
                print("📦 Loaded cards from local cache.")
            }
        } else {
            print("⚠️ No cached cards found.")
        }
    }

    private func saveCardsToLocal() {
        if let data = try? JSONEncoder().encode(cards) {
            UserDefaults.standard.set(data, forKey: cardsStorageKey)
            print("✅ Cards saved to local cache.")
        }
    }

    /// Convenience wrapper mirroring LifeScoreboardViewModel.fetchTeamMembersFromCloud
    /// for fetching the latest production values.
    func fetchScores() {
        fetchMembersFromCloud()
    }

    /// Loads all `TeamMember` records from CloudKit and populates
    /// ``teamData`` without altering the selected user.
    func fetchTeam() {
        CloudKitManager.shared.fetchTeam { [weak self] members in
            guard let self = self else { return }

            DispatchQueue.main.async {
                self.teamData = members.sorted {
                    let scoreA = $0.quotesToday + $0.salesWTD + $0.salesMTD
                    let scoreB = $1.quotesToday + $1.salesWTD + $1.salesMTD
                    return scoreA > scoreB
                }

                self.teamMembers = self.teamData
                self.displayedMembers = self.teamData
                print("✅ Loaded \(self.teamData.count) TeamMember records from CloudKit")
            }
        }
    }

    /// Sets ``selectedUserName`` based on a CloudKit lookup without
    /// modifying ``teamData``.
    func fetchUsers(_ name: String) {
        CloudKitManager.shared.fetchFiltered(byUserName: name) { [weak self] members in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.selectedUserName = members.first?.name ?? name
            }
        }
    }

    /// Loads team members using the names from ``UserManager`` and updates the
    /// local cache. This mirrors the local-loading behavior of
    /// ``LifeScoreboardViewModel`` so the view does not depend on CloudKit.
    func fetchMembersFromCloud(completion: (() -> Void)? = nil) {
        let names = UserManager.shared.userList
        updateLocalEntries(names: names)
        initializeResetDatesIfNeeded()
        performResetsIfNeeded()
        reorderCards()
        teamData = teamMembers
        isLoaded = true
        saveLocal()

        print("🔄 Sorted teamData by actual progress:")
        for member in teamData {
            let total = member.quotesToday + member.salesWTD + member.salesMTD
            print("➡️ \(member.name): \(total)")
        }

        ensureCardsForAllUsers(names)
        completion?()
    }

    func saveEdits(for card: Card) {
        CloudKitManager.saveCard(card)
        withAnimation {
            displayedCards = cards.sorted { $0.production > $1.production }
        }
    }

    /// Saves edits for a given ``TeamMember`` and updates ordering.
    func saveEdits(for member: TeamMember) {
        withAnimation { reorderAfterSave() }
        saveLocal()
        saveMember(member) { _ in
            DispatchQueue.main.async {
                self.teamData.sort {
                    let scoreA = $0.quotesToday + $0.salesWTD + $0.salesMTD
                    let scoreB = $1.quotesToday + $1.salesWTD + $1.salesMTD
                    return scoreA > scoreB
                }

                print("🔄 Re-sorted after Save:")
                for member in self.teamData {
                    let total = member.quotesToday + member.salesWTD + member.salesMTD
                    print("➡️ \(member.name): \(total)")
                }
            }
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

    // MARK: - Card Persistence

    private struct StoredCard: Codable {
        var id: String
        var name: String
        var emoji: String
        var production: Int
        var orderIndex: Int
    }

    private func saveCardsToDevice() {
        let stored = cards.map { card in
            StoredCard(id: card.id, name: card.name, emoji: card.emoji, production: card.production, orderIndex: card.orderIndex)
        }
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: cardsStorageKey)
        }
    }

    private func loadCardsFromDevice() -> [Card] {
        guard let data = UserDefaults.standard.data(forKey: cardsStorageKey),
              let decoded = try? JSONDecoder().decode([StoredCard].self, from: data) else {
            return []
        }
        return decoded.map { Card(id: $0.id, name: $0.name, emoji: $0.emoji, production: $0.production, orderIndex: $0.orderIndex) }
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

        for name in names where !teamMembers.contains(where: { $0.name == name }) {
            if let saved = stored.first(where: { $0.name == name }) {
                teamMembers.append(saved)
            } else {
                let member = TeamMember(name: name)
                // Mirror the goals of the first existing member so new cards
                // don't default to 1/1/1 when added locally before CloudKit sync.
                if let template = teamMembers.first {
                    member.quotesGoal = template.quotesGoal
                    member.salesWTDGoal = template.salesWTDGoal
                    member.salesMTDGoal = template.salesMTDGoal
                }
                member.sortIndex = teamMembers.count
                teamMembers.append(member)
            }
        }
    }


    func saveMember(_ member: TeamMember, completion: ((CKRecord.ID?) -> Void)? = nil) {
        CloudKitManager.shared.save(member) { id in
            completion?(id)
        }
        saveLocal()
    }

    /// Updates only the emoji for the provided member in CloudKit.
    func updateEmoji(for member: TeamMember, completion: ((Bool) -> Void)? = nil) {
        CloudKitManager.shared.updateEmoji(for: member.name, emoji: member.emoji) { success in
            completion?(success)
        }
        saveLocal()
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
                let ordered = savedOrder.compactMap { name in
                    self.teamMembers.first { $0.name == name }
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
        let order = displayedMembers.map { $0.name }
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

    /// Ensures a placeholder card exists for each provided user name.
    /// Local cards are persisted so the UI can appear immediately before
    /// CloudKit records sync down. Any newly created cards are also
    /// uploaded to CloudKit using a stable record ID to initialize the
    /// `Card` record type if needed.
    func ensureCardsForAllUsers(_ users: [String]) {
        for (index, name) in users.enumerated() {
            if !cards.contains(where: { $0.name == name }) {
                let card = Card(id: "card-\(name)", name: name, emoji: "\u{2728}", orderIndex: index)
                cards.append(card)
                CloudKitManager.saveCard(card)
            }
        }
        saveCardsToDevice()
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
} // end of class WinTheDayViewModel

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
