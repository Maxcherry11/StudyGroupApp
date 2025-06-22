import Foundation

class UserManager: ObservableObject {
    static let shared = UserManager()

    // Primary properties used throughout the app
    @Published var userList: [String] = [] {
        didSet {
            if allUsers != userList { allUsers = userList }
            UserDefaults.standard.set(userList, forKey: userDefaultsKey)
        }
    }
    @Published var currentUser: String = "" {
        didSet {
            if currentUserName != currentUser { currentUserName = currentUser }
            UserDefaults.standard.set(currentUser, forKey: "currentUser")
        }
    }

    // Backwards compatibility for existing views like LifeScoreboardView
    @Published var allUsers: [String] = [] {
        didSet {
            if userList != allUsers { userList = allUsers }
        }
    }
    @Published var currentUserName: String = "" {
        didSet {
            if currentUser != currentUserName { currentUser = currentUserName }
        }
    }

    private let userDefaultsKey = "allUsers"

    private init() {
        let storedUser = UserDefaults.standard.string(forKey: "currentUser") ?? ""
        self.currentUser = storedUser
        self.currentUserName = storedUser

        if let stored = UserDefaults.standard.array(forKey: userDefaultsKey) as? [String] {
            self.userList = stored
            self.allUsers = stored
        } else {
            let defaults = ["D.J.", "Ron", "Deanna", "Dimitri"]
            self.userList = defaults
            self.allUsers = defaults
            saveUsers()
        }

        fetchUsersFromCloud()
    }

    private func saveUsers() {
        UserDefaults.standard.set(userList, forKey: userDefaultsKey)
    }

    func addUser(_ name: String) {
        guard !userList.contains(name) else { return }
        CloudKitManager.saveUser(name) { [weak self] in
            // Create a default Win the Day card for the new user
            let defaultCard = CardModel(userName: name)
            CloudKitManager.shared.save(card: defaultCard)
            self?.fetchUsersFromCloud()
        }
    }

    func deleteUser(_ name: String) {
        CloudKitManager.deleteUser(name)
        if currentUser == name {
            currentUser = ""
        }
        fetchUsersFromCloud()
    }

    func selectUser(_ name: String) {
        currentUser = name
    }

    func refresh() {
        fetchUsersFromCloud()
    }

    func fetchUsersFromCloud() {
        CloudKitManager.fetchAllUserNames { names in
            DispatchQueue.main.async {
                print("📥 Received users from CloudKit: \(names)")
                self.userList = names
                self.allUsers = names
                self.saveUsers()
                if !names.contains(self.currentUser) {
                    self.currentUser = names.first ?? ""
                }
            }
        }
    }
}
