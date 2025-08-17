
import SwiftUI
import CloudKit
import Foundation


struct DashboardView: View {
    var body: some View {
        Text("Dashboard")
            .font(.largeTitle)
            .padding()
    }
}

struct SettingsView: View {
    var body: some View {
        Text("Settings")
            .font(.largeTitle)
            .padding()
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape( RoundedCorner(radius: radius, corners: corners) )
    }
}

enum StatType {
    case quotes
    case salesWTD
    case salesMTD
}

struct WinTheDayView: View {
    @StateObject var viewModel: WinTheDayViewModel
    @EnvironmentObject var userManager: UserManager
    @ObservedObject private var cloud = CloudKitManager.shared
    @State private var shimmerPosition: CGFloat = 0
    @State private var editingMemberID: UUID?
    @State private var editingField: String = ""
    @State private var editingValue: Int = 0
    @State private var emojiPickerVisible = false
    @State private var emojiEditingID: UUID?
    @State private var recentlyCompletedIDs: Set<UUID> = []
    @State private var celebrationMemberID: UUID?
    @State private var celebrationField: String = ""
    // Keep editing state active during the delayed reorder window after Save
    @State private var isAwaitingDelayedReorder: Bool = false
    // Cache for frozen order while editing popup is open
    @State private var frozenOrderIDs: [UUID] = []
    // Production Goal Editor State
    @State private var showProductionGoalEditor = false
    @State private var newQuotesGoal = 10
    @State private var newSalesWTDGoal = 2
    @State private var newSalesMTDGoal = 6
    // Goal Name Editor State
    @State private var showGoalNameEditor = false
    @State private var editingQuotesLabel = ""
    @State private var editingSalesWTDLabel = ""
    @State private var editingSalesMTDLabel = ""
    @State private var didRunInitialSync = false
    // Caches for splash-to-dashboard transition
    @State private var lastNonEmptyMembers: [TeamMember] = []
    @State private var lastNonEmptyTeamData: [TeamMember] = []

    // Removed computed properties to avoid compiler type-checking issues

    // DEBUG: order logging
    @State private var enableOrderLogs = true
    private func logOrder(_ label: String, _ members: [TeamMember]) {
        guard enableOrderLogs else { return }
        let names = members.map { $0.name }.joined(separator: ", ")
        print("🧭 [WinTheDay] \(label): [\(names)]")
    }

