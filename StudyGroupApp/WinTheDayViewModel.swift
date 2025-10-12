import Foundation
import CloudKit
import SwiftUI

// MARK: - Trophy Streak State (Local Only)
struct TrophyStreakState: Codable {
    var streakCount: Int
    var lastFinalizedWeekId: String?
    var memberName: String
    
    init(streakCount: Int = 0, lastFinalizedWeekId: String? = nil, memberName: String = "") {
        self.streakCount = streakCount
        self.lastFinalizedWeekId = lastFinalizedWeekId
        self.memberName = memberName
    }
}

@MainActor
class WinTheDayViewModel: ObservableObject {
    /// Shared instance to preserve trophy data across navigation
    static let shared = WinTheDayViewModel()
    
    @Published var teamData: [TeamMember] = []
    /// Set to true once CloudKit data has been loaded and sorted
    @Published var isLoaded = false
    /// True while the Win The Day editor is open. Used to block reorders/sorts.
    @Published var isEditing: Bool = false
    @Published var isWarm: Bool = false
    
    // Used to mute list animations during bootstrap from outside the view model easily.
    static var globalIsBootstrapping: Bool = false
    
    // Debounce mechanism to prevent multiple simultaneous CloudKit saves
    private var saveTimers: [UUID: Timer] = [:]
    // Counter for logging saves
    private var saveCount = 0
    // Flag to prevent multiple finalizations in the same session
    private var hasFinalizedThisWeek: Bool = false

    // MARK: - Data Sanitization Helpers
    nonisolated private static let valueCap: Int = 1_000_000
    nonisolated private static func clampNonNegative(_ v: Int) -> Int { max(0, min(v, Self.valueCap)) }

    nonisolated private static func sanitized(_ m: TeamMember) -> TeamMember {
        let copy = m
        copy.quotesToday  = Self.clampNonNegative(copy.quotesToday)
        copy.salesWTD     = Self.clampNonNegative(copy.salesWTD)
        copy.salesMTD     = Self.clampNonNegative(copy.salesMTD)
        copy.quotesGoal   = Self.clampNonNegative(copy.quotesGoal)
        copy.salesWTDGoal = Self.clampNonNegative(copy.salesWTDGoal)
        copy.salesMTDGoal = Self.clampNonNegative(copy.salesMTDGoal)
        return copy
    }

    private func sanitizeMembersArray(_ arr: [TeamMember]) -> [TeamMember] {
        arr.map { Self.sanitized($0) }
    }

    private func sanitizeCardsArray(_ arr: [Card]) -> [Card] {
        arr.map { card in
            var c = card
            c.production = Self.clampNonNegative(c.production)
            return c
        }
    }

