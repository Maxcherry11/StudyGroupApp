import SwiftUI

struct LaunchScreenView: View {
    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0.0

    var body: some View {
        ZStack {
            Color(red: 237/255, green: 29/255, blue: 36/255)
                .ignoresSafeArea()

            Image("SplashLogo")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 200) // Added to control logo size
                .padding()
                .scaleEffect(scale)
                .opacity(opacity)
                .onAppear {
                    withAnimation(
                        Animation.easeInOut(duration: 2)
                    ) {
                        scale = 1.2
                        opacity = 1.0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        // This delay keeps the logo visible for 0.5 seconds after the animation
                        // You can trigger any next action here if needed
                    }
                }
        }
    }
}
