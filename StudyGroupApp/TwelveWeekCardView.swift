import SwiftUI

struct CardView: View {
    @Binding var member: TwelveWeekMember
    @State private var editingGoal: GoalProgress?
    @State private var isEditingGoals = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Text(member.name)
                .font(.system(size: 40, weight: .heavy))
                .foregroundColor(.white)
                .padding(.top, 150)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                ForEach(member.goals.indices, id: \.self) { index in
                    let goal = member.goals[index]
                    let color = goalColor(for: goal.percent)

                    ZStack(alignment: .topTrailing) {
                        VStack {
                            Spacer()
                            Text(goal.title)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                            Spacer().frame(height: 16)
                            CircleProgressView(progress: goal.percent, color: color)
                                .frame(width: 70, height: 70)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, minHeight: 140)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 20).fill(Color.white.opacity(0.05)))
                        .shadow(radius: 3)
                        .onTapGesture {
                            if !isEditingGoals {
                                editingGoal = goal
                            }
                        }

                        if isEditingGoals {
                            Button(action: {
                                member.goals.remove(at: index)
                            }) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                                    .background(Color.white)
                                    .clipShape(Circle())
                            }
                            .offset(x: 10, y: -10)
                        }
                    }
                }
                if isEditingGoals {
                    Button(action: {
                        let newGoal = GoalProgress(title: "New Goal", percent: 0)
                        member.goals.append(newGoal)
                    }) {
                        VStack(spacing: 10) {
                            Image(systemName: "plus")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(.white)
                            Text("Add Goal")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .frame(maxWidth: .infinity, minHeight: 140)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 20).fill(Color.white.opacity(0.1)))
                        .shadow(radius: 3)
                    }
                }
            }
            Spacer()
        }
        .padding()
        .background(Color(red: 60/255, green: 90/255, blue: 140/255))
        .ignoresSafeArea()
        .sheet(isPresented: Binding(get: {
            editingGoal != nil
        }, set: { value in
            if !value { editingGoal = nil }
        })) {
            GoalEditListView(goals: $member.goals)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    isEditingGoals.toggle()
                }) {
                    Text(isEditingGoals ? "Save" : "Add Goal")
                        .font(.headline)
                        .foregroundColor(.white)
                }
            }
        }
    }
}

struct CircleProgressView: View {
    var progress: Double
    var color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: 10)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(progress * 100))%")
                .font(.caption2)
                .foregroundColor(.white)
        }
    }
}

struct GoalEditView: View {
    @Binding var goal: GoalProgress

    var body: some View {
        NavigationView {
            Form {
                TextField("Title", text: $goal.title)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.4)))
                Slider(value: $goal.percent, in: 0...1)
            }
            .navigationTitle("Edit Goal")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct GoalEditListView: View {
    @Binding var goals: [GoalProgress]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                ForEach($goals.indices, id: \.self) { index in
                    Section(header: Text(goals[index].title).foregroundColor(.gray)) {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("Title", text: $goals[index].title)
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.4)))

                            HStack {
                                Slider(value: $goals[index].percent, in: 0...1)
                                Text("\(Int(goals[index].percent * 100))%")
                                    .foregroundColor(.gray)
                                    .font(.subheadline)
                                    .frame(minWidth: 40, idealWidth: 50, maxWidth: 60, alignment: .trailing)
                            }
                            .frame(height: 40)
                        }
                    }
                }
            }
            .navigationTitle("Edit All Goals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        dismiss()
                    }) {
                        Label("Back", systemImage: "chevron.left")
                            .labelStyle(.titleOnly)
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }
}

private func goalColor(for progress: Double) -> Color {
    let target = onTimeTargetProgress()

    switch progress {
    case 0..<target * 0.5:
        return .red
    case target * 0.5..<target * 0.75:
        return .orange
    case target * 0.75..<target:
        return .yellow
    default:
        return .green
    }
}

private func onTimeTargetProgress() -> Double {
    let calendar = Calendar.current
    let now = Date()

    guard let quarter = calendar.dateInterval(of: .quarter, for: now) else {
        return 1.0
    }

    let totalSeconds = quarter.end.timeIntervalSince(quarter.start)
    let elapsedSeconds = now.timeIntervalSince(quarter.start)
    let percentElapsed = elapsedSeconds / totalSeconds

    return percentElapsed
}

struct TwelveWeekCardView_Previews: PreviewProvider {
    struct PreviewWrapper: View {
        @State private var sample = TwelveWeekMember(
            name: "Demo",
            goals: [
                GoalProgress(title: "Auto", percent: 0.5),
                GoalProgress(title: "Fire", percent: 0.6),
                GoalProgress(title: "Life", percent: 0.4),
                GoalProgress(title: "Training", percent: 0.7)
            ]
        )

        var body: some View {
            CardView(member: $sample)
                .preferredColorScheme(.dark)
                .padding()
        }
    }

    static var previews: some View {
        PreviewWrapper()
    }
}
