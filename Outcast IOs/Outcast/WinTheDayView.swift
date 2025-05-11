import SwiftUI
import CloudKit

struct UserSelectorView: View {
    @AppStorage("selectedUserName") private var selectedUserName: String = ""
    @State private var navigateToWin = false

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
                NavigationLink(
                    destination: WinTheDayView(viewModel: WinTheDayViewModel()),
                    isActive: $navigateToWin
                ) {
                    EmptyView()
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
    @ObservedObject var viewModel: WinTheDayViewModel
    @AppStorage("selectedUserName") private var selectedUserName: String = ""
    @State private var selectedMember: TeamMember?
    @State private var shimmerPosition: CGFloat = 0
    @State private var editingMemberID: UUID?
    @State private var editingField: String = ""
    @State private var editingValue: Int = 0
    @State private var emojiPickerVisible = false
    @State private var emojiEditingID: UUID?
    @State private var recentlyCompletedIDs: Set<UUID> = []

    private var team: [TeamMember] {
        viewModel.teamData
    }

//    // Sorted team by sum of quotesToday, salesWTD, salesMTD (descending)
//    private var sortedTeam: [TeamMember] {
//        team.sorted {
//            ($0.quotesToday + $0.salesWTD + $0.salesMTD) >
//            ($1.quotesToday + $1.salesWTD + $1.salesMTD)
//        }
//    }

var body: some View {
    mainContent
}

private var mainContent: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Win the Day")
                    .font(.largeTitle.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)

                Menu {
                    Button(action: {
                        // Handle change activity action
                    }) {
                        Text("Change Activity")
                        Image(systemName: "circle")
                    }
                    Button(action: {
                        // Handle change goal action
                    }) {
                        Text("Change Goal")
                        Image(systemName: "circle")
                    }
                    Button(action: resetValues) {
                        Text("Reset")
                            .foregroundColor(.red)
                        Image(systemName: "trash.fill")
                    }
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.title2)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            // Animate card reordering in ScrollView
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(team) { member in
                        // Only allow tap/edit if the card is for the logged-in user
                        if member.name == selectedUserName {
                            Button(action: {
                                selectedMember = member
                            }) {
                                TeamCard(member: member, isEditable: true)
                            }
                            .buttonStyle(PlainButtonStyle())
                        } else {
                            TeamCard(member: member, isEditable: false)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .animation(.easeInOut, value: team.map { $0.id }) // Animate changes to team order
            }

            Spacer()
        }
        .background(
            ZStack {
                backgroundGradient(for: team).ignoresSafeArea()
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
        )
        .onAppear {
            withAnimation(Animation.linear(duration: 2.5).repeatForever(autoreverses: false)) {
                shimmerPosition = 1.0
            }
        }
        .overlay(
            Group {
                if let editingID = editingMemberID,
                   let member = team.first(where: { $0.id == editingID }) {
                    EditingOverlayView(
                        member: member,
                        field: editingField,
                        editingMemberID: $editingMemberID,
                        recentlyCompletedIDs: $recentlyCompletedIDs,
                        teamData: $viewModel.teamData
                    )
                }
            }
        )
        .sheet(isPresented: $emojiPickerVisible) {
            VStack(spacing: 20) {
                Text("Choose Your Emoji").font(.headline)
                let emojis = [
                    "😀", "😃", "😄", "😁", "😆", "😅", "😂", "🤣", "😊", "😇",
                    "🙂", "🙃", "😉", "😌", "😍", "😘", "😗", "😙", "😚", "😋",
                    "😜", "🤪", "😝", "🤑", "🤗", "🤭", "🤫", "🤔", "🤐", "😶",
                     "👩🏾", "👧🏽", "👨🏾", "👩🏿", "👩🏾‍🦱", "👱🏽‍♂️", "👨🏽‍🦲", "👨🏽‍💻",
                    "🧓🏾", "👴🏻", "👮🏽‍♂️", "👷🏾‍♀️", "💂🏿", "🕵🏻‍♂️", "👩🏼‍⚕️", "👨🏽‍🎓", "👩🏻‍🏫",
                    "👨🏾‍🏭", "👩🏿‍💻", "👨🏻‍💼", "👩🏼‍🔧", "👨🏽‍🔬", "👩🏾‍🎤", "👨🏾‍🦱", "👨🏿‍🦱", "👩🏽‍⚖️",
                    "🧑🏾‍🌾", "🧑🏿‍🍳", "🧑🏻‍🎨", "🧑🏼‍🔬", "🧑🏽‍✈️", "🧑🏾‍🚀", "🧑🏿‍⚖️", "🧑🏻‍⚕️", "🧑🏼‍🎓", "🧑🏽‍🏫",
                    "❤️", "🧡", "💛", "💚", "💙", "💜", "🤎", "🖤", "🤍", "💯",
                    "🌟", "⭐", "✨", "🔥", "🎉", "🎯", "🏆", "🎖", "🎓", "🎬",
                    "🎧", "🎮", "🎨", "🎼", "🕹", "🧠", "📚", "💡", "📈", "📅"
                ]
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(emojis.chunked(into: 8), id: \.self) { row in
                            HStack {
                                ForEach(row, id: \.self) { emoji in
                                    Button(action: {
                                        if let id = emojiEditingID,
                                           let index = team.firstIndex(where: { $0.id == id }) {
                                            viewModel.teamData[index].emoji = emoji
                                        }
                                        emojiPickerVisible = false
                                    }) {
                                        Text(emoji)
                                            .font(.largeTitle)
                                    }
                                }
                            }
                        }
                    }
                }
                Button("Cancel") {
                    emojiPickerVisible = false
                }
            }
            .padding()
        }
    }

    // Add isEditable parameter to TeamCard
    private func TeamCard(member: TeamMember, isEditable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                if isEditable {
                    Button(action: {
                        emojiEditingID = member.id
                        emojiPickerVisible = true
                    }) {
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

            if isEditable {
                StatRow(
                    title: "Quotes Today",
                    value: member.quotesToday,
                    goal: member.quotesGoal,
                    isEditable: true,
                    member: member,
                    recentlyCompletedIDs: $recentlyCompletedIDs,
                    teamData: $viewModel.teamData
                ) {
                    editingMemberID = member.id
                    editingField = "quotesToday"
                    editingValue = member.quotesToday
                }
                StatRow(
                    title: "Sales WTD",
                    value: member.salesWTD,
                    goal: member.salesWTDGoal,
                    isEditable: true,
                    member: member,
                    recentlyCompletedIDs: $recentlyCompletedIDs,
                    teamData: $viewModel.teamData
                ) {
                    editingMemberID = member.id
                    editingField = "salesWTD"
                    editingValue = member.salesWTD
                }
                StatRow(
                    title: "Sales MTD",
                    value: member.salesMTD,
                    goal: member.salesMTDGoal,
                    isEditable: true,
                    member: member,
                    recentlyCompletedIDs: $recentlyCompletedIDs,
                    teamData: $viewModel.teamData
                ) {
                    editingMemberID = member.id
                    editingField = "salesMTD"
                    editingValue = member.salesMTD
                }
            } else {
                StatRow(
                    title: "Quotes Today",
                    value: member.quotesToday,
                    goal: member.quotesGoal,
                    isEditable: false,
                    member: member,
                    recentlyCompletedIDs: $recentlyCompletedIDs,
                    teamData: $viewModel.teamData
                ) {}
                StatRow(
                    title: "Sales WTD",
                    value: member.salesWTD,
                    goal: member.salesWTDGoal,
                    isEditable: false,
                    member: member,
                    recentlyCompletedIDs: $recentlyCompletedIDs,
                    teamData: $viewModel.teamData
                ) {}
                StatRow(
                    title: "Sales MTD",
                    value: member.salesMTD,
                    goal: member.salesMTDGoal,
                    isEditable: false,
                    member: member,
                    recentlyCompletedIDs: $recentlyCompletedIDs,
                    teamData: $viewModel.teamData
                ) {}
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

    // Add isEditable parameter to StatRow and celebration logic
    private func StatRow(
        title: String,
        value: Int,
        goal: Int,
        isEditable: Bool,
        member: TeamMember,
        recentlyCompletedIDs: Binding<Set<UUID>>,
        teamData: Binding<[TeamMember]>,
        onTap: @escaping () -> Void
    ) -> some View {
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

            // Always show the stat text with consistent styling
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
                if let index = teamData.wrappedValue.firstIndex(where: { $0.id == member.id }) {
                    recentlyCompletedIDs.wrappedValue.insert(teamData.wrappedValue[index].id)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        recentlyCompletedIDs.wrappedValue.remove(teamData.wrappedValue[index].id)
                    }
                }
            }
        }
    }

    // Reset function to reset values
    private func resetValues() {
        for index in team.indices {
            viewModel.teamData[index].quotesToday = 0
            viewModel.teamData[index].salesWTD = 0
            viewModel.teamData[index].salesMTD = 0
        }
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

        switch title {
        case "Quotes Today", "Sales WTD":
            let weekday = calendar.component(.weekday, from: today)
            let dayOfWeek = max(weekday - 1, 1)
            let pace = Double(goal) * Double(dayOfWeek) / 7.0
            return Double(value) >= pace ? .green : .yellow

        case "Sales MTD":
            let dayOfMonth = calendar.component(.day, from: today)
            let totalDays = calendar.range(of: .day, in: .month, for: today)?.count ?? 30
            let pace = Double(goal) * Double(dayOfMonth) / Double(totalDays)
            return Double(value) >= pace ? .green : .yellow

        default:
            return .gray
        }
    }
}