    // Break up the large body chain for compiler performance
    private var lifecycleWrapped: some View {
        VStack(spacing: 20) {
            header
            teamCardsList
            fallbackMessage
            Spacer()
        }
        .overlay(editingOverlay)
        .background(winTheDayBackground)
        // Removed the subtle animation to reduce type-checking complexity
        .onAppear {
            handleOnAppear()
        }
        .onChange(of: userManager.currentUser) { _ in
            viewModel.loadCardOrderFromCloud(for: userManager.currentUser)
        }
        .onChange(of: userManager.userList) { names in
            viewModel.fetchMembersFromCloud { [weak viewModel] in
                viewModel?.ensureCardsForAllUsers(names)
            }
        }
        .onChange(of: viewModel.isLoaded) { loaded in
            guard loaded else { return }
            viewModel.fetchMembersFromCloud { [weak viewModel] in
                viewModel?.ensureCardsForAllUsers(userManager.userList)
            }
        }
        .onChange(of: viewModel.teamMembers.map { $0.id }) { _ in
            let members = viewModel.teamMembers
            if !members.isEmpty { lastNonEmptyMembers = members }
        }
        .onChange(of: viewModel.teamData.map { $0.id }) { _ in
            let data = viewModel.teamData
            if !data.isEmpty { lastNonEmptyTeamData = data }
            if enableOrderLogs { logOrder("teamData changed", data) }
        }
        .onChange(of: editingMemberID) { newValue in
            if newValue == nil {
                if isAwaitingDelayedReorder {
                    // Keep frozen through the delayed reorder window to avoid intermediate resort
                    if enableOrderLogs { print("🧭 [WinTheDay] Edit popup closed — keeping FROZEN during delayed reorder window") }
                } else {
                    // UNFREEZE after the edit sheet dismisses (Save or Cancel) when no delayed reorder is pending
                    if enableOrderLogs { print("🧭 [WinTheDay] Edit popup closed - UNFREEZING order") }
                    frozenOrderIDs.removeAll()
                    viewModel.isEditing = false
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("WinTheDayManualRefresh"))) { _ in
            viewModel.fetchMembersFromCloud()
            viewModel.fetchGoalNamesFromCloud()
        }
    }

    var body: some View {
        AnyView(
            lifecycleWrapped
                .sheet(isPresented: $emojiPickerVisible) {
                    emojiPickerSheet
                }
                .sheet(isPresented: $showProductionGoalEditor) {
                    // Existing content kept as-is
                    VStack(spacing: 20) {
                        Text("Edit Production Goals")
                            .font(.headline)
                        Stepper("Quotes Goal: \(newQuotesGoal)", value: $newQuotesGoal, in: 1...100)
                        Stepper("Sales WTD Goal: \(newSalesWTDGoal)", value: $newSalesWTDGoal, in: 1...100)
                        Stepper("Sales MTD Goal: \(newSalesMTDGoal)", value: $newSalesMTDGoal, in: 1...100)
                        HStack {
                            Button("Cancel") { showProductionGoalEditor = false }
                            Spacer()
                            Button("Save") {
                                for index in viewModel.teamMembers.indices {
                                    viewModel.teamMembers[index].quotesGoal = newQuotesGoal
                                    viewModel.teamMembers[index].salesWTDGoal = newSalesWTDGoal
                                    viewModel.teamMembers[index].salesMTDGoal = newSalesMTDGoal
                                    viewModel.saveMember(viewModel.teamMembers[index])
                                }
                                viewModel.teamMembers = viewModel.teamMembers.map { $0 }
                                showProductionGoalEditor = false
                            }
                        }
                        .padding(.top, 10)
                    }
                    .padding()
                }
                .sheet(isPresented: $showGoalNameEditor) {
                    VStack(spacing: 20) {
                        Text("Edit Goal Names")
                            .font(.headline)
                        TextField("Quotes Label", text: $editingQuotesLabel)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        TextField("Sales WTD Label", text: $editingSalesWTDLabel)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        TextField("Sales MTD Label", text: $editingSalesMTDLabel)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        HStack {
                            Button("Cancel") { showGoalNameEditor = false }
                            Spacer()
                            Button("Save") {
                                viewModel.saveGoalNames(
                                    quotes: editingQuotesLabel,
                                    salesWTD: editingSalesWTDLabel,
                                    salesMTD: editingSalesMTDLabel
                                )
                                showGoalNameEditor = false
                            }
                        }
                        .padding(.top, 10)
                    }
                    .padding()
                    .onAppear {
                        editingQuotesLabel = viewModel.goalNames.quotes
                        editingSalesWTDLabel = viewModel.goalNames.salesWTD
                        editingSalesMTDLabel = viewModel.goalNames.salesMTD
                    }
                }
        )
    }

@ViewBuilder
private func editingSheet(for editingID: UUID) -> some View {
    if let index = viewModel.teamMembers.firstIndex(where: { $0.id == editingID }) {
        let binding = Binding(
            get: { viewModel.teamMembers[index] },
            set: { viewModel.teamMembers[index] = $0 }
        )
        EditingOverlayView(
            member: binding,
            field: editingField,
            editingMemberID: $editingMemberID,
            recentlyCompletedIDs: $recentlyCompletedIDs,
            isAwaitingDelayedReorder: $isAwaitingDelayedReorder,
            onSave: { _, _ in
                // Always delay card movement to ensure consistent behavior
                // This gives time for celebrations to complete and prevents visual glitches
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    handleSaveAndReorder()
                }
                // Don't update teamMembers here - let the delayed reordering handle it
            },
            onCelebration: { memberID, field in
                triggerCelebration(for: memberID, field: field)
            }
        )
        .environmentObject(viewModel)
    }
}

private var contentVStack: some View {
    VStack(spacing: 20) {
        header
        teamCardsList
        fallbackMessage
        Spacer()
    }
}

private var editingOverlay: some View {
    Group {
        if let editingID = editingMemberID,
           let index = viewModel.teamMembers.firstIndex(where: { $0.id == editingID }) {
            EditingOverlayView(
                member: Binding(
                    get: { viewModel.teamMembers[index] },
                    set: { viewModel.teamMembers[index] = $0 }
                ),
                field: editingField,
                editingMemberID: $editingMemberID,
                recentlyCompletedIDs: $recentlyCompletedIDs,
                isAwaitingDelayedReorder: $isAwaitingDelayedReorder,
                onSave: { _, _ in
                    // Always delay card movement to ensure consistent behavior
                    // This gives time for celebrations to complete and prevents visual glitches
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        handleSaveAndReorder()
                    }
                    // Don't update teamMembers here - let the delayed reordering handle it
                },
                onCelebration: { memberID, field in
                    triggerCelebration(for: memberID, field: field)
                }
            )
            .environmentObject(viewModel)
            .transition(.scale)
            .zIndex(100)
        }
    }
}

    // Function to trigger celebration animation
    private func triggerCelebration(for memberID: UUID, field: String) {
        celebrationMemberID = memberID
        celebrationField = field
        
        // Auto-hide celebration after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            celebrationMemberID = nil
            celebrationField = ""
        }
    }

