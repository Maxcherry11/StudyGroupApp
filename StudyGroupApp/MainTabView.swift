//
//  MainTabView.swift
//  Outcast
//
//  Created by D.J. Jones on 5/18/25.
//


import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var userManager: UserManager
    /// Shared WinTheDayViewModel passed from the splash screen so card state
    /// persists when entering the main tabs.
    @EnvironmentObject var viewModel: WinTheDayViewModel
    @StateObject private var scoreboardVM = LifeScoreboardViewModel()
    @StateObject private var twyVM = TwelveWeekYearViewModel()
    @Environment(\.scenePhase) private var scenePhase
    init() {
        UITabBar.appearance().backgroundColor = UIColor.systemGray6
    }
    var body: some View {
        TabView {
            WinTheDayView(viewModel: viewModel)
                .tabItem {
                    Image(systemName: "checkmark.seal.fill")
                    Text("Win the Day")
                }

            LifeScoreboardView(viewModel: scoreboardVM)
                .tabItem {
                    Image(systemName: "briefcase.fill")
                    Text("Scoreboard")
                }

            TwelveWeekYearView(viewModel: twyVM)
                .tabItem {
                    Label("12 Week Year", systemImage: "calendar")
                }
        }
        .onAppear {
            viewModel.fetchMembersFromCloud()
            scoreboardVM.fetchTeamMembersFromCloud()
            twyVM.fetchMembersFromCloud()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                viewModel.fetchMembersFromCloud()
                scoreboardVM.fetchTeamMembersFromCloud()
                twyVM.fetchMembersFromCloud()
            }
        }
    }
}
