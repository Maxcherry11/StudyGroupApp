
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
    @State private var selectedMember: TeamMember?
    @State private var shimmerPosition: CGFloat = 0
    @State private var editingMemberID: UUID?
    @State private var editingField: String = ""
    @State private var editingValue: Int = 0
    @State private var emojiPickerVisible = false
    @State private var emojiEditingID: UUID?
    @State private var recentlyCompletedIDs: Set<UUID> = []
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

    var body: some View {
        Group {
            if viewModel.isLoaded {
                contentVStack
                    .background(winTheDayBackground)
            } else {
                Color.clear
            }
        }
        .onAppear {
            viewModel.fetchMembersFromCloud()
            viewModel.fetchGoalNamesFromCloud()
            viewModel.ensureCardsForAllUsers(userManager.userList)
            shimmerPosition = -1.0
            withAnimation(Animation.linear(duration: 12).repeatForever(autoreverses: false)) {
                shimmerPosition = 1.5
            }
        }
    .onChange(of: userManager.currentUser) { _ in }
    .onChange(of: userManager.userList) { _ in
        if viewModel.isLoaded {
            viewModel.fetchMembersFromCloud()
        }
        viewModel.ensureCardsForAllUsers(userManager.userList)
    }
    .sheet(isPresented: $emojiPickerVisible) {
        emojiPickerSheet
    }
    .sheet(isPresented: $showProductionGoalEditor) {
        VStack(spacing: 20) {
            Text("Edit Production Goals")
                .font(.headline)

            Stepper("Quotes Goal: \(newQuotesGoal)", value: $newQuotesGoal, in: 1...100)
            Stepper("Sales WTD Goal: \(newSalesWTDGoal)", value: $newSalesWTDGoal, in: 1...100)
            Stepper("Sales MTD Goal: \(newSalesMTDGoal)", value: $newSalesMTDGoal, in: 1...100)

            HStack {
                Button("Cancel") {
                    showProductionGoalEditor = false
                }
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
                Button("Cancel") {
                    showGoalNameEditor = false
                }
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
            onSave: { _, _ in
                handleSaveAndReorder()
                viewModel.teamMembers = viewModel.teamMembers.map { $0 }
            }
        )
        .environmentObject(viewModel)
    }
}

private var contentVStack: some View {
    let headerSection = header
    let cardsSection = teamCardsList
    let fallbackSection = fallbackMessage

    return VStack(spacing: 20) {
        headerSection
        cardsSection
        fallbackSection
        Spacer()
    }
    .overlay(
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
                    onSave: { _, _ in
                        handleSaveAndReorder()
                        viewModel.teamMembers = viewModel.teamMembers.map { $0 }
                    }
                )
                .environmentObject(viewModel)
                .transition(.scale)
                .zIndex(100)
            }
        }
    )
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
    ScrollViewReader { scrollProxy in
        ScrollView {
            VStack(spacing: 10) {
                
                ForEach(viewModel.teamData, id: \.id) { member in
                    if let idx = viewModel.teamMembers.firstIndex(where: { $0.id == member.id }) {
                        let name = viewModel.teamMembers[idx].name
                        let isEditable = name == userManager.currentUser
                        TeamMemberCardView(
                            member: $viewModel.teamMembers[idx],
                        isEditable: isEditable,
                        selectedUserName: userManager.currentUser,
                        onEdit: { field in
                            if isEditable {
                                editingMemberID = member.id
                                editingField = field
                                if field == "emoji" {
                                    emojiPickerVisible = true
                                    emojiEditingID = member.id
                                    editingMemberID = nil
                                } else {
                                    withAnimation {
                                        scrollProxy.scrollTo(member.id, anchor: .center)
                                    }
                                }
                            }
                        },
                        recentlyCompletedIDs: $recentlyCompletedIDs,
                        teamData: $viewModel.teamData,
                        quotesLabel: viewModel.goalNames.quotes,
                        salesWTDLabel: viewModel.goalNames.salesWTD,
                        salesMTDLabel: viewModel.goalNames.salesMTD
                        )
                        .id(member.id)
                    }
                }
            }
            .padding(.horizontal, 20)
            .animation(.easeInOut, value: viewModel.teamData.map { $0.id })
        }
        .refreshable {
            viewModel.fetchMembersFromCloud()
            viewModel.fetchGoalNamesFromCloud()
            viewModel.ensureCardsForAllUsers(userManager.userList)
        }
    }
}



private var fallbackMessage: some View {
    Group {
        if viewModel.teamData.isEmpty {
            EmptyView()
        }
    }
}

private var backgroundLayer: some View {
    ZStack {
        backgroundGradient(for: viewModel.teamMembers).ignoresSafeArea()

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
    VStack(spacing: 20) {
        Text("Choose Your Emoji").font(.headline)
        emojiGrid
        Button("Cancel") {
            emojiPickerVisible = false
        }
    }
    .padding()
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
    withAnimation {
        viewModel.reorderAfterSave()
    }
}




    // Reset function to reset values
    private func resetValues() {
        for index in viewModel.teamMembers.indices {
            // Zero out progress values
            viewModel.teamMembers[index].quotesToday = 0
            viewModel.teamMembers[index].salesWTD = 0
            viewModel.teamMembers[index].salesMTD = 0
            viewModel.teamMembers[index].quotesGoal = 10
            viewModel.teamMembers[index].salesWTDGoal = 2
            viewModel.teamMembers[index].salesMTDGoal = 6
            print("🔁 Resetting \(viewModel.teamMembers[index].name): Quotes Goal = \(viewModel.teamMembers[index].quotesGoal), WTD Goal = \(viewModel.teamMembers[index].salesWTDGoal), MTD Goal = \(viewModel.teamMembers[index].salesMTDGoal)")
            viewModel.saveMember(viewModel.teamMembers[index])
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
        case 0:
            colors = [Color.gray.opacity(0.3), Color.gray]
        case 0..<0.25:
            colors = [Color.red.opacity(0.3), Color.red]
        case 0.25..<0.75:
            colors = [Color.yellow.opacity(0.3), Color.yellow]
        default:
            colors = [Color.green.opacity(0), Color.green]
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
    let onSave: ((UUID?, String) -> Void)?

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
    }

    private var buttonRow: some View {
        HStack {
            Button("Cancel") {
                editingMemberID = nil
            }
            Spacer()
            Button("Save") {
                let capturedID = editingMemberID
                let capturedField = field
                editingMemberID = nil // ✅ Dismiss immediately

                viewModel.saveEdits(for: member)
                onSave?(capturedID, capturedField)
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

    var body: some View {
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
    }
}
    
