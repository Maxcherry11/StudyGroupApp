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

    let users = ["D.J.", "Ron", "Deanna", "Dimitri"]

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Text("Who's Checking In?")
                    .font(.title)
                    .fontWeight(.bold)

                ForEach(users, id: \.self) { user in
                    Button(action: {
                        selectedUserName = user
                        print("👤 Selected: \(user)")
                        navigate = true
                    }) {
                        Text(user)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }

                NavigationLink(destination: MainTabView(), isActive: $navigate) {
                    EmptyView()
                }
                .hidden()
            }
            .padding()
        }
    }
}

#Preview {
    UserSelectorView()
}
