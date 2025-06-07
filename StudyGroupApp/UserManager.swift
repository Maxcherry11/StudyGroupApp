import Foundation

class UserManager: ObservableObject {
    static let shared = UserManager()

    @Published var allUsers: [String] = []
    @Published var currentUserName: String {
        didSet {
            UserDefaults.standard.set(currentUserName, forKey: "selectedUserName")
        }
    }

    private let userDefaultsKey = "allUsers"

    private init() {
        self.currentUserName = UserDefaults.standard.string(forKey: "selectedUserName") ?? ""
        if let stored = UserDefaults.standard.array(forKey: userDefaultsKey) as? [String] {
            self.allUsers = stored
        } else {
            self.allUsers = ["D.J.", "Ron", "Deanna", "Dimitri"]
            saveUsers()
        }
    }

    private func saveUsers() {
        UserDefaults.standard.set(allUsers, forKey: userDefaultsKey)
    }

    func addUser(_ name: String) {
        guard !allUsers.contains(name) else { return }
        allUsers.append(name)
        saveUsers()
    }

    func deleteUser(_ name: String) {
        allUsers.removeAll { $0 == name }
        saveUsers()
    }

    func selectUser(_ name: String) {
        currentUserName = name
    }

    func refresh() {
        allUsers = UserDefaults.standard.array(forKey: userDefaultsKey) as? [String] ?? []
    }
}
