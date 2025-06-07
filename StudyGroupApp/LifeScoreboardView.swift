import SwiftUI

struct ScoreboardEditorOverlay: View {
    @Binding var entry: LifeScoreboardViewModel.ScoreEntry
    @ObservedObject var row: LifeScoreboardViewModel.ActivityRow
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text(entry.name)
                .font(.title.bold())

            VStack(spacing: 12) {
                HStack {
                    Text("Score:")
                    Spacer()
                    Stepper("", value: $entry.score, in: 0...100)
                }

                Divider()

                HStack {
                    Text("Pending Apps:")
                    Spacer()
                    Stepper("", value: $row.pending, in: 0...100)
                }

                HStack {
                    Text("Projected Premium:")
                    Spacer()
                    TextField("Projected Premium", value: $row.projected, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .submitLabel(.done)
                }
            }

            HStack(spacing: 16) {
                Button("Cancel") {
                    onDismiss()
                }
                .buttonStyle(.bordered)

                Button("Save") {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(maxWidth: 400)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(radius: 10)
        .padding()
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
                TeamMembersCard()
                    .environmentObject(viewModel)
                    .environmentObject(userManager)

                // Activity Table
                ActivityCard(activity: $viewModel.activity)
                    .environmentObject(viewModel)
                    .environmentObject(userManager)
            }
            .padding()
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
                    entry: .constant(entry),
                    row: row
                ) {
                    selectedEntry = nil
                    selectedRow = nil
                }
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
                .fill(Color.white)
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

    var body: some View {
        ScoreTile(verticalPadding: 8) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Team")
                    .font(.system(size: 20, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .center)

                ForEach(Array(userManager.allUsers.enumerated()), id: \.1) { index, name in
                    let color: Color = {
                        switch index {
                        case 0, 1:
                            return .green
                        case 2:
                            return .yellow
                        case 3:
                            return Color.gray.opacity(0.3)
                        default:
                            return Color.gray.opacity(0.2)
                        }
                    }()

                    let score = viewModel.score(for: name)
                    let isCurrent = name == userManager.currentUserName
                    TeamMemberRow(name: name, score: score, color: color, isCurrentUser: isCurrent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}



private struct TeamMemberRow: View {
    let name: String
    let score: Int
    let color: Color
    let isCurrentUser: Bool

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                Text(name)
                    .font(.system(size: 17, weight: .regular))
                if isCurrentUser {
                    Image(systemName: "pencil")
                }
            }
            Spacer()
            ScoreBadge(text: "\(score)", color: color)
        }
        .padding(.vertical, 2)
    }
}

private struct ActivityCard: View {
    @Binding var activity: [LifeScoreboardViewModel.ActivityRow]
    @EnvironmentObject var viewModel: LifeScoreboardViewModel
    @EnvironmentObject var userManager: UserManager

    var body: some View {
        ScoreTile(verticalPadding: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Activity")
                    .font(.system(size: 20, weight: .bold))

                HStack {
                    Text("Name")
                        .font(.system(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Pending")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 70, alignment: .center)
                    Text("Projected")
                        .font(.system(size: 16, weight: .bold))
                        .frame(minWidth: 100, alignment: .trailing)
                }

                ForEach(userManager.allUsers, id: \.self) { name in
                    if let row = viewModel.row(for: name) {
                        ActivityRowView(row: row)
                            .background(Color(.systemGray6))
                            .cornerRadius(6)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ActivityRowView: View {
    @ObservedObject var row: LifeScoreboardViewModel.ActivityRow

    var body: some View {
        if let entry = row.entries.first {
            HStack {
                Text(entry.name)
                    .font(.system(size: 15, weight: .regular))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(row.pending)")
                    .font(.system(size: 15, weight: .regular))
                    .frame(width: 70, alignment: .center)
                    .monospacedDigit()
                Text(row.projected, format: .currency(code: "USD"))
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.green)
                    .frame(minWidth: 100, alignment: .trailing)
                    .monospacedDigit()
            }
            .padding(.vertical, 6)
        }
    }
}

