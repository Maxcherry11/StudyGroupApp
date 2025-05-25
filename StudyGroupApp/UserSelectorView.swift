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

    let users = ["DJ", "Ron", "Deanna", "Dimitri"]

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Text("Who's Checking In?")
                    .font(.title)
                    .fontWeight(.bold)

                ForEach(users, id: \.self) { user in
                    Button(action: {
                        selectedUserName = user
                        navigate = true
                    }) {
                        Text(user)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue.opacity(0.8))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }

                NavigationLink(destination: WinTheDayView(viewModel: WinTheDayViewModel()), isActive: $navigate) {
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
