import Foundation

class UserManager: ObservableObject {
    static let shared = UserManager()

    // Primary properties used throughout the app
    @Published var userList: [String] = [] {
        didSet {
            if allUsers != userList { allUsers = userList }
            UserDefaults.standard.set(userList, forKey: userDefaultsKey)
            if hasCompletedInitialLoad {
                let reason = isUpdatingFromCloud ? "cloudKitRefresh" : "localEdit"
                postUserListDidUpdateIfNeeded(userList, reason: reason)
            }
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
    private var hasCompletedInitialLoad = false
    private var lastPostedUserSet: Set<String> = []
    private var isUpdatingFromCloud = false

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

    private func normalizeNames(_ names: [String]) -> [String] {
        let cleaned = names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(Set(cleaned)).sorted()
    }

    private func postUserListDidUpdateIfNeeded(_ names: [String], reason: String?) {
        let normalized = normalizeNames(names)
        let normalizedSet = Set(normalized)
        if lastPostedUserSet == normalizedSet { return }
        lastPostedUserSet = normalizedSet
        var userInfo: [String: Any] = ["names": normalized]
        if let reason = reason {
            userInfo["reason"] = reason
        }
        NotificationCenter.default.post(
            name: .userListDidUpdate,
            object: nil,
            userInfo: userInfo
        )
    }

    func addUser(_ name: String) {
        guard !userList.contains(name) else { return }
        CloudKitManager.saveUser(name) { [weak self] in
            // Create a default Win the Day card so the record type exists
            let defaultCard = Card(
                id: "card-\(name)",
                name: name,
                emoji: "\u{2728}",
                production: 0,
                orderIndex: 0
            )
            CloudKitManager.saveCard(defaultCard)
            let twy = TwelveWeekMember(name: name, goals: [])
            CloudKitManager.saveTwelveWeekMember(twy) { _ in }
            
            // Note: TeamMember objects are created by WinTheDayViewModel.ensureCardsForAllUsers
            // to ensure they inherit proper goal values from existing team members
            
            self?.fetchUsersFromCloud()
        }
    }

    func deleteUser(_ name: String, completion: (() -> Void)? = nil) {
        print("🧨 [DELETE] UserManager forwarding unified delete for \(name)")
        CloudKitManager.shared.deleteUserEverywhere(name: name) { [weak self] _ in
            guard let self else {
                completion?()
                return
            }
            if self.currentUser == name {
                self.currentUser = ""
            }
            self.fetchUsersFromCloud()
            completion?()
        }
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
                let sorted = names
                let isInitialLoad = !self.hasCompletedInitialLoad
                self.isUpdatingFromCloud = true
                if sorted != self.userList {
                    self.userList = sorted
                    self.allUsers = sorted
                    self.saveUsers()
                }
                self.isUpdatingFromCloud = false
                if !sorted.contains(self.currentUser) {
                    self.currentUser = sorted.first ?? ""
                }
                if isInitialLoad {
                    self.hasCompletedInitialLoad = true
                }
                let reason = isInitialLoad ? "initialLoad" : "cloudKitRefresh"
                self.postUserListDidUpdateIfNeeded(sorted, reason: reason)
            }
        }
    }
}

extension Notification.Name {
    static let userListDidUpdate = Notification.Name("UserListDidUpdate")
}