private var winTheDayBackground: some View {
    backgroundLayer
}

// Removed winTheDayEditingOverlay and editingOverlay

// Split out onAppear logic for clarity and compile speed


private var header: some View {
    HStack {
        Text("Win the Day")
            .font(.largeTitle.bold())
            .frame(maxWidth: .infinity, alignment: .leading)
        Menu {
            Button("Edit Goal Names") {
                showGoalNameEditor = true
            }
            Button("Edit Production Goals") {
                showProductionGoalEditor = true
            }
            Divider()
            Button(role: .destructive, action: resetValues) {
                Label("Reset", systemImage: "trash.fill")
            }
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.title2)
        }
    }
    .padding(.horizontal, 20)
    .padding(.top, 20)
}


private var teamCardsList: some View {
    TeamCardsListView(
        teamMembers: $viewModel.teamMembers,
        teamData: $viewModel.teamData,
        lastNonEmptyTeamData: $lastNonEmptyTeamData,
        currentUser: userManager.currentUser,
        goalNames: (quotes: viewModel.goalNames.quotes, salesWTD: viewModel.goalNames.salesWTD, salesMTD: viewModel.goalNames.salesMTD),
        editingMemberID: $editingMemberID,
        editingField: $editingField,
        emojiPickerVisible: $emojiPickerVisible,
        emojiEditingID: $emojiEditingID,
        recentlyCompletedIDs: $recentlyCompletedIDs,
        celebrationMemberID: $celebrationMemberID,
        celebrationField: $celebrationField,
        splashOrder: userManager.userList,
        // Keep list in frozen mode while edit sheet is open OR while we are waiting to reorder after Save
        isEditing: (editingMemberID != nil) || isAwaitingDelayedReorder,
        frozenOrderIDs: frozenOrderIDs,
        freezeNow: { ids in
            // Freeze immediately at tap time to avoid any mid-frame resort
            frozenOrderIDs = ids
            viewModel.isEditing = true
            if enableOrderLogs {
                let base = viewModel.teamData.isEmpty ? lastNonEmptyTeamData : viewModel.teamData
                let names = base.map { $0.name }.joined(separator: ", ")
                print("🧭 [WinTheDay] FREEZE at tap -> [\(names)]")
            }
        }
    )
}



private var fallbackMessage: some View {
    Group {
        if (viewModel.teamData.isEmpty ? lastNonEmptyTeamData : viewModel.teamData).isEmpty {
            EmptyView()
        }
    }
}

