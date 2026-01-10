import CloudKit
import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        CloudKitManager.shared.ensureTeamMemberSubscription()
        return true
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        CloudKitManager.shared.handleRemoteNotification(userInfo) { handled in
            completionHandler(handled ? .newData : .noData)
        }
    }
}

@main
struct StudyGroupApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var isShowingLaunchScreen = true
    @StateObject private var userManager = UserManager.shared

    var body: some Scene {
        WindowGroup {
            ZStack {
                if isShowingLaunchScreen {
                    LaunchScreenView()
                        .transition(.opacity)
                } else {
                    UserSelectorView()
                        .environmentObject(userManager)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: isShowingLaunchScreen)
            .onAppear {
                CloudKitManager.shared.migrateTeamMemberFieldsIfNeeded()
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    withAnimation {
                        isShowingLaunchScreen = false
                    }
                }
            }
            .environmentObject(userManager)
        }
    }
}
