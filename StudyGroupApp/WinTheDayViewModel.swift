import Foundation
import CloudKit

class WinTheDayViewModel: ObservableObject {
    @Published var teamData: [TeamMember] = []

    init() {
        self.teamMembers = []
    }
    @Published var teamMembers: [TeamMember] = []
    @Published var displayedCards: [TeamMember] = []
    @Published var selectedUserName: String = ""
    private let storageKey = "WTDMemberStorage"

    /// Initializes ``displayedCards`` only once using the current
    /// `teamMembers` order. This is used when the view first loads or
    /// when navigating back from the splash screen so that card order
    /// remains stable.
    func initializeDisplayedCardsIfNeeded() {
        if displayedCards.isEmpty {
            displayedCards = teamMembers.sorted { $0.sortIndex < $1.sortIndex }
        }
    }

    /// Reorders ``displayedCards`` after a user saves edits. The reordering is
    /// based on the current production metrics and mirrors `reorderCards()`
    /// without being triggered on every appearance.
    func reorderAfterSave() {
        reorderCards()
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
        displayedCards = teamMembers
    }

    func loadCardOrderFromCloud(for user: String) {
        CloudKitManager.shared.fetchCardOrder(for: user) { [weak self] savedOrder in
            guard let self = self else { return }
            if let savedOrder = savedOrder {
                let ordered = savedOrder.compactMap { idString in
                    self.teamMembers.first { $0.id.uuidString == idString }
                }
                self.displayedCards = ordered
            } else {
                let sorted = self.teamMembers.sorted {
                    ($0.quotesToday + $0.salesWTD + $0.salesMTD) >
                    ($1.quotesToday + $1.salesWTD + $1.salesMTD)
                }
                self.displayedCards = sorted
            }
        }
    }

    func saveCardOrderToCloud(for user: String) {
        let order = displayedCards.map { $0.id.uuidString }
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
