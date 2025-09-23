//
//  MainTabView.swift
//  Outcast
//
//  Created by D.J. Jones on 5/18/25.
//

import SwiftUI
import UIKit

struct MainTabView: View {
    @EnvironmentObject var userManager: UserManager
    /// Use the shared WinTheDayViewModel to preserve trophy data across navigation
    @StateObject private var viewModel = WinTheDayViewModel.shared
    @StateObject private var scoreboardVM = LifeScoreboardViewModel()
    @StateObject private var twyVM = TwelveWeekYearViewModel()
    @Environment(\.scenePhase) private var scenePhase
    init() {
        // Translucent, blurred tab bar and navigation bar with no black flash when switching
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithDefaultBackground()
        tabAppearance.backgroundEffect = UIBlurEffect(style: .systemThinMaterial)
        tabAppearance.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.6)

        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
        UITabBar.appearance().isTranslucent = true

        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithDefaultBackground()
        navAppearance.backgroundEffect = UIBlurEffect(style: .systemThinMaterial)
        navAppearance.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.6)

        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
        UINavigationBar.appearance().isTranslucent = true
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
            // Skip WinTheDay fetch if already warm (data was prewarmed from UserSelectorView)
            if !viewModel.isWarm {
                viewModel.fetchMembersFromCloud()
            } else {
                print("🚀 [MainTabView] onAppear - WinTheDay already warm, skipping fetch")
            }
            scoreboardVM.fetchTeamMembersFromCloud()
            twyVM.fetchMembersFromCloud()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                // Skip WinTheDay fetch if already warm
                if !viewModel.isWarm {
                    viewModel.fetchMembersFromCloud()
                } else {
                    print("🚀 [MainTabView] onChange scenePhase - WinTheDay already warm, skipping fetch")
                }
                scoreboardVM.fetchTeamMembersFromCloud()
                twyVM.fetchMembersFromCloud()
            }
        }
    }
}

