import SwiftUI

// MARK: - Model

struct Goal: Identifiable {
    let id = UUID()
    let title: String
    let percent: Int
}

struct Person: Identifiable {
    let id = UUID()
    let name: String
    let emoji: String
    let achieved: Int
    let goals: [Goal]
}

// MARK: - Mock Data

let mockPeople: [Person] = [
    Person(name: "Ron", emoji: "🧔🏻", achieved: 0, goals: [
        Goal(title: "Auto 115", percent: 0),
        Goal(title: "Fire 65", percent: 0),
        Goal(title: "Life 20", percent: 0)
    ]),
    Person(name: "Deanna", emoji: "👩🏽‍💼", achieved: 27, goals: [
        Goal(title: "Auto 75", percent: 48),
        Goal(title: "Fire 60", percent: 20),
        Goal(title: "Life 25", percent: 24),
        Goal(title: "License x2", percent: 50),
        Goal(title: "Workout", percent: 17)
    ]),
    Person(name: "D.J.", emoji: "👨🏽‍💼", achieved: 18, goals: [
        Goal(title: "Auto +75", percent: 18),
        Goal(title: "Fire +75", percent: 40),
        Goal(title: "Life Issued", percent: 8),
        Goal(title: "Appointments", percent: 4)
    ]),
    Person(name: "Dimitri", emoji: "🧔🏽", achieved: 25, goals: [
        Goal(title: "Life Issued 75", percent: 77),
        Goal(title: "Health Issued 3", percent: 0),
        Goal(title: "Google 12", percent: 42),
        Goal(title: "Lose 15 lbs", percent: 33)
    ])
]

// MARK: - Tile View

struct PersonTileView: View {
    let person: Person
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("\(person.emoji) \(person.name)")
                    .font(.headline)
                Spacer()
                Text("\(person.achieved)% Achieved")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Goals
            ForEach(person.goals) { goal in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(goal.title)
                        Spacer()
                        Text("\(goal.percent)%")
                            .foregroundColor(.secondary)
                    }
                    ProgressView(value: Float(goal.percent), total: 100)
                        .tint(progressColor(for: goal.percent))
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemBackground)).shadow(radius: 2))
    }
    
    func progressColor(for percent: Int) -> Color {
        if percent == 0 {
            return .gray
        } else if percent < 50 {
            return .yellow
        } else {
            return .green
        }
    }
}

// MARK: - Sandbox Preview

struct GoalTilePreview: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(mockPeople) { person in
                    PersonTileView(person: person)
                        .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .background(Color(.secondarySystemBackground).ignoresSafeArea())
    }
}

struct GoalTilePreview_Previews: PreviewProvider {
    static var previews: some View {
        GoalTilePreview()
    }
}

