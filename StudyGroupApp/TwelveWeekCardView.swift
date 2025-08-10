import SwiftUI

struct CardView: View {
    @Binding var member: TwelveWeekMember
    @Binding var isInteracting: Bool
    let resetInteraction: () -> Void
    @State private var editingGoal: GoalProgress?
    @State private var isEditingGoals = false
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: TwelveWeekYearViewModel
    @ObservedObject private var userManager = UserManager.shared

    var body: some View {
        let isCurrent = member.name == userManager.currentUser
        NavigationView {
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
                                if !isEditingGoals && isCurrent {
                                    editingGoal = goal
                                }
                            }

                            if isEditingGoals && isCurrent {
                                Button(action: {
                                    member.goals.remove(at: index)
                                    isInteracting = true
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
                    if isEditingGoals && isCurrent {
                        Button(action: {
                            let newGoal = GoalProgress(title: "New Goal", percent: 0)
                            member.goals.append(newGoal)
                            isInteracting = true
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
                editingGoal != nil && isCurrent
            }, set: { value in
                if !value { 
                    editingGoal = nil
                    resetInteraction()
                }
            })) {
                GoalEditListView(member: $member, isInteracting: Binding(
                    get: { isInteracting },
                    set: { isInteracting = $0 }
                ), resetInteraction: resetInteraction)
                    .environmentObject(viewModel)
            }
            .onDisappear {
                resetInteraction()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isCurrent {
                        Button(action: {
                            if isEditingGoals {
                                resetInteraction()
                            }
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
    @Binding var member: TwelveWeekMember
    @EnvironmentObject private var viewModel: TwelveWeekYearViewModel
    @Environment(\.dismiss) private var dismiss
    @Binding var isInteracting: Bool
    let resetInteraction: () -> Void

    var body: some View {
        NavigationView {
            Form {
                ForEach(member.goals.indices, id: \.self) { index in
                    GoalRowEditor(
                        goal: $member.goals[index],
                        isInteracting: $isInteracting,
                        resetInteraction: resetInteraction
                    )
                }
            }
            .navigationTitle("Edit All Goals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        viewModel.saveMember(member)
                        resetInteraction()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        resetInteraction()
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

private struct GoalRowEditor: View {
    @Binding var goal: GoalProgress
    @Binding var isInteracting: Bool
    let resetInteraction: () -> Void

    var body: some View {
        Section(header: Text(goal.title).foregroundColor(.gray)) {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Title", text: $goal.title)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.4))
                    )
                    .onTapGesture { isInteracting = true }
                    .onChange(of: goal.title) { _ in isInteracting = true }

                HStack {
                    Slider(value: $goal.percent, in: 0...1)
                        .onTapGesture { isInteracting = true }
                        .gesture(
                            DragGesture()
                                .onChanged { _ in isInteracting = true }
                                .onEnded { _ in
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                        resetInteraction()
                                    }
                                }
                        )
                    Text("\(Int(goal.percent * 100))%")
                        .foregroundColor(.gray)
                        .font(.subheadline)
                        .frame(minWidth: 40, idealWidth: 50, maxWidth: 60, alignment: .trailing)
                }
                .frame(height: 40)
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
                    CardView(member: $sample, isInteracting: .constant(false), resetInteraction: {})
            .environmentObject(TwelveWeekYearViewModel())
            .preferredColorScheme(.dark)
            .padding()
        }
    }

    static var previews: some View {
        PreviewWrapper()
    }
}
