
import SwiftUI
import CloudKit
import Foundation

struct UserSelectorView: View {
    @AppStorage("selectedUserName") private var selectedUserName: String = ""
    @State private var navigateToWin = false
    @StateObject private var viewModel = WinTheDayViewModel()

    let users = ["D.J.", "Ron", "Deanna", "Dimitri"]

    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Text("Who Are You?")
                    .font(.largeTitle.bold())
                    .padding(.top, 60)
                ForEach(users, id: \.self) { name in
                    Button(action: {
                        selectedUserName = name
                        navigateToWin = true
                    }) {
                        Text(name)
                            .font(.title2.bold())
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.red)
                            .cornerRadius(10)
                    }
                }
                Spacer()
                NavigationLink(
                    destination: MainTabView(),
                    isActive: $navigateToWin
                ) {
                    EmptyView()
                    Text("→ Go")
                        .opacity(0)
                }
                Spacer()
            }
            .padding(.horizontal)
            .navigationBarHidden(true)
        }
    }
}

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

struct WinTheDayView: View {
    @StateObject var viewModel: WinTheDayViewModel
    @AppStorage("selectedUserName") private var selectedUserName: String = ""
    @State private var selectedMember: TeamMember?
    @State private var shimmerPosition: CGFloat = 0
    @State private var editingMemberID: UUID?
    @State private var editingField: String = ""
    @State private var editingValue: Int = 0
    @State private var emojiPickerVisible = false
    @State private var emojiEditingID: UUID?
    @State private var recentlyCompletedIDs: Set<UUID> = []





var body: some View {
    print("🏁 WinTheDayView body loaded")
    return contentVStack
        .background(winTheDayBackground)
        .overlay(winTheDayEditingOverlay)
}

private var contentVStack: some View {
    VStack(spacing: 20) {
        header
        teamCardsList
        fallbackMessage
        Spacer()
    }
    .onAppear { onAppearContent }
    .sheet(isPresented: $emojiPickerVisible) {
        emojiPickerSheet
    }
}

private var winTheDayBackground: some View {
    backgroundLayer
}

private var winTheDayEditingOverlay: some View {
    editingOverlay
}

// Split out onAppear logic for clarity and compile speed
private var onAppearContent: Void {
    print("🟢 onAppear triggered — calling loadData()")
    viewModel.loadData()
    print("🔍 Selected User: \(selectedUserName)")
    print("🧮 Team Data Count After Load: \(viewModel.teamMembers.count)")

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        // Live-resort based on actual values
        viewModel.teamMembers.sort {
            ($0.quotesToday + $0.salesWTD + $0.salesMTD) >
            ($1.quotesToday + $1.salesWTD + $1.salesMTD)
        }
        // Assign and persist sortIndex
        for (i, member) in viewModel.teamMembers.enumerated() {
            viewModel.teamMembers[i].sortIndex = i
            CloudKitManager().save(viewModel.teamMembers[i]) { _ in }
        }
        // Force refresh to apply reordered list
        viewModel.teamMembers = viewModel.teamMembers.map { $0 }
    }

    withAnimation(Animation.linear(duration: 2.5).repeatForever(autoreverses: false)) {
        shimmerPosition = 1.0
    }
}

