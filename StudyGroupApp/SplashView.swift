import SwiftUI

struct SplashView: View {
    @EnvironmentObject var userManager: UserManager
    @StateObject private var viewModel = WinTheDayViewModel()
    @State private var navigate = false

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Text("Who's Checking In?")
                    .font(.title)

                ForEach(viewModel.teamMembers, id: \.name) { member in
                    Button(action: {
                        userManager.currentUser = member.name
                        viewModel.selectedUserName = member.name
                        navigate = true
                    }) {
                        Text(member.name)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                }

                Button(action: {
                    // Add new user logic here
                }) {
                    Label("Add New User", systemImage: "plus")
                        .padding()
                        .background(Color.white)
                        .foregroundColor(.blue)
                        .cornerRadius(10)
                }

                NavigationLink(destination: MainTabView()
                                .environmentObject(userManager)
                                .environmentObject(viewModel), isActive: $navigate) {
                    EmptyView()
                }
                .hidden()
            }
            .padding()
            .onAppear {
                viewModel.fetchMembersFromCloud()
            }
        }
    }
}

#Preview {
    SplashView()
        .environmentObject(UserManager.shared)
}
