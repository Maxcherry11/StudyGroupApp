import SwiftUI

struct ScoreboardEditorOverlay: View {
    @State var entry: LifeScoreboardViewModel.ScoreEntry
    @ObservedObject var row: LifeScoreboardViewModel.ActivityRow
    @EnvironmentObject var viewModel: LifeScoreboardViewModel
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(entry.name)
                .font(.headline)

            VStack(spacing: 16) {
                IntStepperRow(label: "Score", value: $entry.score)
                    .frame(maxWidth: .infinity)
                IntStepperRow(label: "Pending Apps", value: $row.pending)
                    .frame(maxWidth: .infinity)

                HStack {
                    Text("Projected Premium")
                    Spacer()
                    TextField("0", value: $row.projected, format: .currency(code: "USD"))
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                        .padding(6)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(6)
                        .frame(width: 100)
                }
                .frame(maxWidth: .infinity)
            }

            HStack {
                Button("Cancel") { onDismiss() }
                Spacer()
                Button("Save") {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    viewModel.save(entry, pending: row.pending, projected: row.projected)
                    onDismiss()
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .systemBackground))
        .cornerRadius(12)
        .shadow(radius: 8)
        .padding(.horizontal)
    }
}

private struct IntStepperRow: View {
    let label: String
    @Binding var value: Int

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(value)")
                .monospacedDigit()
                .frame(width: 30, alignment: .trailing)
            Stepper("", value: $value, in: 0...1000)
                .labelsHidden()
        }
        .frame(maxWidth: .infinity)
    }
}

struct LifeScoreboardView: View {
    @StateObject var viewModel = LifeScoreboardViewModel()
    @ObservedObject var userManager = UserManager.shared
    @State private var selectedEntry: LifeScoreboardViewModel.ScoreEntry?
    @State private var selectedRow: LifeScoreboardViewModel.ActivityRow?

    private func yearLabel() -> String {
        let month = Calendar.current.component(.month, from: Date())
        switch month {
        case 1...3:
            return "First Year"
        case 4...6:
            return "Second Year"
        case 7...9:
            return "Third Year"
        default:
            return "Fourth Year"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .center, spacing: 24) {
                
                // Header
                VStack(spacing: 8) {
                    Text("Life Scoreboard")
                        .font(.system(size: 34, weight: .bold))
                    
                    Text("3 Weeks Remaining")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.green)
                        .cornerRadius(20)
                    
                    Text(yearLabel())
                        .font(.system(size: 15, weight: .regular))
                    
                }
                .padding(.bottom, 4)
                
                OnTimeCard(onTime: viewModel.onTime, travel: viewModel.travel)

                // Team Members section
                TeamMembersCard(
                    honorThreshold: viewModel.onTime,
                    travelThreshold: viewModel.travel
                ) { entry, row in
                    selectedEntry = entry
                    selectedRow = row
                }
                    .environmentObject(viewModel)
                    .environmentObject(userManager)

                // Activity Table
                ActivityCard(activity: $viewModel.activity) { entry, row in
                    selectedEntry = entry
                    selectedRow = row
                }
                    .environmentObject(viewModel)
                    .environmentObject(userManager)
            }
            .padding()
        }
        .onAppear {
            viewModel.load(for: userManager.userList)
        }
        .onReceive(userManager.$userList) { names in
            viewModel.load(for: names)
        }
        .refreshable {
            userManager.refresh()
            viewModel.load(for: userManager.userList)
        }
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.gray.opacity(0.3), Color.gray]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .sheet(isPresented: Binding<Bool>(
            get: { selectedEntry != nil && selectedRow != nil },
            set: { if !$0 {
                selectedEntry = nil
                selectedRow = nil
            }}
        )) {
            if let entry = selectedEntry,
               let row = selectedRow {
                ScoreboardEditorOverlay(
                    entry: entry,
                    row: row
                ) {
                    selectedEntry = nil
                    selectedRow = nil
                }
                .environmentObject(viewModel)
            }
        }
    }
}

// MARK: - Subviews

private struct ScoreBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            .background(color)
            .cornerRadius(8)
    }
}

