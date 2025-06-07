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
    @State private var selectedEntry: LifeScoreboardViewModel.ScoreEntry?
    @State private var selectedRow: LifeScoreboardViewModel.ActivityRow?

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
                    
                    Text("First Year")
                        .font(.subheadline)
                    
                    Text("6/3/2025")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 4)
                
                OnTimeCard(onTime: viewModel.onTime, travel: viewModel.travel)

                // Team Members section
                TeamMembersCard()
                    .environmentObject(viewModel)

                // Activity Table
                ActivityCard(activity: $viewModel.activity)
            }
            .padding()
        }
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
            .font(.subheadline.bold())
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(color)
            .cornerRadius(8)
    }
}

private struct OnTimeCard: View {
    let onTime: Double
    let travel: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("On Time")
                .font(.title3.bold())

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LOH")
                        .font(.subheadline)
                    ScoreBadge(text: String(format: "%.1f", onTime), color: .yellow)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Travel")
                        .font(.subheadline)
                    ScoreBadge(text: String(format: "%.1f", travel), color: .green)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

private struct TeamMembersCard: View {
    @EnvironmentObject var viewModel: LifeScoreboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Team Members")
                .font(.title3.bold())

            ForEach(Array(zip(viewModel.scores.indices, viewModel.scores)), id: \.0) { index, entry in
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

                TeamMemberRow(name: entry.name, score: entry.score, color: color)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

private struct TeamMemberRow: View {
    let name: String
    let score: Int
    let color: Color

    var body: some View {
        HStack {
            Text(name)
            Spacer()
            ScoreBadge(text: "\(score)", color: color)
        }
    }
}

private struct ActivityCard: View {
    @Binding var activity: [LifeScoreboardViewModel.ActivityRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Activity")
                .font(.title3.bold())

            HStack {
                Text("Name").bold()
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Pending").bold()
                    .frame(width: 70, alignment: .center)
                Text("Projected").bold()
                    .frame(minWidth: 100, alignment: .trailing)
            }

            ForEach(activity) { row in
                ActivityRowView(row: row)
                    .background(Color(.systemGray6))
                    .cornerRadius(6)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

private struct ActivityRowView: View {
    @ObservedObject var row: LifeScoreboardViewModel.ActivityRow

    var body: some View {
        if let entry = row.entries.first {
            HStack {
                Text(entry.name)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(row.pending)")
                    .frame(width: 70, alignment: .center)
                    .monospacedDigit()
                Text(row.projected, format: .currency(code: "USD"))
                    .foregroundColor(.green)
                    .frame(minWidth: 100, alignment: .trailing)
                    .monospacedDigit()
            }
            .padding(.vertical, 8)
        }
    }
}

