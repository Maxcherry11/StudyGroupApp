//
//  MainTabView.swift
//  Outcast
//
//  Created by D.J. Jones on 5/18/25.
//


import SwiftUI

struct MainTabView: View {
    init() {
        UITabBar.appearance().backgroundColor = UIColor.systemGray6
    }
    var body: some View {
        TabView {
            WinTheDayView(viewModel: WinTheDayViewModel())
                .tabItem {
                    Image(systemName: "checkmark.seal.fill")
                    Text("Win the Day")
                }

            LifeScoreboardView(viewModel: LifeScoreboardViewModel())
                .tabItem {
                    Image(systemName: "briefcase.fill")
                    Text("Scoreboard")
                }

            /*
            Week12View()
                .tabItem {
                    Image(systemName: "calendar")
                    Text("12 Week Year")
                }
            */
        }
    }
}

struct Week12View: View {
    var body: some View {
        Text("12 Week Year Placeholder")
            .font(.largeTitle)
            .padding()
    }
}
