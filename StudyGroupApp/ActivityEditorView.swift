import SwiftUI

struct ActivityEditorView: View {
    @ObservedObject var row: LifeScoreboardViewModel.ActivityRow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text(row.name)
                .font(.headline)

            VStack(spacing: 12) {
                HStack {
                    Text("Pending Apps:")
                    Spacer()
                    Stepper("\(row.pending)", value: $row.pending, in: 0...100)
                }

                HStack {
                    Text("Projected Premium:")
                    Spacer()
                    TextField("$0", value: $row.projected, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)

            Button("Save") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
