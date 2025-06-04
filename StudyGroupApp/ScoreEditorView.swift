import SwiftUI

struct ScoreboardEditorOverlay: View {
    let entry: LifeScoreboardViewModel.ScoreEntry?
    let row: LifeScoreboardViewModel.ActivityRow?
    var dismiss: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            if let entry = entry {
                VStack(spacing: 12) {
                    Text(entry.name)
                        .font(.headline)

                    HStack {
                        Text("Score:")
                        Spacer()
                        Stepper("\(entry.score)", value: .constant(entry.score)) // read-only fallback
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
                }
            }

            if let row = row {
                VStack(spacing: 12) {
                    Text(row.name)
                        .font(.headline)

                    HStack {
                        Text("Pending Apps:")
                        Spacer()
                        Stepper("\(row.pending)", value: .constant(row.pending)) // read-only fallback
                    }

                    HStack {
                        Text("Projected Premium:")
                        Spacer()
                        TextField("$0", value: .constant(row.projected), format: .currency(code: "USD"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 120)
                    }
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)
            }

            Button("Save") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(.thinMaterial)
        .cornerRadius(16)
        .padding()
    }
}
