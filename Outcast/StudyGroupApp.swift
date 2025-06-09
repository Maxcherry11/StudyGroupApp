import CloudKit
import SwiftUI

@main
struct StudyGroupApp: App {
    init() {
        CKContainer(identifier: "iCloud.com.dj.Outcast").accountStatus { status, error in
            DispatchQueue.main.async {
                switch status {
                case .available:
                    print("✅ iCloud account is available.")
                case .noAccount:
                    print("❌ No iCloud account logged in.")
                case .restricted:
                    print("❌ iCloud account is restricted.")
                case .couldNotDetermine:
                    print("❌ Could not determine iCloud account status.")
                @unknown default:
                    print("❌ Unknown iCloud account status.")
                }
                if let error = error {
                    print("❌ Error checking iCloud account status: \(error.localizedDescription)")
                }
            }
        }
    }
    var body: some Scene {
        WindowGroup {
            UserSelectorView()
        }
    }
}