    init() {
        let stored = sanitizeMembersArray(loadLocalMembers()).sorted { $0.sortIndex < $1.sortIndex }
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
    /// MARK: - Auto Reset Tracking (Weekly/Monthly)
    private let wtdLastWeeklyResetKey  = "wtd-last-weekly-reset"
    private let wtdLastMonthlyResetKey = "wtd-last-monthly-reset"
    private let wtdLastWeeklyResetIdKey  = "wtd-last-weekly-reset-id"
    private let wtdLastMonthlyResetIdKey = "wtd-last-monthly-reset-id"

    /// Flag a deferred weekly reset when the member list is empty at the moment we detect a new week.
    private var pendingWeeklyReset: Bool = false
    /// Flag a deferred monthly reset when the member list is empty at the moment we detect a new month.
    private var pendingMonthlyReset: Bool = false

    private var lastWeeklyResetId: String? {
        get {
            if let id = UserDefaults.standard.string(forKey: wtdLastWeeklyResetIdKey) {
                return id
            }
            if let legacyDate = UserDefaults.standard.object(forKey: wtdLastWeeklyResetKey) as? Date {
                let id = currentWeekId(legacyDate)
                UserDefaults.standard.set(id, forKey: wtdLastWeeklyResetIdKey)
                UserDefaults.standard.removeObject(forKey: wtdLastWeeklyResetKey)
                return id
            }
            return nil
        }
        set {
            UserDefaults.standard.set(newValue, forKey: wtdLastWeeklyResetIdKey)
            UserDefaults.standard.removeObject(forKey: wtdLastWeeklyResetKey)
        }
    }
    private var lastMonthlyResetId: String? {
        get {
            if let id = UserDefaults.standard.string(forKey: wtdLastMonthlyResetIdKey) {
                return id
            }
            if let legacyDate = UserDefaults.standard.object(forKey: wtdLastMonthlyResetKey) as? Date {
                let id = currentMonthId(legacyDate)
                UserDefaults.standard.set(id, forKey: wtdLastMonthlyResetIdKey)
                UserDefaults.standard.removeObject(forKey: wtdLastMonthlyResetKey)
                return id
            }
            return nil
        }
        set {
            UserDefaults.standard.set(newValue, forKey: wtdLastMonthlyResetIdKey)
            UserDefaults.standard.removeObject(forKey: wtdLastMonthlyResetKey)
        }
    }

    /// MARK: - Date Helpers
    private let resetTimeZone = TimeZone(identifier: "America/Chicago")!

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

    // MARK: - Stable sorting helpers
    func productionScore(_ m: TeamMember) -> Int {
        max(0, m.quotesToday + m.salesWTD + m.salesMTD)
    }

    func stableByScoreThenIndex(_ lhs: TeamMember, _ rhs: TeamMember) -> Bool {
        let l = productionScore(lhs)
        let r = productionScore(rhs)
        if l == r { return lhs.sortIndex < rhs.sortIndex }
        return l > r
    }

    /// Sorts ``displayedCards`` a single time based on production metrics.
    /// This mirrors the stable ordering used by Life Scoreboard.
    func loadInitialDisplayOrder() {
        guard !hasLoadedDisplayOrder else { return }
        guard !isEditing else {
            print("[REORDER] loadInitialDisplayOrder blocked because isEditing = true")
            return
        }
        print("[REORDER] loadInitialDisplayOrder executing")
        displayedMembers = teamMembers.sorted(by: stableByScoreThenIndex)
        hasLoadedDisplayOrder = true
    }

    /// Initializes ``displayedMembers`` only once using the current
    /// ``teamMembers`` order so that card order remains stable when returning
    /// from the splash screen.
    func initializeDisplayedCardsIfNeeded() {
        if displayedMembers.isEmpty {
            guard !isEditing else {
                print("[REORDER] initializeDisplayedCardsIfNeeded blocked because isEditing = true")
                return
            }
            print("[REORDER] initializeDisplayedCardsIfNeeded executing")
            displayedMembers = teamMembers.sorted { $0.sortIndex < $1.sortIndex }
        }
    }

    /// When all production values are equal (e.g., all zero), apply the provided
    /// snapshot order (by IDs) to keep the visual order stable.
    func applySnapshotOrderIfAllZero(_ snapshotIDs: [UUID]) {
        // Only apply if we have a complete snapshot and all totals are equal
        guard !snapshotIDs.isEmpty else { return }
        let allEqual = teamMembers.map { productionScore($0) }.allSatisfy { $0 == teamMembers.first.map(productionScore) }
        guard allEqual else { return }
        let indexByID: [UUID:Int] = Dictionary(uniqueKeysWithValues: snapshotIDs.enumerated().map { ($1, $0) })
        teamMembers.sort { (indexByID[$0.id] ?? Int.max) < (indexByID[$1.id] ?? Int.max) }
        for idx in teamMembers.indices { teamMembers[idx].sortIndex = idx }
        displayedMembers = teamMembers
        teamData = teamMembers
    }

    private func sortedMembersByScore() -> [TeamMember] {
        let sorted = teamMembers.sorted(by: stableByScoreThenIndex)
        for idx in sorted.indices {
            sorted[idx].sortIndex = idx
        }
        return sorted
    }

    /// Reorders cards and updates ``teamMembers`` / ``displayedMembers`` after the user saves edits.
    @MainActor
    /// Caller (usually the view) updates ``teamData`` inside any desired animation.
    func reorderAfterSave() {
        guard !isEditing else {
            print("[REORDER] reorderAfterSave blocked because isEditing = \(isEditing)")
            return
        }
        print("[REORDER] reorderAfterSave executing")
        
        // 🏆 PRESERVE TROPHY DATA: Store current trophy states before reordering
        let trophyStates = preserveTrophyData()

        let sorted = sortedMembersByScore()
        teamMembers = sorted
        displayedMembers = sorted
        lastFetchHash = computeHash(for: sorted)

        // 🏆 RESTORE TROPHY DATA: Ensure trophy states are preserved after reordering
        restoreTrophyData(trophyStates)
    }
    
    // MARK: - Trophy Data Protection
    
    /// Preserves trophy data for all team members during data operations
    private func preserveTrophyData() -> [UUID: TrophyStreakState] {
        var trophyStates: [UUID: TrophyStreakState] = [:]
        for member in teamMembers {
            trophyStates[member.id] = loadStreak(for: member.id)
        }
        return trophyStates
    }
    
    /// Restores trophy data for all team members after data operations
    private func restoreTrophyData(_ trophyStates: [UUID: TrophyStreakState]) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            for (memberID, trophyState) in trophyStates {
                // Only save if the trophy data has actually changed
                let currentState = self.loadStreak(for: memberID)
                if currentState.streakCount != trophyState.streakCount || 
                   currentState.lastFinalizedWeekId != trophyState.lastFinalizedWeekId {
                    self.saveStreak(trophyState, for: memberID)
                }
            }
        }
    }
    
    // MARK: - Trophy Streak Persistence
    
    func streakKey(for memberID: UUID) -> String { "trophyStreak.\(memberID.uuidString)" }
    
    func loadStreak(for memberID: UUID) -> TrophyStreakState {
        // Load from local storage only
        let key = streakKey(for: memberID)
        if let data = UserDefaults.standard.data(forKey: key),
           let state = try? JSONDecoder().decode(TrophyStreakState.self, from: data) {
            return state
        }
        
        // Return default state if no cached data
        guard let member = teamMembers.first(where: { $0.id == memberID }) else {
            return TrophyStreakState(streakCount: 0, lastFinalizedWeekId: nil, memberName: "")
        }
        
        return TrophyStreakState(streakCount: 0, lastFinalizedWeekId: nil, memberName: member.name)
    }
    
    func saveStreak(_ state: TrophyStreakState, for memberID: UUID) {
        // Save to local storage only (like other features in the app)
        let key = streakKey(for: memberID)
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: key)
        }
        
        // Log occasionally to reduce spam
        saveCount += 1
        if saveCount % 10 == 0 {
            print("🏆 [TROPHY] Saved trophy streak locally for \(state.memberName): \(state.streakCount) - \(saveCount) saves")
        }
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
                guard !self.isEditing else {
                    print("[REORDER] fetchTeam: blocked sort/update because isEditing = true")
                    return
                }
                print("[REORDER] fetchTeam: applying sorted order from CloudKit")

                let cleaned = self.sanitizeMembersArray(members)
                self.teamData = cleaned.sorted(by: self.stableByScoreThenIndex)

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
                let cleaned = self.sanitizeCardsArray(records)
                self.cards = cleaned.sorted { $0.orderIndex < $1.orderIndex }
                self.displayedCards = self.cards
                self.saveCardsToDevice()
            }
        }
    }

    /// Loads all `TeamMember` and `Card` records from CloudKit, updating the
    /// local caches when changes are detected.
    func fetchMembersFromCloud(completion: (() -> Void)? = nil) {
        DispatchQueue.main.async {
            // 🚫 Do not mutate any arrays while editing — prevents card jumps on Edit tap
            if self.isEditing {
                print("[REORDER] fetchMembersFromCloud: skipped updates because isEditing = true")
                completion?()
                return
            }
            
            // 🏆 PRESERVE TROPHY DATA: Store current trophy states before CloudKit sync
            let trophyStates = self.preserveTrophyData()
            
            CloudKitManager.shared.migrateTeamMemberFieldsIfNeeded()

            CloudKitManager.shared.fetchTeam { [weak self] fetched in
                guard let self = self else { return }
                let newHash = self.computeHash(for: fetched)
                let fetchedClean = self.sanitizeMembersArray(fetched)

                DispatchQueue.main.async {
                    // ⚠️ Non-destructive merge: only override from CloudKit when it returns non-empty
                    if !fetchedClean.isEmpty {
                        // Merge by name so we don't drop fields if only some members changed
                        var byName: [String: TeamMember] = [:]
                        for m in self.teamMembers { byName[m.name] = m }
                        for m in fetchedClean {
                            byName[m.name] = m // fetched wins entirely per member
                        }
                        let merged = Array(byName.values).sorted { $0.sortIndex < $1.sortIndex }
                        self.teamMembers = merged
                        self.displayedMembers = merged
                        self.teamData = merged
                        self.lastFetchHash = newHash
                        self.saveLocalIfNonEmpty()
                        
                        // 🏆 RESTORE TROPHY DATA: Ensure trophy states are preserved after CloudKit merge
                        self.restoreTrophyData(trophyStates)

                        // If a weekly/monthly reset was deferred because members were missing, retry now that data is present.
                        if self.pendingWeeklyReset || self.pendingMonthlyReset {
                            print("⚠️ [AutoReset] Retrying deferred resets after CloudKit sync")
                            self.performAutoResetsIfNeeded(currentDate: Date())
                        }
                    } else {
                        print("⚠️ CloudKit fetchTeam returned 0 members; keeping local cache to avoid blank screen.")
                    }

                    // Ensure local entries mirror the latest user list only if we actually have a list
                    let allNames = UserManager.shared.userList
                    if !allNames.isEmpty {
                        self.updateLocalEntries(names: allNames)
                        // 🏆 RESTORE TROPHY DATA AGAIN: Ensure trophy states are preserved after updateLocalEntries
                        self.restoreTrophyData(trophyStates)
                    } else {
                        print("ℹ️ User list is empty; skipping updateLocalEntries to avoid clearing cached members.")
                    }

                    CloudKitManager.fetchCards { cards in
                        DispatchQueue.main.async {
                            let cleanedCards = self.sanitizeCardsArray(cards)
                            if cleanedCards.isEmpty {
                                print("⚠️ CloudKit fetchCards returned 0; preserving local cards to avoid blank UI.")
                            } else {
                                var merged = self.cards
                                for card in cleanedCards {
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

                            // 🔗 Keep emoji as a single source of truth from TeamMember -> Card
                            var didChangeAnyCardEmoji = false
                            for idx in self.cards.indices {
                                if let member = self.teamMembers.first(where: { $0.name == self.cards[idx].name }) {
                                    if self.cards[idx].emoji != member.emoji {
                                        self.cards[idx].emoji = member.emoji
                                        didChangeAnyCardEmoji = true
                                    }
                                }
                            }
                            if didChangeAnyCardEmoji {
                                self.saveCardsToDevice()
                                // Persist changed cards to CloudKit so other devices get the new emoji
                                for card in self.cards { CloudKitManager.saveCard(card) }
                            }
                            self.saveLocal()

                            let userList = UserManager.shared.userList
                            let names = userList.isEmpty ? self.teamMembers.map { $0.name } : userList
                            self.ensureCardsForAllUsers(names)

                            self.lastGoalHash = Self.computeGoalHash(for: self.goalNames)
                            self.isLoaded = true
                            
                            // 🏆 FINAL TROPHY RESTORATION: Ensure trophy states are preserved after ALL operations
                            self.restoreTrophyData(trophyStates)
                            
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
        guard !isEditing else {
            print("[REORDER] saveEdits(for:) blocked because isEditing = true")
            return
        }
        withAnimation { reorderAfterSave() }
        saveLocal()
        saveWinTheDayFields(member) { _ in
            DispatchQueue.main.async {
                guard !self.isEditing else {
                    print("[REORDER] saveEdits completion: blocked teamData.sort because isEditing = true")
                    return
                }
                print("[REORDER] saveEdits completion: teamData.sort executing")
                self.teamData.sort(by: self.stableByScoreThenIndex)

                print("🔄 Re-sorted after Save:")
                for member in self.teamData {
                    let total = member.quotesToday + member.salesWTD + member.salesMTD
                    print("➡️ \(member.name): \(total)")
                }
            }
        }
    }

    private func saveLocal() {
        // 🏆 SAFETY CHECK: Ensure we don't accidentally clear trophy data
        // Trophy data is stored separately and should not be affected by team member saves
        let codable = sanitizeMembersArray(teamMembers).map { $0.codable }
        if let data = try? JSONEncoder().encode(codable) {
            UserDefaults.standard.set(data, forKey: storageKey)
            print("💾 Saved \(teamMembers.count) team members to local storage (trophy data preserved)")
        }
    }

    private func loadLocalMembers() -> [TeamMember] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([TeamMember.CodableModel].self, from: data) else {
            return []
        }
        return sanitizeMembersArray(decoded.map { TeamMember(codable: $0) })
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
        let stored = sanitizeCardsArray(cards).map { card in
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
        let mapped = decoded.map { Card(id: $0.id, name: $0.name, emoji: $0.emoji, production: $0.production, orderIndex: $0.orderIndex) }
        return sanitizeCardsArray(mapped)
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
        
        // 🏆 PRESERVE TROPHY DATA: Store current trophy states before updating entries
        let trophyStates = preserveTrophyData()
        
        teamMembers.removeAll { member in !names.contains(member.name) }

        let stored = loadLocalMembers()

        for name in names where !teamMembers.contains(where: { $0.name == name }) {
            if let saved = stored.first(where: { $0.name == name }) {
                teamMembers.append(saved)
            }
            // Note: New TeamMember objects are now created in ensureCardsForAllUsers
            // to ensure they have proper goal values copied from existing members
        }
        
        // 🏆 RESTORE TROPHY DATA: Ensure trophy states are preserved after updating entries
        restoreTrophyData(trophyStates)
    }


    func saveMember(_ member: TeamMember, completion: ((CKRecord.ID?) -> Void)? = nil) {
        CloudKitManager.shared.save(member) { id in
            completion?(id)
        }
        saveLocal()
    }

    /// Saves only Win The Day specific fields to avoid affecting Life Scoreboard data
    func saveWinTheDayFields(_ member: TeamMember, completion: ((CKRecord.ID?) -> Void)? = nil) {
        let memberID = member.id
        let memberName = member.name

        // 🏆 PRESERVE TROPHY DATA: Store current trophy state before saving
        let currentTrophyState = loadStreak(for: memberID)
        
        // First fetch the existing record to update it properly
        let recordID = CKRecord.ID(recordName: "member-\(memberName)")

        CloudKitManager.container.publicCloudDatabase.fetch(withRecordID: recordID) { [weak self] existingRecord, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let memberIndex = self.teamMembers.firstIndex(where: { $0.id == memberID }) else {
                    completion?(nil)
                    return
                }
                let memberRef = self.teamMembers[memberIndex]

                func applyAndSave(to record: CKRecord) async {
                    // Clamp values before write
                    let safe = Self.sanitized(memberRef)
                    
                    // Update only Win The Day fields
                    record["quotesToday"] = safe.quotesToday as CKRecordValue
                    record["salesWTD"] = safe.salesWTD as CKRecordValue
                    record["salesMTD"] = safe.salesMTD as CKRecordValue
                    record["quotesGoal"] = safe.quotesGoal as CKRecordValue
                    record["salesWTDGoal"] = safe.salesWTDGoal as CKRecordValue
                    record["salesMTDGoal"] = safe.salesMTDGoal as CKRecordValue
                    record["emoji"] = safe.emoji as CKRecordValue
                    record["emojiUserSet"] = safe.emojiUserSet as CKRecordValue
                    record["sortIndex"] = safe.sortIndex as CKRecordValue

                    print("\u{1F4BE} saveWinTheDayFields() saving for \(memberName) [quotes=\(safe.quotesToday), wtd=\(safe.salesWTD), mtd=\(safe.salesMTD), emoji=\(safe.emoji)] -> \(record.recordID.recordName)")
                    do {
                        let saved = try await CloudKitManager.container.publicCloudDatabase.save(record)
                        print("✅ saveWinTheDayFields() saved: \(saved.recordID.recordName)")
                        completion?(saved.recordID)
                    } catch {
                        print("❌ saveWinTheDayFields() save failed: \(error.localizedDescription)")
                        completion?(nil)
                    }
                }

                // Path 1: fetched existing by canonical ID
                if let record = existingRecord, error == nil {
                    await applyAndSave(to: record)
                    return
                }

                // Path 2: fallback query-by-name to catch legacy/non-canonical IDs
                print("\u{1F50D} saveWinTheDayFields() falling back to query-by-name for: \(memberName)")
                let predicate = NSPredicate(format: "name == %@", memberName)
                let query = CKQuery(recordType: TeamMember.recordType, predicate: predicate)
                var matched: CKRecord?

                await withCheckedContinuation { continuation in
                    CloudKitManager.container.publicCloudDatabase.fetch(withQuery: query, inZoneWith: nil, desiredKeys: nil, resultsLimit: 1) { result in
                        switch result {
                        case .success(let (matchResults, _)):
                            matched = matchResults.compactMap { _, r in try? r.get() }.first
                        case .failure(let err):
                            print("❌ saveWinTheDayFields() query-by-name failed: \(err.localizedDescription)")
                        }
                        continuation.resume()
                    }
                }

                if let record = matched {
                    await applyAndSave(to: record)
                    return
                }

                // Path 3: create canonical record if nothing found
                print("ℹ️ saveWinTheDayFields() creating canonical record for: \(memberName) -> \(recordID.recordName)")
                let newRecord = CKRecord(recordType: TeamMember.recordType, recordID: recordID)
                newRecord["name"] = memberName as CKRecordValue
                await applyAndSave(to: newRecord)
            }
        }
        
        // 🏆 RESTORE TROPHY DATA: Ensure trophy state is preserved after saving
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.saveStreak(currentTrophyState, for: memberID)
        }
        
        saveLocal()
    }

    /// Updates only the emoji for the provided member in CloudKit.
    func updateEmoji(for member: TeamMember, completion: ((Bool) -> Void)? = nil) {
        // Update local TeamMember model
        if let memberIndex = teamMembers.firstIndex(where: { $0.name == member.name }) {
            teamMembers[memberIndex].emoji = member.emoji
        }
        
        // Update local Card model and persist to CloudKit
        if let cardIndex = cards.firstIndex(where: { $0.name == member.name }) {
            cards[cardIndex].emoji = member.emoji
            saveCardsToDevice()
            CloudKitManager.saveCard(cards[cardIndex])
        }
        
        // Persist emoji on the TeamMember record as well (belt-and-suspenders so all devices agree)
        if let idx = teamMembers.firstIndex(where: { $0.name == member.name }) {
            saveWinTheDayFields(teamMembers[idx]) { _ in }
        }
        
        // Persist locally and publish changes
        saveLocal()
        teamMembers = teamMembers.map { $0 }
        
        DispatchQueue.main.async {
            completion?(true)
        }
    }
    /// Reorders team members by current production (quotes + sales) and updates
    /// their persisted `sortIndex`. This mirrors the stable ordering logic used
    /// in LifeScoreboardViewModel.
    func reorderCards() {
        guard !isEditing else {
            print("[REORDER] reorderCards blocked because isEditing = \(isEditing)")
            return
        }
        print("[REORDER] reorderCards executing")
        let sorted = sortedMembersByScore()
        teamMembers = sorted
        displayedMembers = sorted
        teamData = sorted
        lastFetchHash = computeHash(for: sorted)
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
                if self.isEditing {
                    print("[REORDER] loadCardOrderFromCloud: blocked fallback sort because isEditing = true")
                    self.displayedMembers = self.teamMembers
                } else {
                    let sorted = self.teamMembers.sorted(by: self.stableByScoreThenIndex)
                    print("[REORDER] loadCardOrderFromCloud: applying fallback sort")
                    self.displayedMembers = sorted
                }
            }
        }
    }

    // MARK: - Editing gates (optional, callable from the View)
    func beginEditing() { isEditing = true }
    func endEditingAndReorder() {
        isEditing = false
        reorderAfterSave()
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

    // MARK: - Trophy Finalization Logic
    
    /// Checks if weekly goals are met for a member
    private func isWeeklyMet(for member: TeamMember) -> Bool {
        // Only award if a corresponding goal is set (> 0)
        let quotesHit = member.quotesGoal > 0 && member.quotesToday >= member.quotesGoal
        let salesHit  = member.salesWTDGoal > 0 && member.salesWTD >= member.salesWTDGoal
        return quotesHit || salesHit
    }
    
    /// Generates a unique week ID for trophy finalization tracking
    private func currentWeekId(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = resetTimeZone
        cal.firstWeekday = 1 // Sunday
        let components = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return "\(components.yearForWeekOfYear ?? 0)-W\(components.weekOfYear ?? 0)"
    }

    private func currentMonthId(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = resetTimeZone
        let components = cal.dateComponents([.year, .month], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        return String(format: "%04d-M%02d", year, month)
    }
    
    /// Resets the session finalization flag when a new week starts
    private func resetFinalizationFlagIfNewWeek(now: Date = Date()) {
        let weekId = currentWeekId(now)
        // Check if we're in a new week by comparing with stored week
        let lastFinalizedWeekKey = "lastFinalizedWeekId"
        let lastWeekId = UserDefaults.standard.string(forKey: lastFinalizedWeekKey)
        
        if lastWeekId != weekId {
            hasFinalizedThisWeek = false
            UserDefaults.standard.set(weekId, forKey: lastFinalizedWeekKey)
            print("🏆 [FINALIZE] New week detected (\(weekId)), resetting finalization flag")
        }
    }
    
    /// Finalizes trophies for the current week if needed
    func finalizeCurrentWeekIfNeeded(now: Date = Date()) {
        // Prevent multiple finalizations in the same session
        if hasFinalizedThisWeek {
            print("🏆 [FINALIZE] Already finalized this week in this session, skipping")
            return
        }
        
        // Determine this week id (we finalize the week ending now)
        let weekId = currentWeekId(now)
        print("🏆 [FINALIZE] Starting finalizeCurrentWeekIfNeeded for week: \(weekId)")
        let lastFinalizedWeekKey = "lastFinalizedWeekId"
        let lastWeekId = UserDefaults.standard.string(forKey: lastFinalizedWeekKey) ?? "nil"
        print("🏆 [FINALIZE] Previously finalized week id: \(lastWeekId)")
        
        // For each member, if we haven't finalized this week yet, finalize using current values.
        for member in teamMembers {
            var state = loadStreak(for: member.id)
            print("🏆 [FINALIZE] Member \(member.name) - Current: \(state.streakCount) trophies, lastFinalizedWeekId: \(state.lastFinalizedWeekId ?? "nil")")
            
            // Only finalize once per week per member
            if state.lastFinalizedWeekId == weekId { 
                print("🏆 [FINALIZE] Member \(member.name) - Already finalized this week, skipping")
                continue 
            }
            
            let wasWeeklyMet = isWeeklyMet(for: member)
            print("🏆 [FINALIZE] Member \(member.name) - Weekly goals met: \(wasWeeklyMet)")
            
            if wasWeeklyMet {
                state.streakCount += 1
                print("🏆 [FINALIZE] Member \(member.name) - Incremented streak to: \(state.streakCount)")
            } else {
                state.streakCount = 0
                print("🏆 [FINALIZE] Member \(member.name) - Reset streak to: \(state.streakCount)")
            }
            state.lastFinalizedWeekId = weekId
            saveStreak(state, for: member.id)
            print("🏆 [FINALIZE] Member \(member.name) - Saved streak: \(state.streakCount) trophies")
        }
        
        // Mark as finalized for this session
        hasFinalizedThisWeek = true
        
        // Force a redraw so trophy rows reflect any changes
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
    }

    /// MARK: - Auto Reset Logic (Quotes/Sales WTD weekly on Sunday, Sales MTD monthly on 1st)
    func performAutoResetsIfNeeded(currentDate: Date = Date()) {
        // Align reset calendar with Chicago time so "Sunday" is consistent
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = resetTimeZone
        let weekId = currentWeekId(currentDate)
        let monthId = currentMonthId(currentDate)

        var didWeekly = false
        var didMonthly = false

        // Compute boundary components in reset timezone
        let weekday = cal.component(.weekday, from: currentDate) // 1 = Sunday (firstWeekday set to 1 elsewhere for week id)
        let day = cal.component(.day, from: currentDate)

        // Bootstrap missing IDs without resetting mid-period
        if lastWeeklyResetId == nil && weekday != 1 {
            print("🧭 [AutoReset] Bootstrap weekly id (no reset) — setting lastWeeklyResetId=\(weekId) on non-Sunday")
            lastWeeklyResetId = weekId
        }
        if lastMonthlyResetId == nil && day != 1 {
            print("🧭 [AutoReset] Bootstrap monthly id (no reset) — setting lastMonthlyResetId=\(monthId) on non-day-1")
            lastMonthlyResetId = monthId
        }

        // Recompute newness after bootstrap
        let isNewWeek = lastWeeklyResetId != weekId
        let isNewMonth = lastMonthlyResetId != monthId

        // 🏆 PRESERVE TROPHY DATA: Store current trophy states before any resets
        var trophyStates = preserveTrophyData()

        // 🏆 RESET FINALIZATION FLAG: Check if we're in a new week
        resetFinalizationFlagIfNewWeek(now: currentDate)

        // Boundary gates
        let isSunday = (weekday == 1)
        let isDayOne = (day == 1)

        // 🏆 FINALIZE TROPHIES BEFORE RESET: Only at true weekly boundary
        if isNewWeek && isSunday {
            let weekStartDate = cal.dateInterval(of: .weekOfYear, for: currentDate)?.start ?? currentDate
            finalizeCurrentWeekIfNeeded(now: weekStartDate)
            // Refresh preserved states so we keep the finalized streak values
            trophyStates = preserveTrophyData()
        }

        // WEEKLY: reset quotesToday & salesWTD once per new week, ONLY on Sunday
        if isNewWeek && isSunday {
            if teamMembers.isEmpty {
                if !pendingWeeklyReset {
                    print("⚠️ [AutoReset] Detected new week (\(weekId)) on Sunday but no members are loaded — deferring reset")
                }
                pendingWeeklyReset = true
            } else {
                for i in teamMembers.indices {
                    teamMembers[i].quotesToday = 0
                    teamMembers[i].salesWTD = 0
                    saveWinTheDayFields(teamMembers[i])
                }
                lastWeeklyResetId = weekId
                didWeekly = true
                pendingWeeklyReset = false
            }
        } else {
            // Do not carry a pending weekly reset outside the boundary window
            pendingWeeklyReset = false
        }

        // MONTHLY: reset salesMTD once per new month, ONLY on day 1
        if isNewMonth && isDayOne {
            if teamMembers.isEmpty {
                if !pendingMonthlyReset {
                    print("⚠️ [AutoReset] Detected new month (\(monthId)) on day 1 but no members are loaded — deferring reset")
                }
                pendingMonthlyReset = true
            } else {
                for i in teamMembers.indices {
                    teamMembers[i].salesMTD = 0
                    saveWinTheDayFields(teamMembers[i])
                }
                lastMonthlyResetId = monthId
                didMonthly = true
                pendingMonthlyReset = false
            }
        } else {
            // Do not carry a pending monthly reset outside the boundary window
            pendingMonthlyReset = false
        }

        if didWeekly || didMonthly {
            // 🏆 RESTORE TROPHY DATA: Ensure trophy states are preserved after resets
            restoreTrophyData(trophyStates)
            
            // Persist & refresh bindings/UI
            saveLocal()
            DispatchQueue.main.async { [weak self] in self?.objectWillChange.send() }
        }
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
                // Keep TeamMember emoji in sync with Card default
                if let cardEmoji = cards.first(where: { $0.name == name })?.emoji, !cardEmoji.isEmpty {
                    member.emoji = cardEmoji
                }
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
        teamMembers = sanitizeMembersArray(teamMembers)
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

    /// Pre-fetch so WinTheDayView can render instantly (call from Splash/App launch).
    /// Safe to call multiple times.
    func prewarm(userList: [String], currentUser: String) {
        // 🏆 PRESERVE TROPHY DATA: Store current trophy states before prewarm operations
        let trophyStates = preserveTrophyData()
        
        // Run auto-resets first so saved/fetched data reflects the new period.
        performAutoResetsIfNeeded(currentDate: Date())

        // Fetch labels + members, then ensure cards/order locally, then mark warm.
        fetchGoalNamesFromCloud()
        fetchMembersFromCloud { [weak self] in
            guard let self = self else { return }
            self.ensureCardsForAllUsers(userList)
            self.loadCardOrderFromCloud(for: currentUser)
            
            // 🏆 RESTORE TROPHY DATA: Ensure trophy states are preserved after prewarm
            self.restoreTrophyData(trophyStates)
            
            DispatchQueue.main.async { 
                self.isWarm = true
                // 🏆 RUN TROPHY LOGIC: Finalize trophies after data is loaded and warm
                print("🔥 [PREWARM] Data loaded and warm - running trophy finalization")
                // Note: finalizeCurrentWeekIfNeeded will be called from WinTheDayView.onAppear
            }
        }
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
