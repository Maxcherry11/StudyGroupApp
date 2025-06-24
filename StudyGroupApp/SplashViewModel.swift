import Foundation
import CloudKit

class SplashViewModel: ObservableObject {
    /// Team members available for selection on the splash screen.
    @Published var teamMembers: [TeamMember] = []

    /// Fetches all members from CloudKit and updates ``teamMembers``.
    func fetchMembersFromCloud() {
        CloudKitManager.shared.fetchAllTeamMembers { fetched in
            DispatchQueue.main.async {
                self.teamMembers = fetched
            }
        }
    }

    /// Adds a new member by creating paired Win and Scoreboard records then refreshes ``teamMembers``.
    func addMember(name: String, emoji: String = "🙂") {
        CloudKitManager.shared.createTeamMemberRecords(for: name)
        fetchMembersFromCloud()
    }

    /// Deletes the provided member record and refreshes the list.
    func deleteMember(_ member: TeamMember) {
        CloudKitManager.shared.deleteTeamMember(member) { [weak self] _ in
            self?.fetchMembersFromCloud()
        }
    }
}
