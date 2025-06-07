//
//  UserSelectorView.swift
//  StudyGroupApp
//
//  Created by D.J. Jones on 5/24/25.
//

import SwiftUI
import CloudKit

struct UserSelectorView: View {
    @AppStorage("selectedUserName") private var selectedUserName: String = ""
    @State private var navigate = false

    @State private var users: [String] = []
    @State private var newUserName = ""
    @State private var showAddUserAlert = false

    var body: some View {
        NavigationView {
            ZStack {
                Color.white.ignoresSafeArea()

                GeometryReader { geometry in
                    VStack {
                        Spacer()
                        VStack(spacing: 24) {
                            Text("Who's Checking In?")
                                .font(.title)
                                .fontWeight(.bold)

                            List {
                                ForEach(users, id: \.self) { user in
                                    Button(action: {
                                        selectedUserName = user
                                        UserManager.shared.selectUser(user)
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
                                    guard !trimmed.isEmpty, !users.contains(trimmed) else { return }
                                    users.append(trimmed)

                                    CloudKitManager().fetchTeam { members in
                                        let base = members.first
                                        let newMember = TeamMember(
                                            name: trimmed,
                                            quotesToday: 0,
                                            salesWTD: 0,
                                            salesMTD: 0,
                                            quotesGoal: base?.quotesGoal ?? 10,
                                            salesWTDGoal: base?.salesWTDGoal ?? 2,
                                            salesMTDGoal: base?.salesMTDGoal ?? 6,
                                            emoji: base?.emoji ?? "🙂",
                                            sortIndex: (members.map { $0.sortIndex }.max() ?? -1) + 1
                                        )
                                        CloudKitManager().save(newMember) { _ in
                                            print("✅ Saved new TeamMember to CloudKit: \(trimmed)")
                                            UserManager.shared.refresh()
                                        }
                                    }

                                    newUserName = ""
                                })
                                Button("Cancel", role: .cancel) { }
                            }

                            NavigationLink(destination: MainTabView(), isActive: $navigate) {
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
                let predicate = NSPredicate(value: true)
                let query = CKQuery(recordType: "TeamMember", predicate: predicate)
                let operation = CKQueryOperation(query: query)

                var loadedNames: [String] = []

                operation.recordMatchedBlock = { _, result in
                    if case .success(let record) = result,
                       let name = record["name"] as? String {
                        loadedNames.append(name)
                    }
                }

                operation.queryResultBlock = { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success:
                            users = loadedNames.sorted()
                            UserManager.shared.refresh()
                            print("✅ Loaded names from CloudKit: \(users)")
                        case .failure(let error):
                            print("❌ Failed to load names: \(error.localizedDescription)")
                        }
                    }
                }

                CKContainer(identifier: "iCloud.com.dj.Outcast").publicCloudDatabase.add(operation)
            }
        }
    }

    private func deleteUser(at offsets: IndexSet) {
        for index in offsets {
            let nameToDelete = users[index]
            users.remove(at: index)

            CloudKitManager().deleteByName(nameToDelete) { success in
                if success {
                    print("🗑️ Deleted \(nameToDelete) from CloudKit")
                } else {
                    print("⚠️ Failed to delete \(nameToDelete) from CloudKit")
                }
            }
        }

        // Reload names from CloudKit to reflect changes
        let predicate = NSPredicate(value: true)
        let query = CKQuery(recordType: "TeamMember", predicate: predicate)
        let operation = CKQueryOperation(query: query)

        var loadedNames: [String] = []

        operation.recordMatchedBlock = { _, result in
            if case .success(let record) = result,
               let name = record["name"] as? String {
                loadedNames.append(name)
            }
        }

        operation.queryResultBlock = { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    users = loadedNames.sorted()
                    UserManager.shared.refresh()
                    print("✅ Reloaded names after delete: \(users)")
                case .failure(let error):
                    print("❌ Failed to reload names: \(error.localizedDescription)")
                }
            }
        }

        CKContainer(identifier: "iCloud.com.dj.Outcast").publicCloudDatabase.add(operation)
    }
}

#Preview {
    UserSelectorView()
}
