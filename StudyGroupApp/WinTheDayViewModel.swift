import Foundation
import CloudKit
import SwiftUI

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
    
    // Track which week has been finalized during the current app session
    private var sessionFinalizedWeekId: String?
    private var isProcessingAutoReset: Bool = false
    private let lastFinalizedWeekKey = "lastFinalizedWeekId"
    private let finalizationDefaultsVersionKey = "lastFinalizedWeekVersion"
    private let finalizationDefaultsVersion = 2

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
        migrateFinalizationTrackingIfNeeded()
        NotificationCenter.default.addObserver(
            forName: .cloudKitUserDeleted,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let name = note.userInfo?["name"] as? String else { return }
            self?.purgeLocalCaches(for: name)
        }
        NotificationCenter.default.addObserver(
            forName: .userListDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self = self else { return }
            let names = note.userInfo?["names"] as? [String] ?? UserManager.shared.userList
            let normalized = self.normalizeCardNames(names)
            let incomingSet = Set(normalized)
            if incomingSet.isEmpty {
                print("🧭 [CARDS] skip reason=emptySet count=0 names=[]")
                return
            }
            if incomingSet == self.lastRefreshedNameSet {
                print("🧭 [CARDS] skip reason=sameSet count=\(normalized.count) names=\(self.previewNames(normalized))")
                return
            }
            let now = Date()
            let elapsed = now.timeIntervalSince(self.lastRefreshTime)
            if elapsed < self.cardsRefreshCooldown {
                let remaining = (self.cardsRefreshCooldown - elapsed) + self.cardsRefreshDebounce
                self.pendingCardsRefreshWorkItem?.cancel()
                self.pendingCardsRefreshWorkItem = nil
                print("🧭 [CARDS] defer reason=cooldown remaining=\(String(format: "%.2fs", remaining)) count=\(normalized.count) names=\(self.previewNames(normalized))")
                let namesSnapshot = normalized
                let incomingSetSnapshot = incomingSet
                let workItem = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.lastRefreshTime = Date()
                    self.lastRefreshedNameSet = incomingSetSnapshot
                    self.requestCardsFetch(names: namesSnapshot, trigger: "userListDidUpdate", reason: "diffSet")
                }
                self.pendingCardsRefreshWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + remaining, execute: workItem)
                return
            }
            self.pendingCardsRefreshWorkItem?.cancel()
            self.pendingCardsRefreshWorkItem = nil
            self.lastRefreshTime = now
            self.lastRefreshedNameSet = incomingSet
            self.requestCardsFetch(names: normalized, trigger: "userListDidUpdate", reason: "diffSet")
        }
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
    private var lastRefreshedNameSet: Set<String> = []
    private var lastRefreshTime: Date = .distantPast
    private var pendingCardsRefreshWorkItem: DispatchWorkItem?
    private let cardsRefreshCooldown: TimeInterval = 1.0
    private let cardsRefreshDebounce: TimeInterval = 0.15
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
        
        let sorted = sortedMembersByScore()
        teamMembers = sorted
        displayedMembers = sorted
        lastFetchHash = computeHash(for: sorted)
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
        let names = UserManager.shared.userList
        Task { [weak self] in
            let records = await CardsFetchCoordinator.shared.requestFetch(names: names, reason: "fetchCardsFromCloud")
            await MainActor.run {
                guard let self else { return }
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
            
            CloudKitManager.shared.migrateTeamMemberFieldsIfNeeded()

            CloudKitManager.shared.fetchTeam { [weak self] fetched in
                guard let self = self else { return }
                let newHash = self.computeHash(for: fetched)
                let fetchedClean = self.sanitizeMembersArray(fetched)

                DispatchQueue.main.async {
                    var mergedSnapshot = self.teamMembers
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
                        mergedSnapshot = merged
                        self.saveLocalIfNonEmpty(mergedSnapshot)

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
                    } else {
                        print("ℹ️ User list is empty; skipping updateLocalEntries to avoid clearing cached members.")
                    }

                    self.lastGoalHash = Self.computeGoalHash(for: self.goalNames)
                    self.isLoaded = true
                    completion?()
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

    private func saveLocal(members: [TeamMember]) {
        // 🏆 SAFETY CHECK: Ensure we don't accidentally clear trophy data
        // Trophy data is stored separately and should not be affected by team member saves
        let cleaned = sanitizeMembersArray(members)
        let codable = cleaned.map { $0.codable }
        let names = cleaned.map { $0.name }.sorted()
        let preview = names.prefix(8).joined(separator: ", ")
        let suffix = names.count > 8 ? ", ..." : ""
        print("💾 Saving snapshotCount=\(cleaned.count) snapshotNames=[\(preview)\(suffix)] (trophy data preserved)")
        if let data = try? JSONEncoder().encode(codable) {
            UserDefaults.standard.set(data, forKey: storageKey)
            print("💾 Saved \(cleaned.count) team members to local storage: [\(preview)\(suffix)] (trophy data preserved)")
        }
    }

    private func saveLocal() {
        saveLocal(members: teamMembers)
    }

    private func normalizeCardNames(_ names: [String]) -> [String] {
        let cleaned = names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(Set(cleaned)).sorted()
    }

    private func previewNames(_ names: [String]) -> String {
        let preview = names.prefix(8).joined(separator: ", ")
        let suffix = names.count > 8 ? ", ..." : ""
        return "[\(preview)\(suffix)]"
    }

    private func requestCardsFetch(names: [String], trigger: String, reason: String) {
        let sorted = normalizeCardNames(names)
        print("🧭 [CARDS] trigger=\(trigger) reason=\(reason) count=\(sorted.count) names=\(previewNames(sorted))")
        Task { [weak self] in
            let cards = await CardsFetchCoordinator.shared.requestFetch(names: sorted, reason: "\(trigger):\(reason)")
            await MainActor.run {
                guard let self else { return }
                let membersSnapshot = self.teamMembers
                self.applyFetchedCards(cards, membersSnapshot: membersSnapshot)
            }
        }
    }

    private func applyFetchedCards(_ cards: [Card], membersSnapshot: [TeamMember]) {
        let cleanedCards = sanitizeCardsArray(cards)
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

        for m in membersSnapshot {
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

        var didChangeAnyCardEmoji = false
        for idx in self.cards.indices {
            if let member = membersSnapshot.first(where: { $0.name == self.cards[idx].name }) {
                if self.cards[idx].emoji != member.emoji {
                    self.cards[idx].emoji = member.emoji
                    didChangeAnyCardEmoji = true
                }
            }
        }
        if didChangeAnyCardEmoji {
            self.saveCardsToDevice()
            for card in self.cards { CloudKitManager.saveCard(card) }
        }
        self.saveLocal(members: membersSnapshot)

        let userList = UserManager.shared.userList
        let names = userList.isEmpty ? membersSnapshot.map { $0.name } : userList
        self.ensureCardsForAllUsers(names)
    }

    private func purgeLocalCaches(for name: String) {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filteredMembers = teamMembers.filter {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != key
        }
        if filteredMembers.count != teamMembers.count {
            print("🧹 Purging local team members for deleted user: \(name)")
            teamMembers = filteredMembers
            displayedMembers = filteredMembers
            teamData = filteredMembers
            saveLocal(members: filteredMembers)
        }

        if UserManager.shared.userList.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == key }) {
            let updated = UserManager.shared.userList.filter {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != key
            }
            UserManager.shared.userList = updated
            UserManager.shared.allUsers = updated
            if UserManager.shared.currentUser.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == key {
                UserManager.shared.currentUser = updated.first ?? ""
            }
            print("🧹 Purged UserManager list for deleted user: \(name)")
        }

        let filteredCards = cards.filter {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != key
        }
        if filteredCards.count != cards.count {
            print("🧹 Purging local cards for deleted user: \(name)")
            cards = filteredCards
            displayedCards = filteredCards
            saveCardsToDevice()
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
        logCloudKitIdentityAndScope(
            context: "saveWinTheDayFields()",
            container: CloudKitManager.container,
            dbScope: .public
        )
        let memberName = member.name
        let memberID = member.id
        
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
                        logCKError(error, context: "saveWinTheDayFields()")
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
    
    private var lastPersistedFinalizedWeekId: String? {
        get { UserDefaults.standard.string(forKey: lastFinalizedWeekKey) }
        set {
            let defaults = UserDefaults.standard
            if let newValue {
                defaults.set(newValue, forKey: lastFinalizedWeekKey)
            } else {
                defaults.removeObject(forKey: lastFinalizedWeekKey)
            }
        }
    }
    
    private func weekIdToFinalize(for date: Date) -> String? {
        adjustWeekId(currentWeekId(date), by: -1)
    }
    
    private func adjustWeekId(_ weekId: String, by offset: Int) -> String? {
        guard offset != 0 else { return weekId }
        guard let baseDate = date(forWeekId: weekId) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = resetTimeZone
        guard let adjusted = cal.date(byAdding: .weekOfYear, value: offset, to: baseDate) else { return nil }
        return currentWeekId(adjusted)
    }
    
    private func date(forWeekId weekId: String) -> Date? {
        let parts = weekId.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]) else { return nil }
        let weekPart = parts[1]
        guard weekPart.first == "W",
              let weekNumber = Int(weekPart.dropFirst()) else { return nil }
        
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = resetTimeZone
        cal.firstWeekday = 1
        cal.minimumDaysInFirstWeek = 1
        
        var components = DateComponents()
        components.yearForWeekOfYear = year
        components.weekOfYear = weekNumber
        components.weekday = cal.firstWeekday
        components.hour = 12
        
        return cal.date(from: components)
    }
    
    private func migrateFinalizationTrackingIfNeeded() {
        let defaults = UserDefaults.standard
        let storedVersion = defaults.integer(forKey: finalizationDefaultsVersionKey)
        guard storedVersion < finalizationDefaultsVersion else { return }
        
        if let storedWeekId = defaults.string(forKey: lastFinalizedWeekKey),
           let adjusted = adjustWeekId(storedWeekId, by: -1) {
            defaults.set(adjusted, forKey: lastFinalizedWeekKey)
        }
        
        defaults.set(finalizationDefaultsVersion, forKey: finalizationDefaultsVersionKey)
    }
    
    /// Resets the in-memory finalization guard when the target week changes.
    private func resetSessionFinalizationIfNeeded(now: Date = Date()) {
        guard let targetWeekId = weekIdToFinalize(for: now) else { return }
        if let finalizedWeek = sessionFinalizedWeekId, finalizedWeek == targetWeekId {
            return
        }
        if sessionFinalizedWeekId != nil {
            print("🏆 [FINALIZE] New week detected (\(targetWeekId)), resetting finalization flag")
        }
        sessionFinalizedWeekId = nil
    }
    
    /// Finalizes trophies for the prior week using CloudKit-backed streaks.
    func finalizeCurrentWeekIfNeeded(now: Date = Date()) async {
        guard let targetWeekId = weekIdToFinalize(for: now) else {
            print("🏆 [FINALIZE] No prior week available to finalize (date=\(now))")
            return
        }

        if sessionFinalizedWeekId == targetWeekId {
            print("🏆 [FINALIZE] Already finalized week \(targetWeekId) in this session, skipping")
            return
        }

        let previousWeekId = lastPersistedFinalizedWeekId ?? "nil"
        print("🏆 [FINALIZE] Starting finalizeCurrentWeekIfNeeded for week: \(targetWeekId)")
        print("🏆 [FINALIZE] Previously finalized week id: \(previousWeekId)")

        if let lastPersistedFinalizedWeekId, lastPersistedFinalizedWeekId == targetWeekId {
            print("🏆 [FINALIZE] Week \(targetWeekId) already finalized (persisted), skipping")
            sessionFinalizedWeekId = targetWeekId
            return
        }

        let membersSnapshot = teamMembers
        guard !membersSnapshot.isEmpty else {
            print("🏆 [FINALIZE] No team members loaded — deferring finalization")
            return
        }

        var didFinalizeAny = false
        var allSucceeded = true
        for member in membersSnapshot {
            let wasWeeklyMet = isWeeklyMet(for: member)
            print("🏆 [FINALIZE] Member \(member.name) - Weekly goals met: \(wasWeeklyMet)")

            if let record = await finalizeWeekInCloud(memberName: member.name,
                                                      weekId: targetWeekId,
                                                      didWin: wasWeeklyMet) {
                didFinalizeAny = true
                let newStreak = record["trophyStreakCount"] as? Int ?? (wasWeeklyMet ? member.trophyStreakCount + 1 : 0)
                let lastId = record["trophyLastFinalizedWeekId"] as? String ?? targetWeekId
                if let idx = teamMembers.firstIndex(where: { $0.id == member.id }) {
                    teamMembers[idx].trophyStreakCount = newStreak
                    teamMembers[idx].trophyLastFinalizedWeekId = lastId
                }
                print("🏆 [FINALIZE] Member \(member.name) - Cloud streak now \(newStreak) (last finalized: \(lastId))")
            } else {
                allSucceeded = false
                print("🏆 [FINALIZE] Member \(member.name) - Cloud update failed or skipped")
            }
        }

        if didFinalizeAny {
            if allSucceeded {
                sessionFinalizedWeekId = targetWeekId
                lastPersistedFinalizedWeekId = targetWeekId
            }
            objectWillChange.send()
        }
    }

    private func finalizeWeekInCloud(memberName: String,
                                     weekId: String,
                                     didWin: Bool) async -> CKRecord? {
        await withCheckedContinuation { continuation in
            CloudStreakManager.shared.finalizeWeek(for: memberName,
                                                   weekId: weekId,
                                                   didWin: didWin) { result in
                switch result {
                case .success(let record):
                    continuation.resume(returning: record)
                case .failure(let error):
                    print("❌ [FINALIZE] Cloud finalize failed for \(memberName): \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func appBecameActiveInCloud(for memberName: String) async -> CKRecord? {
        await withCheckedContinuation { continuation in
            CloudStreakManager.shared.appBecameActive(for: memberName) { result in
                switch result {
                case .success(let record):
                    continuation.resume(returning: record)
                case .failure(let error):
                    print("❌ [AutoReset] appBecameActive failed for \(memberName): \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func syncCloudResets(for memberNames: [String]) async -> [CKRecord] {
        var records: [CKRecord] = []
        for name in memberNames {
            if let record = await appBecameActiveInCloud(for: name) {
                records.append(record)
            }
        }
        return records
    }

    private func apply(resetRecords: [CKRecord], didWeekly: Bool, didMonthly: Bool) {
        guard !resetRecords.isEmpty else { return }
        for record in resetRecords {
            guard let name = record["name"] as? String,
                  let index = teamMembers.firstIndex(where: { $0.name == name }) else { continue }
            if let quotes = record["quotesToday"] as? Int {
                teamMembers[index].quotesToday = quotes
            }
            if let salesWTD = record["salesWTD"] as? Int {
                teamMembers[index].salesWTD = salesWTD
            }
            if let salesMTD = record["salesMTD"] as? Int {
                teamMembers[index].salesMTD = salesMTD
            }
            if let weekKey = record["weekKey"] as? String {
                teamMembers[index].weekKey = weekKey
            }
            if let monthKey = record["monthKey"] as? String {
                teamMembers[index].monthKey = monthKey
            }
            if let streak = record["trophyStreakCount"] as? Int {
                teamMembers[index].trophyStreakCount = streak
            }
            if let last = record["trophyLastFinalizedWeekId"] as? String {
                teamMembers[index].trophyLastFinalizedWeekId = last
            }
        }

        if didWeekly {
            for idx in teamMembers.indices {
                teamMembers[idx].quotesToday = 0
                teamMembers[idx].salesWTD = 0
            }
        }
        if didMonthly {
            for idx in teamMembers.indices {
                teamMembers[idx].salesMTD = 0
            }
        }
    }

    /// MARK: - Auto Reset Logic (Quotes/Sales WTD weekly on Sunday, Sales MTD monthly on 1st)
    func performAutoResetsIfNeeded(currentDate: Date = Date()) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = resetTimeZone
        let weekId = currentWeekId(currentDate)
        let monthId = currentMonthId(currentDate)

        let weekday = cal.component(.weekday, from: currentDate) // 1 = Sunday
        let day = cal.component(.day, from: currentDate)

        if lastWeeklyResetId == nil && weekday != 1 {
            print("🧭 [AutoReset] Bootstrap weekly id (no reset) — setting lastWeeklyResetId=\(weekId) on non-Sunday")
            lastWeeklyResetId = weekId
        }
        if lastMonthlyResetId == nil && day != 1 {
            print("🧭 [AutoReset] Bootstrap monthly id (no reset) — setting lastMonthlyResetId=\(monthId) on non-day-1")
            lastMonthlyResetId = monthId
        }

        let isNewWeek = lastWeeklyResetId != weekId
        let isNewMonth = lastMonthlyResetId != monthId

        resetSessionFinalizationIfNeeded(now: currentDate)

        let isSunday = (weekday == 1)
        let isDayOne = (day == 1)

        let needsWeeklyReset = isNewWeek && isSunday
        let needsMonthlyReset = isNewMonth && isDayOne
        let requiresNormalization: Bool = {
            guard !teamMembers.isEmpty else { return false }
            return teamMembers.contains {
                needsPeriodKeyNormalization(for: $0,
                                            currentWeekId: weekId,
                                            currentMonthId: monthId)
            }
        }()

        if !needsWeeklyReset {
            pendingWeeklyReset = false
        }
        if !needsMonthlyReset {
            pendingMonthlyReset = false
        }

        guard needsWeeklyReset || needsMonthlyReset || requiresNormalization else { return }

        guard !teamMembers.isEmpty else {
            if needsWeeklyReset && !pendingWeeklyReset {
                print("⚠️ [AutoReset] Detected new week (\(weekId)) but no members are loaded — deferring reset")
                pendingWeeklyReset = true
            }
            if needsMonthlyReset && !pendingMonthlyReset {
                print("⚠️ [AutoReset] Detected new month (\(monthId)) but no members are loaded — deferring reset")
                pendingMonthlyReset = true
            }
            return
        }

        if isProcessingAutoReset {
            print("⏳ [AutoReset] Reset already in progress, skipping concurrent request")
            return
        }

        isProcessingAutoReset = true
        let memberNames = teamMembers.map { $0.name }

        Task { @MainActor in
            defer { self.isProcessingAutoReset = false }

            if needsWeeklyReset || needsMonthlyReset {
                await self.finalizeCurrentWeekIfNeeded(now: currentDate)
            }

            var resetRecords: [CKRecord] = []
            if requiresNormalization && !needsWeeklyReset && !needsMonthlyReset {
                print("🧭 [AutoReset] Normalizing legacy week/month keys without triggering resets")
            }
            if needsWeeklyReset || needsMonthlyReset || requiresNormalization {
                resetRecords = await self.syncCloudResets(for: memberNames)
            }

            self.apply(resetRecords: resetRecords,
                       didWeekly: needsWeeklyReset,
                       didMonthly: needsMonthlyReset)

            if needsWeeklyReset {
                self.lastWeeklyResetId = weekId
                self.pendingWeeklyReset = false
            }
            if needsMonthlyReset {
                self.lastMonthlyResetId = monthId
                self.pendingMonthlyReset = false
            }

            self.saveLocal()
            self.objectWillChange.send()
            self.fetchMembersFromCloud()
        }
    }

    private func needsPeriodKeyNormalization(for member: TeamMember,
                                             currentWeekId: String,
                                             currentMonthId: String) -> Bool {
        if keyNeedsNormalization(rawKey: member.weekKey,
                                 expected: currentWeekId,
                                 normalize: normalizedWeekKey) {
            return true
        }
        if keyNeedsNormalization(rawKey: member.monthKey,
                                 expected: currentMonthId,
                                 normalize: normalizedMonthKey) {
            return true
        }
        return false
    }

    private func keyNeedsNormalization(rawKey: String?,
                                       expected: String,
                                       normalize: (String?) -> String?) -> Bool {
        guard let rawKey else { return true }
        guard let normalized = normalize(rawKey) else { return true }
        if normalized != expected {
            return false
        }
        return rawKey != normalized
    }

    private func normalizedWeekKey(_ key: String?) -> String? {
        guard let key, !key.isEmpty else { return nil }

        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if trimmed.contains("-") {
            let parts = trimmed.split(separator: "-")
            guard parts.count == 2,
                  let year = Int(parts[0]) else { return nil }
            var weekPart = parts[1]
            if weekPart.hasPrefix("W") {
                weekPart = weekPart.dropFirst()
            }
            guard let week = Int(weekPart),
                  (1...53).contains(week) else { return nil }
            return String(format: "%04d-W%02d", year, week)
        }

        let digits = trimmed.filter { $0.isNumber }
        guard digits.count >= 5 else { return nil }
        let yearDigits = digits.prefix(4)
        let weekDigits = digits.dropFirst(4)
        guard let year = Int(yearDigits),
              let week = Int(weekDigits),
              (1...53).contains(week) else { return nil }
        return String(format: "%04d-W%02d", year, week)
    }

    private func normalizedMonthKey(_ key: String?) -> String? {
        guard let key, !key.isEmpty else { return nil }

        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if trimmed.contains("-") {
            let parts = trimmed.split(separator: "-")
            guard parts.count == 2,
                  let year = Int(parts[0]) else { return nil }
            var monthPart = parts[1]
            if monthPart.hasPrefix("M") {
                monthPart = monthPart.dropFirst()
            }
            guard let month = Int(monthPart),
                  (1...12).contains(month) else { return nil }
            return String(format: "%04d-M%02d", year, month)
        }

        let digits = trimmed.filter { $0.isNumber }
        guard digits.count >= 5 else { return nil }
        let yearDigits = digits.prefix(4)
        let monthDigits = digits.dropFirst(4)
        guard let year = Int(yearDigits),
              let month = Int(monthDigits),
              (1...12).contains(month) else { return nil }
        return String(format: "%04d-M%02d", year, month)
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
    private func saveLocalIfNonEmpty(_ members: [TeamMember]) {
        guard !members.isEmpty else { return }
        saveLocal(members: members)
    }

    private func saveLocalIfNonEmpty() {
        saveLocalIfNonEmpty(teamMembers)
    }

    /// Pre-fetch so WinTheDayView can render instantly (call from Splash/App launch).
    /// Safe to call multiple times.
    func prewarm(userList: [String], currentUser: String) {
        // Run auto-resets first so saved/fetched data reflects the new period.
        performAutoResetsIfNeeded(currentDate: Date())

        // Fetch labels + members, then ensure cards/order locally, then mark warm.
        fetchGoalNamesFromCloud()
        fetchMembersFromCloud { [weak self] in
            guard let self = self else { return }
            self.ensureCardsForAllUsers(userList)
            self.loadCardOrderFromCloud(for: currentUser)
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