struct TeamMember: Identifiable, Codable {
    var id = UUID()
    var name: String
    var quotesToday: Int
    var salesWTD: Int
    var salesMTD: Int
    var quotesGoal: Int = 10
    var salesWTDGoal: Int = 2
    var salesMTDGoal: Int = 8
    
    var emoji: String {
        get {
            UserDefaults.standard.string(forKey: "emoji-\(name)") ?? "🕶️"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "emoji-\(name)")
        }
    }
    
//    init(from record: CKRecord) {
//        self.id = UUID(uuidString: record.recordID.recordName) ?? UUID()
//        self.name = record["name"] as? String ?? ""
//        self.quotesToday = record["quotesToday"] as? Int ?? 0
//        self.salesWTD = record["salesWTD"] as? Int ?? 0
//        self.salesMTD = record["salesMTD"] as? Int ?? 0
//        self.quotesGoal = record["quotesGoal"] as? Int ?? 10
//        self.salesWTDGoal = record["salesWTDGoal"] as? Int ?? 2
//        self.salesMTDGoal = record["salesMTDGoal"] as? Int ?? 8
//    }
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
        case "Quotes Today": return member.quotesToday
        case "Sales WTD": return member.salesWTD
        case "Sales MTD": return member.salesMTD
        default: return 0
        }
    }

    // Helper: Get goal for a stat title and member
    private func goalFor(_ title: String, of member: TeamMember) -> Int {
        switch title {
        case "Quotes Today": return member.quotesGoal
        case "Sales WTD": return member.salesWTDGoal
        case "Sales MTD": return member.salesMTDGoal
        default: return 0
        }
    }