private var backgroundLayer: some View {
    ZStack {
        backgroundGradient(for: viewModel.teamMembers.isEmpty ? lastNonEmptyMembers : viewModel.teamMembers).ignoresSafeArea()

        // Existing shimmer overlay
        LinearGradient(
            gradient: Gradient(colors: [
                Color.white.opacity(0.0),
                Color.white.opacity(0.10),
                Color.white.opacity(0.0)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(width: 400)
        .rotationEffect(.degrees(30))
        .offset(x: shimmerPosition * 600)
        .blendMode(.overlay)
        .ignoresSafeArea()

        // Restored true shimmer beam overlay (diagonal, plusLighter blend)
        LinearGradient(
            gradient: Gradient(colors: [
                Color.white.opacity(0.0),
                Color.white.opacity(0.18),
                Color.white.opacity(0.0)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(width: 300)
        .offset(x: shimmerPosition * UIScreen.main.bounds.width)
        .rotationEffect(.degrees(25))
        .blendMode(.plusLighter)
        .ignoresSafeArea()
    }
}

// Removed editingOverlayContent, editingOverlayBody, and editingOverlay

private var emojiPickerSheet: some View {
    AnyView(
        VStack(spacing: 20) {
            Text("Choose Your Emoji").font(.headline)
            emojiGrid
            Button("Cancel") {
                emojiPickerVisible = false
            }
        }
        .padding()
    )
}


private var emojiGrid: some View {
    let emojis = [
        "👨🏽‍🦲", "👨🏾‍🦲", "👨🏿‍🦲",
        "😐", "🙂", "😊", "😌", "😎", "🤓",
        "😏", "😶", "🙃", "😬", "🤔", "😯",
        "🤨", "😄", "😅", "😇", "😍", "🤩",
        "🏃🏽‍♀️", "🏃🏾‍♀️", "🏃🏿‍♀️",
        "🏃🏽‍♂️", "🏃🏾‍♂️", "🏃🏿‍♂️",
        "🧔🏽", "🧔🏾", "🧔🏿",
        "👩🏽", "👩🏾", "👩🏿",
        "🧑🏽", "🧑🏾", "🧑🏿",
        "👨🏽", "👨🏾", "👨🏿",
        "👩🏽‍🦱", "👩🏾‍🦱", "👩🏿‍🦱",
        "👨🏽‍🦱", "👨🏾‍🦱", "👨🏿‍🦱",
        "👦🏾", "👧🏾", "👴🏾",
        "🤗", "🤝", "🫶🏾", "🙏🏾", "🤜🏾", "🤛🏾",
        "😤", "😠", "😡", "🥹", "😢", "😭"
    ]

    let columns = Array(repeating: GridItem(.flexible()), count: 6)

    return ScrollView {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(emojis, id: \.self) { emoji in
                Button(action: {
                    if let id = emojiEditingID,
                       let index = viewModel.teamMembers.firstIndex(where: { $0.id == id }) {
                        viewModel.teamMembers[index].emoji = emoji
                        viewModel.updateEmoji(for: viewModel.teamMembers[index])
                        viewModel.teamMembers = viewModel.teamMembers.map { $0 }
                    }
                    emojiPickerVisible = false
                }) {
                    Text(emoji)
                        .font(.system(size: 32))
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.vertical, 10)
    }
}

/// Handles saving edits and reordering cards with animation.
private func handleSaveAndReorder() {
    if enableOrderLogs {
        let before = viewModel.teamMembers
        logOrder("before SAVE+REORDER", before)
    }
    
    // Only reorder if we're not already in the correct order
    // This prevents unnecessary shuffling when the order hasn't actually changed
    let currentOrder = viewModel.teamMembers.map { $0.id }
    let expectedOrder = viewModel.teamMembers.sorted(by: viewModel.stableByScoreThenIndex).map { $0.id }
    
    let needsReordering = currentOrder != expectedOrder
    
    if needsReordering {
        if enableOrderLogs { print("🧭 [WinTheDay] Order changed, performing reorder with smooth animation") }
        
        // First save the data, then reorder with smooth animation
        withAnimation(.easeInOut(duration: 0.5)) {
            viewModel.reorderAfterSave()
        }
        
        if enableOrderLogs {
            let after = viewModel.teamMembers
            logOrder("after SAVE+REORDER", after)
        }
        viewModel.saveCardOrderToCloud(for: userManager.currentUser)
        
        // Force update to trigger SwiftUI redraw after reordering
        viewModel.teamMembers = viewModel.teamMembers.map { $0 }
    } else {
        if enableOrderLogs { print("🧭 [WinTheDay] No reordering needed - order is already correct") }
    }
    
    // Clear frozen state now that we are done
    frozenOrderIDs.removeAll()
    isAwaitingDelayedReorder = false
    // Always unfreeze the editing state after save (whether reordering happened or not)
    viewModel.isEditing = false
}

/// Handles the onAppear logic to avoid complex type-checking issues
private func handleOnAppear() {
    guard !didRunInitialSync else { return }
    didRunInitialSync = true

    viewModel.fetchGoalNamesFromCloud()
    viewModel.fetchMembersFromCloud { [weak viewModel] in
        viewModel?.ensureCardsForAllUsers(userManager.userList)
    }
    viewModel.loadCardOrderFromCloud(for: userManager.currentUser)
    shimmerPosition = -1.0
    withAnimation(Animation.linear(duration: 12).repeatForever(autoreverses: false)) {
        shimmerPosition = 1.5
    }
}




    // Reset function to reset values
    private func resetValues() {
        for index in viewModel.teamMembers.indices {
            // Only reset Win The Day specific progress values
            // Preserve Life Scoreboard fields (score, pending, projected, actual)
            viewModel.teamMembers[index].quotesToday = 0
            viewModel.teamMembers[index].salesWTD = 0
            viewModel.teamMembers[index].salesMTD = 0
            
            // Reset goals to default values
            viewModel.teamMembers[index].quotesGoal = 10
            viewModel.teamMembers[index].salesWTDGoal = 2
            viewModel.teamMembers[index].salesMTDGoal = 6
            
            print("🔁 Resetting Win The Day values for \(viewModel.teamMembers[index].name): Quotes Goal = \(viewModel.teamMembers[index].quotesGoal), WTD Goal = \(viewModel.teamMembers[index].salesWTDGoal), MTD Goal = \(viewModel.teamMembers[index].salesMTDGoal)")
            
            // Save only the Win The Day fields to avoid affecting Life Scoreboard data
            viewModel.saveWinTheDayFields(viewModel.teamMembers[index])
        }
        // Force update to trigger SwiftUI redraw
        viewModel.teamMembers = viewModel.teamMembers.map { $0 }
    }

    // New background gradient based on team progress
    private func backgroundGradient(for team: [TeamMember]) -> LinearGradient {
        var totalActual = 0
        var totalGoal = 0

        for member in team {
            totalActual += member.quotesToday + member.salesWTD + member.salesMTD
            totalGoal += member.quotesGoal + member.salesWTDGoal + member.salesMTDGoal
        }

        guard totalGoal > 0 else {
            return LinearGradient(
                gradient: Gradient(colors: [Color.gray.opacity(0.3), Color.gray]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        let percent = Double(totalActual) / Double(totalGoal)

        let colors: [Color]
        switch percent {
        case 0..<0.26:
            colors = [Color.red.opacity(0.3), Color.red]
        case 0.26..<0.51:
            colors = [Color.orange.opacity(0.3), Color.orange]
        case 0.51..<0.8:
            colors = [Color.yellow.opacity(0.3), Color.yellow]
        default:
            colors = [Color.green.opacity(0.0), Color.green]
        }

        return LinearGradient(
            gradient: Gradient(colors: colors),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func progressColor(for type: StatType, value: Int, goal: Int) -> Color {
        guard goal > 0 else { return .gray }

        let calendar = Calendar.current
        let today = Date()

        let isOnTrack: Bool

        switch type {
        case .quotes, .salesWTD:
            let weekday = calendar.component(.weekday, from: today)
            let dayOfWeek = max(weekday - 1, 1)
            let expected = Double(goal) * Double(dayOfWeek) / 7.0
            isOnTrack = Double(value) >= expected

        case .salesMTD:
            let dayOfMonth = calendar.component(.day, from: today)
            let totalDays = calendar.range(of: .day, in: .month, for: today)?.count ?? 30
            let expected = Double(goal) * Double(dayOfMonth) / Double(totalDays)
            isOnTrack = Double(value) >= expected
        }

        return isOnTrack ? .green : .yellow
    }
}

// MARK: - StatRow View
struct StatRow: View {
    let title: String
    let value: Int
    let goal: Int
    let type: StatType
    let isEditable: Bool
    @Binding var member: TeamMember
    @Binding var recentlyCompletedIDs: Set<UUID>
    @Binding var teamData: [TeamMember]
    let onTap: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline.bold())
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 140, height: 10)
                    .padding(.leading, 10)
                Capsule()
                    .fill(progressColor(for: type, value: value, goal: goal))
                    .frame(
                        width: goal > 0 ? min(CGFloat(value) / CGFloat(goal), 1.0) * 140 : 0,
                        height: 10
                    )
                    .padding(.leading, 10)
            }

            Text("\(value) / \(goal)")
                .font(.subheadline.bold())
                .foregroundColor(.primary)
                .lineLimit(1)
                .frame(width: 90, alignment: .trailing)
        }
        .frame(height: 26)
        .contentShape(Rectangle())
        .onTapGesture {
            if isEditable {
                onTap()
            }
        }
        .opacity(1.0)
        .onChange(of: value) { newValue in
            let oldColor = progressColor(for: type, value: newValue - 1, goal: goal)
            let newColor = progressColor(for: type, value: newValue, goal: goal)
            if oldColor != .green && newColor == .green {
                recentlyCompletedIDs.insert(member.id)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    recentlyCompletedIDs.remove(member.id)
                }
            }
        }
    }

    private func progressColor(for type: StatType, value: Int, goal: Int) -> Color {
        guard goal > 0 else { return .gray }

        let calendar = Calendar.current
        let today = Date()

        let isOnTrack: Bool
        switch type {
        case .quotes, .salesWTD:
            let weekday = calendar.component(.weekday, from: today)
            let dayOfWeek = max(weekday - 1, 1)
            let expected = Double(goal) * Double(dayOfWeek) / 7.0
            isOnTrack = Double(value) >= expected
        case .salesMTD:
            let dayOfMonth = calendar.component(.day, from: today)
            let totalDays = calendar.range(of: .day, in: .month, for: today)?.count ?? 30
            let expected = Double(goal) * Double(dayOfMonth) / Double(totalDays)
            isOnTrack = Double(value) >= expected
        }

        return isOnTrack ? .green : .yellow
    }
}


extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}


    // Helper: Get value for a stat title and member
    private func valueFor(_ title: String, of member: TeamMember) -> Int {
        switch title {
        case "Quotes Today", "Quotes WTD": return member.quotesToday
        case "Sales WTD": return member.salesWTD
        case "Sales MTD": return member.salesMTD
        default: return 0
        }
    }

    // Helper: Get goal for a stat title and member
    private func goalFor(_ title: String, of member: TeamMember) -> Int {
        switch title {
        case "Quotes Today", "Quotes WTD": return member.quotesGoal
        case "Sales WTD": return member.salesWTDGoal
        case "Sales MTD": return member.salesMTDGoal
        default: return 0
        }
    }
    




// MARK: - FieldStepperRow
private struct FieldStepperRow: View {
    let label: String
    @Binding var value: Int

    var body: some View {
        HStack {
            Text(label)
            Stepper(value: $value, in: 0...1000) {
                Text("\(value)")
            }
        }
    }
}

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
                    if true { print("🧭 [WinTheDay] SAVE pressed for member=\(member.name) — delaying reorder") }
                    viewModel.saveWinTheDayFields(member)
                    onSave?(capturedID, capturedField)
                    let shouldCelebrate = checkIfAnyProgressTurnedGreen()
                    if shouldCelebrate {
                        onCelebration?(member.id, "any")
                    }
                } else {
                    if true { print("🧭 [WinTheDay] SAVE pressed but no values changed — no reorder needed") }
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


private struct TeamMemberCardView: View {
    @Binding var member: TeamMember
    let isEditable: Bool
    let selectedUserName: String
    let onEdit: (String) -> Void
    @Binding var recentlyCompletedIDs: Set<UUID>
    @Binding var teamData: [TeamMember]
    let quotesLabel: String
    let salesWTDLabel: String
    let salesMTDLabel: String
    @Binding var celebrationMemberID: UUID?
    @Binding var celebrationField: String

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    if isEditable {
                        Button(action: { onEdit("emoji") }) {
                            Text(member.emoji)
                                .font(.title2.bold())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .contextMenu { }
                    } else {
                        Text(member.emoji)
                            .font(.title2.bold())
                    }
                    HStack(spacing: 6) {
                        Text(member.name)
                            .font(.title2.bold())
                        if isEditable {
                            Image(systemName: "pencil")
                                .foregroundColor(.white)
                        }
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 237/255, green: 29/255, blue: 36/255))
                .foregroundColor(.white)
                .cornerRadius(10, corners: [.topLeft, .topRight])

                StatRow(
                    title: quotesLabel,
                    value: member.quotesToday,
                    goal: member.quotesGoal,
                    type: .quotes,
                    isEditable: isEditable,
                    member: $member,
                    recentlyCompletedIDs: $recentlyCompletedIDs,
                    teamData: $teamData,
                    onTap: { if isEditable { onEdit("quotesToday") } }
                )
                StatRow(
                    title: salesWTDLabel,
                    value: member.salesWTD,
                    goal: member.salesWTDGoal,
                    type: .salesWTD,
                    isEditable: isEditable,
                    member: $member,
                    recentlyCompletedIDs: $recentlyCompletedIDs,
                    teamData: $teamData,
                    onTap: { if isEditable { onEdit("salesWTD") } }
                )
                StatRow(
                    title: salesMTDLabel,
                    value: member.salesMTD,
                    goal: member.salesMTDGoal,
                    type: .salesMTD,
                    isEditable: isEditable,
                    member: $member,
                    recentlyCompletedIDs: $recentlyCompletedIDs,
                    teamData: $teamData,
                    onTap: { if isEditable { onEdit("salesMTD") } }
                )
            }
            .padding(6)
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(12)
            .shadow(radius: 2)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 0)
            
            // Celebration overlay - only show if this is the celebrating member
            if celebrationMemberID == member.id {
                CelebrationView(field: celebrationField)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Celebration View
struct CelebrationView: View {
    let field: String
    @State private var scale: CGFloat = 0.0
    @State private var opacity: Double = 0.0
    
    var body: some View {
        VStack {
            Spacer()
            Text("🎉")
                .font(.system(size: 60))
                .scaleEffect(scale)
                .opacity(opacity)
                .onAppear {
                    // Start animation sequence
                    withAnimation(.easeOut(duration: 0.3)) {
                        scale = 1.2
                        opacity = 1.0
                    }
                    
                    // Scale down to normal size
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            scale = 1.0
                        }
                    }
                    
                    // Fade out
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        withAnimation(.easeIn(duration: 0.3)) {
                            opacity = 0.0
                        }
                    }
                }
            Spacer()
        }
    }
}
    

// MARK: - Extracted Team Cards List (lighter for the type checker)
private struct TeamCardsListView: View {
    @Binding var teamMembers: [TeamMember]
    @Binding var teamData: [TeamMember]
    @Binding var lastNonEmptyTeamData: [TeamMember]
    let currentUser: String
    let goalNames: (quotes: String, salesWTD: String, salesMTD: String)
    @Binding var editingMemberID: UUID?
    @Binding var editingField: String
    @Binding var emojiPickerVisible: Bool
    @Binding var emojiEditingID: UUID?
    @Binding var recentlyCompletedIDs: Set<UUID>
    @Binding var celebrationMemberID: UUID?
    @Binding var celebrationField: String
    let splashOrder: [String]
    let isEditing: Bool
    let frozenOrderIDs: [UUID]
    let freezeNow: ([UUID]) -> Void

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(dataSource, id: \.id) { member in
                        if let idx = teamMembers.firstIndex(where: { $0.name == member.name }) {
                            let isEditable = teamMembers[idx].name == currentUser
                        TeamMemberCardView(
                            member: $teamMembers[idx],
                            isEditable: isEditable,
                            selectedUserName: currentUser,
                            onEdit: { field in
                                guard isEditable else { return }
                                if true { print("🧭 [WinTheDay] onEdit tapped for \(member.name) field=\(field)") }
                                // Freeze immediately using the exact on-screen order to prevent any movement
                                freezeNow(dataSource.map { $0.id })
                                // Now proceed to open the editor
                                editingMemberID = member.id
                                editingField = field
                                if field == "emoji" {
                                    emojiPickerVisible = true
                                    emojiEditingID = member.id
                                    editingMemberID = nil
                                } else {
                                    withAnimation { scrollProxy.scrollTo(member.id, anchor: .center) }
                                }
                            },
                            recentlyCompletedIDs: $recentlyCompletedIDs,
                            teamData: $teamData,
                            quotesLabel: goalNames.quotes,
                            salesWTDLabel: goalNames.salesWTD,
                            salesMTDLabel: goalNames.salesMTD,
                            celebrationMemberID: $celebrationMemberID,
                            celebrationField: $celebrationField
                        )
                            .id(member.id)
                        }
                    }
                }
                .animation((!isEditing && frozenOrderIDs.isEmpty) ? .easeInOut(duration: 0.35) : nil, value: dataSource.map { $0.id })
                .padding(.horizontal, 20)
            }
            .transaction { t in
                if isEditing { t.disablesAnimations = true }
            }
            .refreshable {
                NotificationCenter.default.post(name: .init("WinTheDayManualRefresh"), object: nil)
            }
        }
    }

    private var dataSource: [TeamMember] {
        let base = teamData.isEmpty ? lastNonEmptyTeamData : teamData
        
        if true { print("🧭 [WinTheDay] dataSource evaluated - isEditing: \(isEditing), frozenOrderIDs.count: \(frozenOrderIDs.count)") }

        // STEP 2: If editing is active, use the frozen order to prevent any movement
        if isEditing || !frozenOrderIDs.isEmpty {
            if !frozenOrderIDs.isEmpty {
                let indexByID: [UUID:Int] = Dictionary(uniqueKeysWithValues: frozenOrderIDs.enumerated().map { ($1, $0) })
                if true {
                    let names = base.sorted { (indexByID[$0.id] ?? Int.max) < (indexByID[$1.id] ?? Int.max) }.map { $0.name }
                    print("🧭 [WinTheDay] dataSource=FROZEN (editing active) -> \(names)")
                }
                // Return the EXACT frozen order - no reordering, no changes
                return base.sorted { (indexByID[$0.id] ?? Int.max) < (indexByID[$1.id] ?? Int.max) }
            } else {
                // Fallback: if somehow we're editing but no frozen IDs, return base order unchanged
                if true { print("🧭 [WinTheDay] dataSource=FROZEN fallback -> \(base.map { $0.name })") }
                return base
            }
        }

        // STEP 4: Only apply normal ordering logic when NOT editing
        // Build a fast index map for Splash order
        let indexMap: [String:Int] = Dictionary(uniqueKeysWithValues: splashOrder.enumerated().map { ($1, $0) })

        // Split into members with any progress and those with zero progress
        let withProgress = base.filter { ($0.quotesToday + $0.salesWTD + $0.salesMTD) > 0 }
        let zeroProgress = base.filter { ($0.quotesToday + $0.salesWTD + $0.salesMTD) == 0 }

        if withProgress.isEmpty {
            // All zero progress - use splash order
            if true {
                let names = zeroProgress.sorted { (indexMap[$0.name] ?? Int.max) < (indexMap[$1.name] ?? Int.max) }.map { $0.name }
                print("🧭 [WinTheDay] dataSource=ALL_ZERO splash order -> \(names)")
            }
            return zeroProgress.sorted { (indexMap[$0.name] ?? Int.max) < (indexMap[$1.name] ?? Int.max) }
        } else {
            // Mixed progress - sort by score, then splash order for zeros
            let sortedProgress = withProgress.sorted { lhs, rhs in
                let l = lhs.quotesToday + lhs.salesWTD + lhs.salesMTD
                let r = rhs.quotesToday + rhs.salesWTD + rhs.salesMTD
                if l == r {
                    return (indexMap[lhs.name] ?? Int.max) < (indexMap[rhs.name] ?? Int.max)
                }
                return l > r
            }
            let sortedZeros = zeroProgress.sorted { (indexMap[$0.name] ?? Int.max) < (indexMap[$1.name] ?? Int.max) }
            
            if true {
                let progressNames = sortedProgress.map { $0.name }
                let zeroNames = sortedZeros.map { $0.name }
                print("🧭 [WinTheDay] dataSource=MIXED progressed -> \(progressNames), zeros(splash) -> \(zeroNames)")
            }
            
            return sortedProgress + sortedZeros
        }
    }
}
