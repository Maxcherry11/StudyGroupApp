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
                
                // On Time section
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("On Time")
                            .font(.title3.bold())
                        Text("LOH")
                            .font(.subheadline)
                        Text("17.7")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.yellow)
                            .cornerRadius(8)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Travel")
                            .font(.subheadline)
                        Text("31.0")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green)
                            .cornerRadius(8)
                    }
                }
                
                // Team Members section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Team Members")
                        .font(.title3.bold())
                    let teamScores: [(String, Int, Color)] = [
                        ("Dimitri", 60, .green),
                        ("Deanna", 41, .green),
                        ("D.J.", 19, .yellow),
                        ("Ron", 12, Color.gray.opacity(0.3)),
                        ("Greg", 7, Color.gray.opacity(0.2))
                    ]
                    ForEach(teamScores, id: \.0) { name, score, color in
                        HStack {
                            Text(name)
                            Spacer()
                            Text("\(score)")
                                .font(.subheadline.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(color)
                                .cornerRadius(8)
                        }
                    }
                }
                
                // Activity Table
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
                    
                    ForEach($viewModel.activity) { $row in
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
                            .background(Color(.systemGray6))
                            .cornerRadius(6)
                        }
                    }
                }
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
