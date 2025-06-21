import CloudKit
import SwiftUI

@main
struct StudyGroupApp: App {
    @State private var isShowingLaunchScreen = true
    @StateObject private var userManager = UserManager.shared

    var body: some Scene {
        WindowGroup {
            ZStack {
                if isShowingLaunchScreen {
                    LaunchScreenView()
                        .transition(.opacity)
                } else {
                    SplashView()
                        .environmentObject(userManager)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: isShowingLaunchScreen)
            .onAppear {
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