private var header: some View {
    HStack {
        Text("Win the Day")
            .font(.largeTitle.bold())
            .frame(maxWidth: .infinity, alignment: .leading)
        Menu {
            Button("Change Activity") {}
            Button("Change Goal") {}
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
    ScrollView {
        VStack(spacing: 10) {
            ForEach($viewModel.teamMembers) { $member in
                TeamMemberCardView(
                    member: $member,
                    isEditable: member.name == selectedUserName,
                    selectedUserName: selectedUserName,
                    onEdit: {
                        if member.name == selectedUserName {
                            editingMemberID = member.id
                        }
                    },
                    recentlyCompletedIDs: $recentlyCompletedIDs,
                    teamData: $viewModel.teamMembers
                )
            }
        }
        .padding(.horizontal, 20)
        .animation(.easeInOut, value: viewModel.teamMembers.map { $0.id })
    }
}



private var fallbackMessage: some View {
    Group {
        if viewModel.teamMembers.isEmpty {
            Text("No team data found. Try adding a sample card.")
                .foregroundColor(.red)
                .padding()
        }
    }
}

private var backgroundLayer: some View {
    ZStack {
        backgroundGradient(for: viewModel.teamMembers).ignoresSafeArea()
        LinearGradient(
            gradient: Gradient(colors: [
                Color.white.opacity(0.0),
                Color.white.opacity(0.25),
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
    }
}

private var editingOverlay: some View {
    Group {
        if let editingID = editingMemberID,
           let index = viewModel.teamMembers.firstIndex(where: { $0.id == editingID }) {
            let binding = Binding(
                get: { viewModel.teamMembers[index] },
                set: {
                    viewModel.teamMembers[index] = $0
                    viewModel.teamMembers.sort {
                        ($0.quotesToday + $0.salesWTD + $0.salesMTD) >
                        ($1.quotesToday + $1.salesWTD + $1.salesMTD)
                    }
                    for (i, member) in viewModel.teamMembers.enumerated() {
                        viewModel.teamMembers[i].sortIndex = i
                        CloudKitManager().save(viewModel.teamMembers[i]) { _ in }
                    }
                }
            )
            EditingOverlayView(
                member: binding,
                field: editingField,
                editingMemberID: $editingMemberID,
                recentlyCompletedIDs: $recentlyCompletedIDs
            )
        }
    }
}

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
    let emojis = ["😀", "🎯", "🏆", "🎓", "💯", "🔥", "🎉", "💡", "📈", "📅"]
    return ScrollView {
        LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(emojis.chunked(into: 5), id: \.self) { row in
                HStack {
                    ForEach(row, id: \.self) { emoji in
                        Button(action: {
                            if let id = emojiEditingID,
                               let index = viewModel.teamMembers.firstIndex(where: { $0.id == id }) {
                                viewModel.teamMembers[index].emoji = emoji
                                CloudKitManager().save(viewModel.teamMembers[index]) { _ in }
                                viewModel.teamMembers = viewModel.teamMembers.map { $0 }
                            }
                            emojiPickerVisible = false
                        }) {
                            Text(emoji).font(.largeTitle)
                        }
                    }
                }
            }
        }
    }
}

    // Add isEditable parameter to TeamCard
    private func TeamCard(member: Binding<TeamMember>, isEditable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                if isEditable {
                    Button(action: {
                        emojiEditingID = member.wrappedValue.id
                        emojiPickerVisible = true
                    }) {
                        Text(member.wrappedValue.emoji)
                            .font(.title2.bold())
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    Text(member.wrappedValue.emoji)
                        .font(.title2.bold())
                }
                HStack(spacing: 6) {
                    Text(member.wrappedValue.name)
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

            if let index = viewModel.teamMembers.firstIndex(where: { $0.id == member.wrappedValue.id }) {
                let memberBinding = Binding(
                    get: { viewModel.teamMembers[index] },
                    set: { viewModel.teamMembers[index] = $0 }
                )
                if isEditable {
                    StatRow(
                        title: "Quotes WTD",
                        value: member.wrappedValue.quotesToday,
                        goal: member.wrappedValue.quotesGoal,
                        isEditable: true,
                        member: memberBinding,
                        recentlyCompletedIDs: $recentlyCompletedIDs,
                        teamData: $viewModel.teamMembers
                    ) {
                        editingMemberID = member.wrappedValue.id
                        editingField = "quotesToday"
                        editingValue = member.wrappedValue.quotesToday
                    }
                    StatRow(
                        title: "Sales WTD",
                        value: member.wrappedValue.salesWTD,
                        goal: member.wrappedValue.salesWTDGoal,
                        isEditable: true,
                        member: memberBinding,
                        recentlyCompletedIDs: $recentlyCompletedIDs,
                        teamData: $viewModel.teamMembers
                    ) {
                        editingMemberID = member.wrappedValue.id
                        editingField = "salesWTD"
                        editingValue = member.wrappedValue.salesWTD
                    }
                    StatRow(
                        title: "Sales MTD",
                        value: member.wrappedValue.salesMTD,
                        goal: member.wrappedValue.salesMTDGoal,
                        isEditable: true,
                        member: memberBinding,
                        recentlyCompletedIDs: $recentlyCompletedIDs,
                        teamData: $viewModel.teamMembers
                    ) {
                        editingMemberID = member.wrappedValue.id
                        editingField = "salesMTD"
                        editingValue = member.wrappedValue.salesMTD
                    }
                } else {
                    StatRow(
                        title: "Quotes WTD",
                        value: member.wrappedValue.quotesToday,
                        goal: member.wrappedValue.quotesGoal,
                        isEditable: false,
                        member: memberBinding,
                        recentlyCompletedIDs: $recentlyCompletedIDs,
                        teamData: $viewModel.teamMembers
                    ) {}
                    StatRow(
                        title: "Sales WTD",
                        value: member.wrappedValue.salesWTD,
                        goal: member.wrappedValue.salesWTDGoal,
                        isEditable: false,
                        member: memberBinding,
                        recentlyCompletedIDs: $recentlyCompletedIDs,
                        teamData: $viewModel.teamMembers
                    ) {}
                    StatRow(
                        title: "Sales MTD",
                        value: member.wrappedValue.salesMTD,
                        goal: member.wrappedValue.salesMTDGoal,
                        isEditable: false,
                        member: memberBinding,
                        recentlyCompletedIDs: $recentlyCompletedIDs,
                        teamData: $viewModel.teamMembers
                    ) {}
                }
            }
        }
        .padding(6)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(radius: 2)
        .frame(maxWidth: .infinity)
        // Remove any .frame(height: ...) modifiers here to avoid overlap
        .padding(.horizontal, 0) // line 362
        .overlay(
            VStack {
                Spacer()
                if recentlyCompletedIDs.contains(member.wrappedValue.id) {
                    Text("🎉")
                        .font(.system(size: 40))
                        .scaleEffect(1.4)
                        .transition(.scale)
                        .padding(.bottom, 30)
                }
            }
            .animation(.easeOut(duration: 0.4), value: recentlyCompletedIDs.contains(member.wrappedValue.id))
        )
    }



// MARK: - StatRow View
struct StatRow: View {
    let title: String
    let value: Int
    let goal: Int
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
                    .fill(progressColor(for: title, value: value, goal: goal))
                    .frame(
                        width: goal > 0 ? min(CGFloat(value) / CGFloat(goal), 1.0) * 140 : 0,
                        height: 10
                    )
                    .padding(.leading, 10)
            }

            Text("\(value) / \(goal)")
                .font(.subheadline.bold())
                .foregroundColor(.black)
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
            let color = progressColor(for: title, value: newValue, goal: goal)
            if color == .green {
                if let index = teamData.firstIndex(where: { $0.id == member.id }) {
                    recentlyCompletedIDs.insert(teamData[index].id)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        recentlyCompletedIDs.remove(teamData[index].id)
                    }
                }
            }
        }
    }

    private func progressColor(for title: String, value: Int, goal: Int) -> Color {
        guard goal > 0 else { return .gray }

        let calendar = Calendar.current
        let today = Date()

        let isOnTrack: Bool

        switch title {
        case "Quotes Today", "Quotes WTD", "Sales WTD":
            let weekday = calendar.component(.weekday, from: today)
            let dayOfWeek = max(weekday - 1, 1)
            let expected = Double(goal) * Double(dayOfWeek) / 7.0
            isOnTrack = Double(value) >= expected

        case "Sales MTD":
            let dayOfMonth = calendar.component(.day, from: today)
            let totalDays = calendar.range(of: .day, in: .month, for: today)?.count ?? 30
            let expected = Double(goal) * Double(dayOfMonth) / Double(totalDays)
            isOnTrack = Double(value) >= expected

        default:
            return .gray
        }

        return isOnTrack ? .green : .yellow
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
            CloudKitManager().save(viewModel.teamMembers[index]) { _ in }
        }
        // Force update to trigger SwiftUI redraw
        viewModel.teamMembers = viewModel.teamMembers.map { $0 }
    }

    // Background gradient based on team progress
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

    private func progressColor(for title: String, value: Int, goal: Int) -> Color {
        guard goal > 0 else { return .gray }

        let calendar = Calendar.current
        let today = Date()

        let isOnTrack: Bool

        switch title {
        case "Quotes Today", "Quotes WTD", "Sales WTD":
            let weekday = calendar.component(.weekday, from: today)
            let dayOfWeek = max(weekday - 1, 1)
            let expected = Double(goal) * Double(dayOfWeek) / 7.0
            isOnTrack = Double(value) >= expected

        case "Sales MTD":
            let dayOfMonth = calendar.component(.day, from: today)
            let totalDays = calendar.range(of: .day, in: .month, for: today)?.count ?? 30
            let expected = Double(goal) * Double(dayOfMonth) / Double(totalDays)
            isOnTrack = Double(value) >= expected

        default:
            return .gray
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


// MARK: - EditingOverlayView

private struct EditingOverlayView: View {
    @Binding var member: TeamMember
    let field: String
    @Binding var editingMemberID: UUID?
    @Binding var recentlyCompletedIDs: Set<UUID>

    var body: some View {
        VStack(spacing: 15) {
            fieldStepper
            HStack {
                Button("Cancel") {
                    editingMemberID = nil
                }
                Spacer()
                Button("Save") {
                    CloudKitManager().save(member) { newRecordID in
                        if let newRecordID = newRecordID {
                            member.id = UUID(uuidString: newRecordID.recordName) ?? member.id
                        }
                        DispatchQueue.main.async {
                            if let i = WinTheDayViewModel.shared?.teamMembers.firstIndex(where: { $0.id == member.id }) {
                                WinTheDayViewModel.shared?.teamMembers[i] = member
                            }

                            if let teamMembers = WinTheDayViewModel.shared?.teamMembers {
                                let sorted = teamMembers.sorted {
                                    ($0.quotesToday + $0.salesWTD + $0.salesMTD) >
                                    ($1.quotesToday + $1.salesWTD + $1.salesMTD)
                                }
                                for (i, member) in sorted.enumerated() {
                                    WinTheDayViewModel.shared?.teamMembers[i] = member
                                    WinTheDayViewModel.shared?.teamMembers[i].sortIndex = i
                                    CloudKitManager().save(WinTheDayViewModel.shared!.teamMembers[i]) { _ in }
                                }
                                WinTheDayViewModel.shared?.teamMembers = sorted.map { $0 }
                            }

                            editingMemberID = nil
                        }
                    }
                }
            }
        }
        .padding()
        .frame(width: 280)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(radius: 8)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.4)))
    }

    // MARK: - Split out the stepper based on field
    @ViewBuilder
    private var fieldStepper: some View {
        if field == "quotesToday" {
            HStack {
                Text("Quotes WTD")
                Stepper(value: $member.quotesToday, in: 0...1000) {
                    Text("\(member.quotesToday)")
                }
            }
        } else if field == "salesWTD" {
            HStack {
                Text("Sales WTD")
                Stepper(value: $member.salesWTD, in: 0...1000) {
                    Text("\(member.salesWTD)")
                }
            }
        } else if field == "salesMTD" {
            HStack {
                Text("Sales MTD")
                Stepper(value: $member.salesMTD, in: 0...1000) {
                    Text("\(member.salesMTD)")
                }
            }
        }
    }
}


