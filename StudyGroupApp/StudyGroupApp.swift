import CloudKit
import SwiftUI

@main
struct StudyGroupApp: App {
    @State private var isShowingLaunchScreen = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                if isShowingLaunchScreen {
                    LaunchScreenView()
                        .transition(.opacity)
                } else {
                    UserSelectorView()
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
        }
    }
}
