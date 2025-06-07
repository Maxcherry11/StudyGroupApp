import Foundation
import CloudKit

class UserManager: ObservableObject {
    static let shared = UserManager()

    @Published var allUsers: [String] = []
    @Published var currentUserName: String {
        didSet {
            UserDefaults.standard.set(currentUserName, forKey: "selectedUserName")
        }
    }

    private let cloudKit = CloudKitManager()
    private init() {
        self.currentUserName = UserDefaults.standard.string(forKey: "selectedUserName") ?? ""
        loadUsers()
    }

    func loadUsers() {
        cloudKit.fetchTeam { members in
            let names = members.map { $0.name }.sorted()
            DispatchQueue.main.async {
                self.allUsers = names
            }
        }
    }

    func selectUser(_ name: String) {
        currentUserName = name
    }

    func refresh() {
        loadUsers()
    }
}
