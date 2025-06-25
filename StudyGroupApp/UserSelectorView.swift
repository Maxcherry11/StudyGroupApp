//
//  UserSelectorView.swift
//  StudyGroupApp
//
//  Created by D.J. Jones on 5/24/25.
//

import SwiftUI
import CloudKit

struct UserSelectorView: View {
    @EnvironmentObject var userManager: UserManager
    /// Use the WinTheDayViewModel so the splash screen mirrors the main app data
    @StateObject private var viewModel = WinTheDayViewModel()
    @State private var navigate = false

    @State private var newUserName = ""
    @State private var showAddUserAlert = false

    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                GeometryReader { geometry in
                    VStack {
                        Spacer()
                        VStack(spacing: 24) {
                            Text("Who's Checking In?")
                                .font(.title)
                                .fontWeight(.bold)

                            List {
                                ForEach(viewModel.teamMembers, id: \.id) { member in
                                    Button(action: {
                                        // Set the active user and proceed into the app
                                        userManager.currentUser = member.name
                                        viewModel.selectedUserName = member.name
                                        print("👤 Selected: \(member.name)")
                                        navigate = true
                                    }) {
                                        Text(member.name)
                                            .font(.system(size: 26, weight: .bold))
                                            .foregroundColor(.white)
                                            .frame(maxWidth: .infinity)
                                            .padding()
                                            .padding(.vertical, 6)
                                            .background(Color.red)
                                            .cornerRadius(12)
                                    }
                                }
                                .onDelete(perform: deleteUser)

                                Button(action: {
                                    showAddUserAlert = true
                                }) {
                                    Label("Add New User", systemImage: "plus")
                                        .font(.system(size: 18, weight: .medium))
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(Color.blue.opacity(0.9))
                                        .foregroundColor(.white)
                                        .cornerRadius(10)
                                }
                                .padding(.top, 24)
                            }
                            .listStyle(PlainListStyle())
                            .refreshable {
                                userManager.refresh()
                                viewModel.fetchMembersFromCloud()
                            }
                            .alert("Add User", isPresented: $showAddUserAlert) {
                                TextField("Name", text: $newUserName)
                                Button("Add", action: {
                                    let trimmed = newUserName.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !trimmed.isEmpty, !userManager.userList.contains(trimmed) else { return }
                                    userManager.addUser(trimmed)
                                    // Use CloudKitManager's helper so the new member
                                    // inherits existing production goals.
                                    CloudKitManager.shared.addTeamMember(name: trimmed) { _ in
                                        viewModel.fetchMembersFromCloud()
                                    }
                                    newUserName = ""
                                })
                                Button("Cancel", role: .cancel) { }
                            }

                            NavigationLink(destination: MainTabView().environmentObject(userManager).environmentObject(viewModel), isActive: $navigate) {
                                EmptyView()
                            }
                            .hidden()
                        }
                        .padding()
                        Spacer()
                    }
                    .frame(height: geometry.size.height)
                }
            }
        }
    }

    private func deleteUser(at offsets: IndexSet) {
        for index in offsets {
            let member = viewModel.teamMembers[index]
            userManager.deleteUser(member.name)
            CloudKitManager.shared.deleteByName(member.name) { _ in
                viewModel.fetchMembersFromCloud()
            }
        }
    }
}

#Preview {
    UserSelectorView()
        .environmentObject(UserManager.shared)
}
