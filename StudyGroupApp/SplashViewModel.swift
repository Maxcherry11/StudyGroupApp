import Foundation
import CloudKit

class SplashViewModel: ObservableObject {
    @Published var users: [String] = []

    /// Fetch the user list from CloudKit and update ``users``.
    func fetchUsersFromCloud() {
        CloudKitManager.fetchUsers { fetched in
            DispatchQueue.main.async {
                print("✅ Cloud returned users: \(fetched)")
                self.users = fetched
            }
        }
    }

    /// Add a new user both locally and in CloudKit.
    func addUser(_ name: String) {
        CloudKitManager.saveUser(name) { [weak self] in
            self?.fetchUsersFromCloud()
        }
    }

    /// Delete a user from CloudKit and refresh the list.
    func deleteUser(_ name: String) {
        CloudKitManager.deleteUser(name)
        fetchUsersFromCloud()
    }
}