private struct ScoreTile<Content: View>: View {
    var verticalPadding: CGFloat = 16
    var horizontalPadding: CGFloat = 16
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(uiColor: .secondarySystemBackground))
                .shadow(radius: 4)

            content()
                .padding(.vertical, verticalPadding)
                .padding(.horizontal, horizontalPadding)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct OnTimeCard: View {
    let onTime: Double
    let travel: Double

    var body: some View {
        ScoreTile {
            HStack(alignment: .center) {
                VStack(spacing: 2) {
                    Text("Honor")
                        .font(.system(size: 17, weight: .semibold))
                    ScoreBadge(text: String(format: "%.1f", onTime), color: .yellow)
                }

                Spacer()

                Text("On Time")
                    .font(.system(size: 24, weight: .bold))

                Spacer()

                VStack(spacing: 2) {
                    Text("Travel")
                        .font(.system(size: 17, weight: .semibold))
                    ScoreBadge(text: String(format: "%.1f", travel), color: .green)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}
private struct TeamMembersCard: View {
    @EnvironmentObject var viewModel: LifeScoreboardViewModel
    @EnvironmentObject var userManager: UserManager
    let honorThreshold: Double
    let travelThreshold: Double
    var onSelect: (LifeScoreboardViewModel.ScoreEntry, LifeScoreboardViewModel.ActivityRow) -> Void

    private func color(for score: Double) -> Color {
        if score >= travelThreshold { return .green }
        if score >= honorThreshold { return .yellow }
        return .gray
    }

    var body: some View {
        let sortedNames = userManager.userList.sorted { lhs, rhs in
            viewModel.score(for: lhs) > viewModel.score(for: rhs)
        }

        return ScoreTile(verticalPadding: 8) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Team")
                    .font(.system(size: 20, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .center)

                ForEach(sortedNames, id: \.self) { name in
                    if let entry = viewModel.scores.first(where: { $0.name == name }),
                       let row = viewModel.row(for: name) {
                        TeamMemberRow(
                            entry: entry,
                            color: color(for: Double(entry.score)),
                            isCurrentUser: name == userManager.currentUser
                        ) {
                            onSelect(entry, row)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}



private struct TeamMemberRow: View {
    var entry: LifeScoreboardViewModel.ScoreEntry
    let color: Color
    let isCurrentUser: Bool
    var onEdit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Text(entry.name)
                    .font(.system(size: 20, weight: .regular, design: .rounded))
                if isCurrentUser {
                    Image(systemName: "pencil")
                }
            }

            ProgressView(value: Double(entry.score) / 100)
                .tint(color)
                .animation(.easeInOut(duration: 0.4), value: entry.score)
                .frame(height: 8)
                .frame(maxWidth: .infinity)

            Text("\(entry.score)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .frame(width: 35, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            if isCurrentUser { onEdit() }
        }
    }
}

private struct ActivityCard: View {
    @Binding var activity: [LifeScoreboardViewModel.ActivityRow]
    @EnvironmentObject var viewModel: LifeScoreboardViewModel
    @EnvironmentObject var userManager: UserManager
    var onSelect: (LifeScoreboardViewModel.ScoreEntry, LifeScoreboardViewModel.ActivityRow) -> Void

    var body: some View {
        let sortedRows = userManager.userList
            .compactMap { viewModel.row(for: $0) }
            .sorted { $0.projected > $1.projected }

        return ScoreTile(verticalPadding: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Activity")
                    .font(.system(size: 20, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .center)

                HStack(spacing: 6) {
                    Text("Name")
                        .font(.system(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Pending")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 70, alignment: .center)
                        .layoutPriority(1)
                    Text("Projected")
                        .font(.system(size: 17, weight: .bold))
                        .frame(minWidth: 110, alignment: .trailing)
                }

                ForEach(sortedRows) { row in
                    let isCurrent = row.name == userManager.currentUser
                    ActivityRowView(row: row, isCurrentUser: isCurrent) {
                        if let entry = viewModel.scores.first(where: { $0.name == row.name }) {
                            onSelect(entry, row)
                        }
                    }
                    .background(Color(.systemGray6))
                    .cornerRadius(6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ActivityRowView: View {
    @ObservedObject var row: LifeScoreboardViewModel.ActivityRow
    let isCurrentUser: Bool
    var onEdit: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(row.name)
                .font(.system(size: 21, weight: .regular))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(row.pending)")

                .font(.system(size: 15, weight: .regular))
                .frame(width: 70, alignment: .center)
                .layoutPriority(1)
                .monospacedDigit()
            Text(row.projected, format: .currency(code: "USD").precision(.fractionLength(0)))
                .font(.system(size: 17, weight: .regular))                .foregroundColor(.green)
                .frame(minWidth: 110, alignment: .trailing)
                .monospacedDigit()
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            if isCurrentUser { onEdit() }
        }
    }
}

