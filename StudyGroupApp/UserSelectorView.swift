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
                                ForEach(userManager.userList, id: \.self) { user in
                                    Button(action: {
                                        userManager.selectUser(user)
                                        print("👤 Selected: \(user)")
                                        navigate = true
                                    }) {
                                        Text(user)
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
                            .alert("Add User", isPresented: $showAddUserAlert) {
                                TextField("Name", text: $newUserName)
                                Button("Add", action: {
                                    let trimmed = newUserName.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !trimmed.isEmpty, !userManager.userList.contains(trimmed) else { return }
                                    userManager.addUser(trimmed)
                                    CloudKitManager.shared.createScoreRecord(for: trimmed)
                                    let member = TeamMember(name: trimmed)
                                    CloudKitManager.shared.save(member) { _ in }
                                    newUserName = ""
                                })
                                Button("Cancel", role: .cancel) { }
                            }

                            NavigationLink(destination: MainTabView().environmentObject(userManager), isActive: $navigate) {
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
            .onAppear {
                userManager.refresh()
            }
        }
    }

    private func deleteUser(at offsets: IndexSet) {
        for index in offsets {
            let nameToDelete = userManager.userList[index]
            userManager.deleteUser(nameToDelete)
            CloudKitManager.shared.deleteScoreRecord(for: nameToDelete)
            CloudKitManager.shared.deleteByName(nameToDelete) { _ in }
        }
    }
}

#Preview {
    UserSelectorView()
}
