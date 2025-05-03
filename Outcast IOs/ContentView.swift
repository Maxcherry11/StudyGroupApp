import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            WinTheDayView()  // This refers to the actual struct from WinTheDayView.swift
                .tabItem {
                    Label("Win the Day", systemImage: "checkmark.seal.fill")
                }

            LifeScoreboardView()  // Placeholder for now
                .tabItem {
                    Label("Life Scoreboard", systemImage: "briefcase.fill")
                }

            TwelveWeekYearView()  // Placeholder for now
                .tabItem {
                    Label("12 Week Year", systemImage: "calendar")
                }
        }
    }
}

// Placeholder screens for now
struct LifeScoreboardView: View {
    var body: some View {
        Text("Life Scoreboard Tracker Coming Soon!")
            .font(.largeTitle)
            .padding()
    }
}

struct TwelveWeekYearView: View {
    var body: some View {
        Text("12 Week Year Tracker Coming Soon!")
            .font(.largeTitle)
            .padding()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
