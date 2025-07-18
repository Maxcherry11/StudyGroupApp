struct Week: Identifiable {
    let id = UUID()
    let number: Int
    var isComplete: Bool
}

struct Goal {
    let title: String
    var weeks: [Week]
    
    var percentComplete: Int {
        let completed = weeks.filter { $0.isComplete }.count
        return Int(Double(completed) / Double(weeks.count) * 100)
    }
}

import SwiftUI

struct ContentView: View {
    @State private var goal = Goal(
        title: "Call 100 clients",
        weeks: (1...12).map { Week(number: $0, isComplete: false) }
    )
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Text(goal.title)
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Progress: \(goal.percentComplete)%")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                    ForEach(goal.weeks.indices, id: \.self) { i in
                        Button(action: {
                            withAnimation {
                                goal.weeks[i].isComplete.toggle()
                            }
                        }) {
                            Text("W\(goal.weeks[i].number)")
                                .fontWeight(.medium)
                                .frame(width: 60, height: 60)
                                .background(goal.weeks[i].isComplete ? Color.green : Color.gray.opacity(0.2))
                                .foregroundColor(goal.weeks[i].isComplete ? .white : .primary)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .strokeBorder(goal.weeks[i].isComplete ? Color.green : Color.gray, lineWidth: 2)
                                )
                        }
                    }
                }
                .padding(.top, 20)
                
                Spacer()
            }
            .padding()
            .navigationTitle("12-Week Year")
        }
    }
}
