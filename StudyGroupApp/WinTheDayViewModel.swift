import Foundation
import CloudKit
import SwiftUI

class WinTheDayViewModel: ObservableObject {
    @Published var teamData: [TeamMember] = []

    init() {
        self.teamMembers = []
    }
    @Published var teamMembers: [TeamMember] = []
    @Published var displayedMembers: [TeamMember] = []
    @Published var cards: [Card] = []
    @Published var displayedCards: [Card] = []
    @Published var selectedUserName: String = ""
    private let storageKey = "WTDMemberStorage"
    private var hasLoadedDisplayOrder = false

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

    private func updateLocalEntries(names: [String]) {
        teamMembers.removeAll { !names.contains($0.name) }
        let stored = loadLocalMembers()
        for name in names where !teamMembers.contains(where: { $0.name == name }) {
            if let saved = stored.first(where: { $0.name == name }) {
                teamMembers.append(saved)
            } else {
                teamMembers.append(TeamMember(name: name))
            }
        }
        for (index, _) in teamMembers.enumerated() {
            teamMembers[index].sortIndex = index
        }
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

            for (index, name) in names.enumerated() {
                if let m = members.first(where: { $0.name == name }) {
                    if index < self.teamMembers.count {
                        self.teamMembers[index] = m
                        self.teamMembers[index].sortIndex = index
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
            CloudKitManager.shared.save(teamMembers[index]) { _ in }
        }
        displayedMembers = teamMembers
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
