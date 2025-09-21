import SwiftUI
import Foundation

// MARK: - EditingOverlayView
private struct EditingOverlayView: View {
    @EnvironmentObject var viewModel: WinTheDayViewModel
    @Binding var member: TeamMember
    let field: String
    @Binding var editingMemberID: UUID?
    @Binding var recentlyCompletedIDs: Set<UUID>
    @Binding var isAwaitingDelayedReorder: Bool
    let onSave: ((UUID?, String) -> Void)?
    let onCelebration: ((UUID, String) -> Void)?
    let onConfetti: ((UUID) -> Void)?
    @State private var oldQuotesValue: Int = 0
    @State private var oldSalesWTDValue: Int = 0
    @State private var oldSalesMTDValue: Int = 0

    var body: some View {
        bodyContent
    }

    private var bodyContent: some View {
        VStack(spacing: 15) {
            fieldStepper
            buttonRow
        }
        .padding()
        .frame(width: 280)
        .background(Color(uiColor: .systemBackground))
        .cornerRadius(12)
        .shadow(radius: 8)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.4)))
        .onAppear {
            // Store ALL old values when editing starts
            oldQuotesValue = member.quotesToday
            oldSalesWTDValue = member.salesWTD
            oldSalesMTDValue = member.salesMTD
        }
    }

    private var buttonRow: some View {
        HStack {
            Button("Cancel") {
                // Restore original values when canceling
                member.quotesToday = oldQuotesValue
                member.salesWTD = oldSalesWTDValue
                member.salesMTD = oldSalesMTDValue
                editingMemberID = nil
                // Don't trigger any reordering when canceling
            }
            Spacer()
            Button("Save") {
                // Mark that we are entering the delayed-reorder window BEFORE dismissing the editor
                isAwaitingDelayedReorder = true
                let capturedID = editingMemberID
                let capturedField = field
                editingMemberID = nil // ✅ Dismiss immediately (after flag set)

                // Only trigger reordering if values actually changed
                let valuesChanged = (member.quotesToday != oldQuotesValue) ||
                                   (member.salesWTD != oldSalesWTDValue) ||
                                   (member.salesMTD != oldSalesMTDValue)
                if valuesChanged {

                    viewModel.saveWinTheDayFieldsDebounced(member)
                    onSave?(capturedID, capturedField)
                    let shouldCelebrate = checkIfAnyProgressTurnedGreen()
                    let didCompleteAnyGoal = checkIfAnyGoalCompleted()
                    
                    if shouldCelebrate {
                        onCelebration?(member.id, "any") // 🎉 small burst
                    }
                    if didCompleteAnyGoal {
                        onConfetti?(member.id)           // 🎊 confetti big celebration
                    }
                } else {

                }
            }
        }
    }

    // MARK: - Field stepper using FieldStepperRow
    @ViewBuilder
    private var fieldStepper: some View {
        FieldStepperRow(label: "Quotes WTD", value: $member.quotesToday)
        FieldStepperRow(label: "Sales WTD", value: $member.salesWTD)
        FieldStepperRow(label: "Sales MTD", value: $member.salesMTD)
    }
    
    // Helper functions to check progress color changes
    private func getCurrentValue(for field: String, member: TeamMember) -> Int {
        switch field {
        case "quotesToday": return member.quotesToday
        case "salesWTD": return member.salesWTD
        case "salesMTD": return member.salesMTD
        default: return 0
        }
    }
    
    private func getGoal(for field: String, member: TeamMember) -> Int {
        switch field {
        case "quotesToday": return member.quotesGoal
        case "salesWTD": return member.salesWTDGoal
        case "salesMTD": return member.salesMTDGoal
        default: return 0
        }
    }
    
    // Check if ANY of the three progress lines turned green
    private func checkIfAnyProgressTurnedGreen() -> Bool {
        // Check quotes progress
        let oldQuotesColor = progressColor(for: "quotesToday", value: oldQuotesValue, goal: member.quotesGoal)
        let newQuotesColor = progressColor(for: "quotesToday", value: member.quotesToday, goal: member.quotesGoal)
        let quotesTurnedGreen = oldQuotesColor != .green && newQuotesColor == .green
        
        // Check sales WTD progress
        let oldSalesWTDColor = progressColor(for: "salesWTD", value: oldSalesWTDValue, goal: member.salesWTDGoal)
        let newSalesWTDColor = progressColor(for: "salesWTD", value: member.salesWTD, goal: member.salesWTDGoal)
        let salesWTDTurnedGreen = oldSalesWTDColor != .green && newSalesWTDColor == .green
        
        // Check sales MTD progress
        let oldSalesMTDColor = progressColor(for: "salesMTD", value: oldSalesMTDValue, goal: member.salesMTDGoal)
        let newSalesMTDColor = progressColor(for: "salesMTD", value: member.salesMTD, goal: member.salesMTDGoal)
        let salesMTDTurnedGreen = oldSalesMTDColor != .green && newSalesMTDColor == .green
        
        // Return true if ANY line turned green
        return quotesTurnedGreen || salesWTDTurnedGreen || salesMTDTurnedGreen
    }
    
    private func checkIfAnyGoalCompleted() -> Bool {
        let quotesCompleted   = (oldQuotesValue < member.quotesGoal)   && (member.quotesToday >= member.quotesGoal)
        let salesWTDCompleted = (oldSalesWTDValue < member.salesWTDGoal) && (member.salesWTD >= member.salesWTDGoal)
        let salesMTDCompleted = (oldSalesMTDValue < member.salesMTDGoal) && (member.salesMTD >= member.salesMTDGoal)
        return quotesCompleted || salesWTDCompleted || salesMTDCompleted
    }
    
    private func progressColor(for field: String, value: Int, goal: Int) -> Color {
        guard goal > 0 else { return .gray }
        
        let calendar = Calendar.current
        let today = Date()
        
        let isOnTrack: Bool
        switch field {
        case "quotesToday", "salesWTD":
            let weekday = calendar.component(.weekday, from: today)
            let dayOfWeek = max(weekday - 1, 1)
            let expected = Double(goal) * Double(dayOfWeek) / 7.0
            isOnTrack = Double(value) >= expected
        case "salesMTD":
            let dayOfMonth = calendar.component(.day, from: today)
            let totalDays = calendar.range(of: .day, in: .month, for: today)?.count ?? 30
            let expected = Double(goal) * Double(dayOfMonth) / Double(totalDays)
            isOnTrack = Double(value) >= expected
        default:
            isOnTrack = false
        }
        
        return isOnTrack ? .green : .yellow
    }
}


// MARK: - FieldStepperRow
private struct FieldStepperRow: View {
    let label: String
    @Binding var value: Int
    var range: ClosedRange<Int> = 0...10_000

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
            Spacer()
            Stepper(value: $value, in: range) {
                Text("\(value)")
                    .monospacedDigit()
                    .frame(minWidth: 36, alignment: .trailing)
            }
            .accessibilityLabel(Text("\(label) value"))
        }
    }
}