// MARK: - EditingOverlayView

private struct EditingOverlayView: View {
    let member: TeamMember
    let field: String
    @Binding var editingMemberID: UUID?
    @Binding var recentlyCompletedIDs: Set<UUID>
    @Binding var teamData: [TeamMember]

    var body: some View {
        VStack(spacing: 15) {
            if field == "quotesToday" {
                HStack {
                    Text("Quotes Today")
                    Stepper(value: $teamData[index].quotesToday, in: 0...1000) {
                        Text("\(teamData[index].quotesToday)")
                    }
                }
            } else if field == "salesWTD" {
                HStack {
                    Text("Sales WTD")
                    Stepper(value: $teamData[index].salesWTD, in: 0...1000) {
                        Text("\(teamData[index].salesWTD)")
                    }
                }
            } else if field == "salesMTD" {
                HStack {
                    Text("Sales MTD")
                    Stepper(value: $teamData[index].salesMTD, in: 0...1000) {
                        Text("\(teamData[index].salesMTD)")
                    }
                }
            }

            HStack {
                Button("Cancel") {
                    editingMemberID = nil
                }
                Spacer()
                Button("Save") {
                    // Handle progress logic here if needed
                    editingMemberID = nil
                    withAnimation(.easeInOut) {
                        teamData.sort {
                            ($0.quotesToday + $0.salesWTD + $0.salesMTD) >
                            ($1.quotesToday + $1.salesWTD + $1.salesMTD)
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

    private var index: Int {
        teamData.firstIndex(where: { $0.id == member.id }) ?? 0
    }
}
