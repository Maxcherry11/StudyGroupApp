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
        print("🗃️ WTD init loaded \(stored.count) cached members.")
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

    /// Loads all `Card` records from CloudKit and updates the local arrays.
    func fetchCardsFromCloud() {
        CloudKitManager.fetchCards { [weak self] records in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.cards = records.sorted { $0.orderIndex < $1.orderIndex }
                self.displayedCards = self.cards
                self.saveCardsToDevice()
            }
        }
    }

    /// Loads all `TeamMember` and `Card` records from CloudKit, updating the
    /// local caches when changes are detected.
    func fetchMembersFromCloud(completion: (() -> Void)? = nil) {
        DispatchQueue.main.async {
            CloudKitManager.shared.migrateTeamMemberFieldsIfNeeded()

            CloudKitManager.shared.fetchTeam { [weak self] fetched in
                guard let self = self else { return }
                let newHash = self.computeHash(for: fetched)

                DispatchQueue.main.async {
                    // ⚠️ Non-destructive merge: only override from CloudKit when it returns non-empty
                    if !fetched.isEmpty {
                        // Merge by name so we don't drop fields if only some members changed
                        var byName: [String: TeamMember] = [:]
                        for m in self.teamMembers { byName[m.name] = m }
                        for m in fetched {
                            byName[m.name] = m // fetched wins entirely per member
                        }
                        let merged = Array(byName.values).sorted { $0.sortIndex < $1.sortIndex }
                        self.teamMembers = merged
                        self.displayedMembers = merged
                        self.teamData = merged
                        self.reorderAfterSave()
                        self.lastFetchHash = newHash
                        self.saveLocalIfNonEmpty()
                    } else {
                        print("⚠️ CloudKit fetchTeam returned 0 members; keeping local cache to avoid blank screen.")
                    }

                    // Ensure local entries mirror the latest user list only if we actually have a list
                    let allNames = UserManager.shared.userList
                    if !allNames.isEmpty {
                        self.updateLocalEntries(names: allNames)
                    } else {
                        print("ℹ️ User list is empty; skipping updateLocalEntries to avoid clearing cached members.")
                    }

                    CloudKitManager.fetchCards { cards in
                        DispatchQueue.main.async {
                            if cards.isEmpty {
                                print("⚠️ CloudKit fetchCards returned 0; preserving local cards to avoid blank UI.")
                            } else {
                                var merged = self.cards
                                for card in cards {
                                    if let idx = merged.firstIndex(where: { $0.id == card.id }) {
                                        merged[idx] = card
                                    } else {
                                        merged.append(card)
                                    }
                                }
                                self.cards = merged.sorted { $0.orderIndex < $1.orderIndex }
                                self.displayedCards = self.cards
                                self.saveCardsToDevice()
                            }

                            // 🧩 Backfill: If a Card has a default/empty emoji but TeamMember has a real one, copy it up and persist to CloudKit
                            for m in self.teamMembers {
                                if let idx = self.cards.firstIndex(where: { $0.name == m.name }) {
                                    let current = self.cards[idx].emoji.trimmingCharacters(in: .whitespacesAndNewlines)
                                    let memberEmoji = m.emoji.trimmingCharacters(in: .whitespacesAndNewlines)
                                    let isDefaultOrEmpty = current.isEmpty || current == "\u{2728}"
                                    let hasRealMemberEmoji = !memberEmoji.isEmpty && memberEmoji != "\u{2728}"
                                    if isDefaultOrEmpty && hasRealMemberEmoji {
                                        self.cards[idx].emoji = memberEmoji
                                        self.saveCardsToDevice()
                                        CloudKitManager.saveCard(self.cards[idx])
                                    }
                                }
                            }

                            // 🔗 Keep emoji as a single source of truth from Card -> TeamMember
                            for idx in self.teamMembers.indices {
                                if let card = self.cards.first(where: { $0.name == self.teamMembers[idx].name }) {
                                    self.teamMembers[idx].emoji = card.emoji
                                }
                            }
                            self.saveLocal()

                            let userList = UserManager.shared.userList
                            let names = userList.isEmpty ? self.teamMembers.map { $0.name } : userList
                            self.ensureCardsForAllUsers(names)

                            self.lastGoalHash = Self.computeGoalHash(for: self.goalNames)
                            self.isLoaded = true
                            completion?()
                        }
                    }
                }
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
        withAnimation { reorderAfterSave() }
        saveLocal()
        saveWinTheDayFields(member) { _ in
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
        guard !names.isEmpty else { return }
        teamMembers.removeAll { member in !names.contains(member.name) }

        let stored = loadLocalMembers()

        for name in names where !teamMembers.contains(where: { $0.name == name }) {
            if let saved = stored.first(where: { $0.name == name }) {
                teamMembers.append(saved)
            }
            // Note: New TeamMember objects are now created in ensureCardsForAllUsers
            // to ensure they have proper goal values copied from existing members
        }
    }


    func saveMember(_ member: TeamMember, completion: ((CKRecord.ID?) -> Void)? = nil) {
        CloudKitManager.shared.save(member) { id in
            completion?(id)
        }
        saveLocal()
    }

    /// Saves only Win The Day specific fields to avoid affecting Life Scoreboard data
    func saveWinTheDayFields(_ member: TeamMember, completion: ((CKRecord.ID?) -> Void)? = nil) {
        // First fetch the existing record to update it properly
        let recordID = CKRecord.ID(recordName: "member-\(member.name)")
        
        CloudKitManager.container.publicCloudDatabase.fetch(withRecordID: recordID) { [weak self] existingRecord, error in
            if let error = error {
                print("❌ Failed to fetch existing record for \(member.name): \(error.localizedDescription)")
                // Fallback to regular save if fetch fails
                self?.saveMember(member, completion: completion)
                return
            }
            
            guard let record = existingRecord else {
                print("❌ No existing record found for \(member.name), falling back to regular save")
                self?.saveMember(member, completion: completion)
                return
            }
            
            // Update only the Win The Day fields in the existing record
            record["quotesToday"] = member.quotesToday as CKRecordValue
            record["salesWTD"] = member.salesWTD as CKRecordValue
            record["salesMTD"] = member.salesMTD as CKRecordValue
            record["quotesGoal"] = member.quotesGoal as CKRecordValue
            record["salesWTDGoal"] = member.salesWTDGoal as CKRecordValue
            record["salesMTDGoal"] = member.salesMTDGoal as CKRecordValue
            // record["emoji"] = member.emoji as CKRecordValue    // Removed: emoji is now sourced from Card only
            record["sortIndex"] = member.sortIndex as CKRecordValue
            
            // Save the updated record
            CloudKitManager.container.publicCloudDatabase.save(record) { _, error in
                if let error = error {
                    print("❌ Failed to save Win The Day fields: \(error.localizedDescription)")
                } else {
                    print("✅ Saved Win The Day fields for \(member.name)")
                }
                completion?(record.recordID)
            }
        }
        
        saveLocal()
    }

    /// Updates only the emoji for the provided member in CloudKit.
    func updateEmoji(for member: TeamMember, completion: ((Bool) -> Void)? = nil) {
        // Update in CloudKit via the shared helper
        CloudKitManager.shared.updateEmoji(for: member.name, emoji: member.emoji) { success in
            DispatchQueue.main.async {
                // Reflect change in TeamMember array
                if let memberIndex = self.teamMembers.firstIndex(where: { $0.name == member.name }) {
                    self.teamMembers[memberIndex].emoji = member.emoji
                }
                // Reflect change in Card array and persist
                if let cardIndex = self.cards.firstIndex(where: { $0.name == member.name }) {
                    self.cards[cardIndex].emoji = member.emoji
                    self.saveCardsToDevice()
                    // Push card emoji to CloudKit to keep Card and TeamMember consistent
                    CloudKitManager.saveCard(self.cards[cardIndex])
                }
                // Persist TeamMember change locally
                self.saveLocal()
                completion?(success)
            }
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
            saveWinTheDayFields(teamMembers[index]) { _ in }
        }
        teamMembers = teamMembers.map { $0 }
    }

    private func resetMonthlyValues() {
        for index in teamMembers.indices {
            teamMembers[index].salesMTD = 0
            saveWinTheDayFields(teamMembers[index]) { _ in }
        }
        teamMembers = teamMembers.map { $0 }
    }

    /// Ensures a placeholder card exists for each provided user name.
    /// Local cards are persisted so the UI can appear immediately before
    /// CloudKit records sync down. Any newly created cards are also
    /// uploaded to CloudKit using a stable record ID to initialize the
    /// `Card` record type if needed.
    /// Also ensures TeamMember objects exist with proper goal values copied from existing members.
    func ensureCardsForAllUsers(_ users: [String]) {
        // Determine template goals from existing members or local storage; fallback to defaults
        let templateGoals: (quotes: Int, wtd: Int, mtd: Int) = {
            if let t = teamMembers.first(where: { $0.quotesGoal > 0 || $0.salesWTDGoal > 0 || $0.salesMTDGoal > 0 }) {
                return (t.quotesGoal, t.salesWTDGoal, t.salesMTDGoal)
            } else if let t = loadLocalMembers().first(where: { $0.quotesGoal > 0 || $0.salesWTDGoal > 0 || $0.salesMTDGoal > 0 }) {
                return (t.quotesGoal, t.salesWTDGoal, t.salesMTDGoal)
            } else {
                return (10, 2, 6)
            }
        }()
        for (index, name) in users.enumerated() {
            // Ensure Card exists
            if !cards.contains(where: { $0.name == name }) {
                var newEmoji = "\u{2728}" // default
                if let existingMember = teamMembers.first(where: { $0.name == name }), !existingMember.emoji.isEmpty {
                    newEmoji = existingMember.emoji
                } else if let localMember = loadLocalMembers().first(where: { $0.name == name }), !localMember.emoji.isEmpty {
                    newEmoji = localMember.emoji
                }
                let card = Card(id: "card-\(name)", name: name, emoji: newEmoji, orderIndex: index)
                cards.append(card)
                CloudKitManager.saveCard(card)
            }
            
            // Ensure TeamMember exists with proper goals
            if let idxExisting = teamMembers.firstIndex(where: { $0.name == name }) {
                let m = teamMembers[idxExisting]
                if m.quotesGoal == 0 && m.salesWTDGoal == 0 && m.salesMTDGoal == 0 {
                    teamMembers[idxExisting].quotesGoal = templateGoals.quotes
                    teamMembers[idxExisting].salesWTDGoal = templateGoals.wtd
                    teamMembers[idxExisting].salesMTDGoal = templateGoals.mtd
                    // Persist the repaired goals to CloudKit so other devices align
                    saveWinTheDayFields(teamMembers[idxExisting])
                }
            }
            if !teamMembers.contains(where: { $0.name == name }) {
                let member = TeamMember(name: name)
                // Set goals from template so new members never start at 0/0/0
                member.quotesGoal = templateGoals.quotes
                member.salesWTDGoal = templateGoals.wtd
                member.salesMTDGoal = templateGoals.mtd
                member.sortIndex = teamMembers.count
                teamMembers.append(member)
                // Save the new member to CloudKit using Win The Day fields only
                saveWinTheDayFields(member)
            }
        }
        saveCardsToDevice()
        
        // Update teamData to reflect the new members so the UI displays them properly
        teamData = teamMembers
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
    private func saveLocalIfNonEmpty() {
        guard !teamMembers.isEmpty else { return }
        saveLocal()
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