private struct TeamMemberCardView: View {
    @Binding var member: TeamMember
    let isEditable: Bool
    let selectedUserName: String
    let onEdit: () -> Void
    @Binding var recentlyCompletedIDs: Set<UUID>
    @Binding var teamData: [TeamMember]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                if isEditable {
                    Button(action: onEdit) {
                        Text(member.emoji)
                            .font(.title2.bold())
                    }
                    .buttonStyle(PlainButtonStyle())
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
                title: "Quotes WTD",
                value: member.quotesToday,
                goal: member.quotesGoal,
                isEditable: isEditable,
                member: $member,
                recentlyCompletedIDs: $recentlyCompletedIDs,
                teamData: $teamData,
                onTap: { if isEditable { onEdit() } }
            )
            StatRow(
                title: "Sales WTD",
                value: member.salesWTD,
                goal: member.salesWTDGoal,
                isEditable: isEditable,
                member: $member,
                recentlyCompletedIDs: $recentlyCompletedIDs,
                teamData: $teamData,
                onTap: { if isEditable { onEdit() } }
            )
            StatRow(
                title: "Sales MTD",
                value: member.salesMTD,
                goal: member.salesMTDGoal,
                isEditable: isEditable,
                member: $member,
                recentlyCompletedIDs: $recentlyCompletedIDs,
                teamData: $teamData,
                onTap: { if isEditable { onEdit() } }
            )
        }
        .padding(6)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(radius: 2)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 0)
        .overlay(
            VStack {
                Spacer()
                if recentlyCompletedIDs.contains(member.id) {
                    Text("🎉")
                        .font(.system(size: 40))
                        .scaleEffect(1.4)
                        .transition(.scale)
                        .padding(.bottom, 30)
                }
            }
            .animation(.easeOut(duration: 0.4), value: recentlyCompletedIDs.contains(member.id))
        )
    }
}
